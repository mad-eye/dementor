events = require 'events'
net = require 'net'
{spawn, exec} = require 'child_process'
fs = require 'fs'
util = require 'util'
_path = require 'path'
Logger = require 'pince'

ID_FILE_PATH = _path.normalize "#{__dirname}/../lib/id_rsa"
remoteAddr = '0.0.0.0' #FIXME: This accepts all IPV4 connections.  Generalize.

log = new Logger 'tunnelManager'
class TunnelManager extends events.EventEmitter
  constructor: (@tunnelHost) ->
    log.trace 'Constructing TunnelManager'
    @shuttingDown = false
    @tunnels = {}
    @Connection = require 'ssh2'
    @connections = {}
    @reconnectIntervals = {}

    @connectionOptions =
      host: @tunnelHost
      port: 22
      username: 'prisoner'
      privateKey: require('fs').readFileSync(ID_FILE_PATH)

    #npm installs this with the wrong permissions.
    # fs.chmodSync ID_FILE_PATH, "400"


  #@param tunnel: {name, localPort, remotePort}
  #@param hooks: map of event names to callbacks for that event
  startTunnel: (tunnel, hooks) ->
    log.debug "Starting tunnel #{tunnel.name} for local port #{tunnel.localPort}"
    tunnel.remotePort ?= 0
    @tunnels[tunnel.name] = tunnel
    @_openConnection tunnel, hooks

  #hooks: {close:->, end:->}
  _openConnection: (tunnel, hooks) ->
    #Useful flag to disable known hosts checking: -oStrictHostKeyChecking=no
    @connections[tunnel.name] = connection = new @Connection
    connection.on 'connect', =>
      log.debug "Connected to #{@connectionOptions.host}"
    connection.on 'ready', =>
      log.trace "Tunnel #{tunnel.name} ready"
      clearInterval @reconnectIntervals[tunnel.name]
      delete @reconnectIntervals[tunnel.name]
      log.trace "Requesting forwarding for remote port #{tunnel.remotePort}"
      connection.forwardIn remoteAddr, tunnel.remotePort, (err, remotePort) =>
        if err
          log.warn "Error opening tunnel #{tunnel.name}:", err
          #XXX: This will currently kill things
          connection.emit 'error', err
        else
          if remotePort
            tunnel.remotePort = remotePort
          #remotePort isn't populated if we supplied it with a port.
          else
            remotePort = tunnel.remotePort
          log.debug "Remote forwarding port: #{remotePort}"
          hooks.setup remotePort
    connection.on 'error', (err) =>
      log.warn "Tunnel #{tunnel.name} had error:", err
    connection.on 'end', =>
      log.debug "Tunnel #{tunnel.name} ending"
      hooks.end?()
    connection.on 'close', (hadError) =>
      log.debug "Tunnel #{tunnel.name} closing"
      hooks.close?()
      if hadError
        log.warn "Closing had error:", hadError
      unless @shuttingDown
        log.trace "Setting up reconnection interval for #{tunnel.name}"
        @reconnectIntervals[tunnel.name] = setInterval =>
          log.trace "Trying to reopen tunnel #{tunnel.name}"
          @_openConnection tunnel, hooks
        , 10*1000

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

