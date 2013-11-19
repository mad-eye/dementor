events = require 'events'
net = require 'net'
{spawn, exec} = require 'child_process'
fs = require 'fs'
util = require 'util'
_path = require 'path'
Logger = require 'pince'

remoteAddr = '0.0.0.0' #FIXME: This accepts all IPV4 connections.  Generalize.

log = new Logger 'tunnelManager'
class TunnelManager extends events.EventEmitter
  constructor: (@tunnelHost) ->
    log.trace 'Constructing TunnelManager'
    @shuttingDown = false
    @tunnels = {}
    @Connection = require 'ssh2'
    @connections = {}
    @reconnectTimeouts = {}
    @backoffCounter = 2

    @connectionOptions =
      host: @tunnelHost
      port: 22
      username: 'prisoner'
      privateKey: null #Will be supplied later.

  setPrivateKey: (privateKey) ->
    @connectionOptions.privateKey = privateKey

  #@param tunnel: {name, localPort, remotePort}
  #@param hooks: map of event names to callbacks for that event
  startTunnel: (tunnel, hooks) ->
    log.debug "Starting tunnel #{tunnel.name} for local port #{tunnel.localPort}"
    tunnel.remotePort ?= 0
    @tunnels[tunnel.name] = tunnel
    @_openConnection tunnel, hooks

  #hooks: {close:->, error: (err)->, setupComplete: (remotePort)->}
  _openConnection: (tunnel, hooks) ->
    #Useful flag to disable known hosts checking: -oStrictHostKeyChecking=no
    @connections[tunnel.name] = connection = new @Connection
    connection.on 'connect', =>
      log.debug "Connected to #{@connectionOptions.host}"
    connection.on 'ready', =>
      log.trace "Tunnel #{tunnel.name} ready"
      clearTimeout @reconnectTimeouts[tunnel.name]
      delete @reconnectTimeouts[tunnel.name]
      @backoffCounter = 2
      log.trace "Requesting forwarding for remote port #{tunnel.remotePort}"
      connection.forwardIn remoteAddr, tunnel.remotePort, (err, remotePort) =>
        if err
          log.warn "Error opening tunnel #{tunnel.name}:", err
          #XXX: This will currently kill things
          connection.emit 'error', err
        else
          #remotePort isn't populated if we supplied it with a port.
          #So either tunnel.remotePort needs to be replaced with remotePort,
          #or vice-versa.
          if remotePort
            tunnel.remotePort = remotePort
          else
            remotePort = tunnel.remotePort
          log.debug "Remote forwarding port: #{remotePort}"
          hooks.setupComplete remotePort
    connection.on 'error', (err) =>
      if err.level == 'authentication'
        log.debug "Authentication error for tunnel #{tunnel.name}:", err
        hooks.error err
      else
        log.warn "Tunnel #{tunnel.name} had error:", err
    connection.on 'end', =>
      log.debug "Tunnel #{tunnel.name} ending"
    connection.on 'close', (hadError) =>
      log.debug "Tunnel #{tunnel.name} closing"
      hooks.close?()
      if hadError
        log.warn "Tunnel closing had error"
      unless @shuttingDown
        log.trace "Setting up reconnection timeout for #{tunnel.name}"
        clearTimeout @reconnectTimeouts[tunnel.name]
        @reconnectTimeouts[tunnel.name] = setTimeout =>
          log.trace "Trying to reopen tunnel #{tunnel.name}"
          @_openConnection tunnel, hooks
        , (@backoffCounter++)*1000
    connection.on 'debug', (msg) ->
      log.trace msg

    connection.on 'keyboard-interactive', ->
      log.debug "(keyboard-interactive)", arguments

    connection.on 'change password', ->
      log.debug "(change password)", arguments

    connection.on 'tcp connection', (info, accept, reject) =>
      log.trace "tcp incoming connection:", util.inspect info
      stream = accept()
      @_handleIncomingStream stream, tunnel

    connection.connect @connectionOptions

  _handleIncomingStream: (stream, {name, localPort}) ->
    stream.on 'data', (data) =>
      #log.trace "[#{name}] Data received"
      0
    stream.on 'end', =>
      log.trace "[#{name}] EOF"
    stream.on 'error', (err) =>
      log.warn "[#{name}] error:", err
    stream.on 'close', (hadErr) =>
      log.trace "[#{name}] closed", (if hadErr then "with error")

    log.trace "Pausing stream"
    stream.pause()
    log.trace "Forwarding to localhost:#{localPort}"
    socket = net.connect localPort, 'localhost', =>
      stream.pipe socket
      socket.pipe stream
      stream.resume()
      log.trace "Resuming stream"

  shutdown: (callback) ->
    log.trace 'Shutting down TunnelManager'
    @shuttingDown = true
    for name, connection in @connections
      log.trace "Killing tunnel #{name}"
      connection.end()
    process.nextTick (callback ? ->)

module.exports = TunnelManager

