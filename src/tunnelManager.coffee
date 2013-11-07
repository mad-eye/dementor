events = require 'events'
net = require 'net'
{spawn, exec} = require 'child_process'
fs = require 'fs'
util = require 'util'
_path = require 'path'

ID_FILE_PATH = _path.normalize "#{__dirname}/../lib/id_rsa"
remoteAddr = '0.0.0.0' #FIXME: This accepts all IPV4 connections.  Generalize.

class TunnelManager extends events.EventEmitter
  constructor: (@shareHost) ->
    @emit 'trace', 'Constructing TunnelManager'
    @shuttingDown = false
    @tunnels = {}
    @Connection = require 'ssh2'
    @connections = {}
    @reconnectIntervals = {}

    @connectionOptions =
      host: @shareHost
      port: 22
      username: 'ubuntu'
      privateKey: require('fs').readFileSync(ID_FILE_PATH)

    #npm installs this with the wrong permissions.
    fs.chmodSync ID_FILE_PATH, "400"


  #callback: (err, tunnel) ->
  startTunnel: (options, callback)->
    @emit 'debug', "Starting tunnel #{options.name} for local port #{options.localPort}"
    options.remotePort ?= 0
    name = options.name
    @tunnels[name] = tunnel = name: name, localPort: options.localPort, remotePort: options.remotePort
    @_openConnection tunnel, (err, remotePort) =>
      return callback err if err
      tunnel.remotePort = remotePort if remotePort?
      callback null, tunnel

  #callback: (err, remotePort) ->
  _openConnection: (tunnel, callback) ->
    #Useful flag to disable known hosts checking: -oStrictHostKeyChecking=no
    @connections[tunnel.name] = connection = new @Connection
    connection.on 'connect', =>
      @emit 'debug', "Connected to #{@connectionOptions.host}"
    connection.on 'ready', =>
      @emit 'trace', "Tunnel #{tunnel.name} ready"
      clearInterval @reconnectIntervals[tunnel.name]
      delete @reconnectIntervals[tunnel.name]
      @emit 'trace', "Requesting forwarding for remote port #{tunnel.remotePort}"
      connection.forwardIn remoteAddr, tunnel.remotePort, (err, remotePort) =>
        if err
          @emit 'warn', "Error opening tunnel #{tunnel.name}:", err
        else
          #remotePort isn't populated if we supplied it with a port.
          remotePort ?= tunnel.remotePort
          @emit 'debug', "Remote forwarding port: #{remotePort}"
        callback? err, remotePort
    connection.on 'error', (err) =>
      @emit 'warn', "Tunnel #{tunnel.name} had error:", err
    connection.on 'end', =>
      @emit 'debug', "Tunnel #{tunnel.name} ending"
    connection.on 'close', (hadError) =>
      @emit 'debug', "Tunnel #{tunnel.name} closing"
      if hadError
        @emit 'warn', "Closing had error:", hadError
      unless @shuttingDown
        @emit 'trace', "Setting up reconnection interval for #{tunnel.name}"
        @reconnectIntervals[tunnel.name] = setInterval =>
          @emit 'trace', "Trying to reopen tunnel #{tunnel.name}"
          @_openConnection tunnel, (err) =>
            #Need to conncetion.close() here?
            @emit 'debug', "Tunnel #{tunnel.name} reconnected"
        , 10*1000

    connection.on 'tcp connection', (info, accept, reject) =>
      @emit 'trace', "tcp incoming connection:", util.inspect info
      stream = accept()
      @_handleIncomingStream stream, tunnel.name

    connection.connect @connectionOptions

  _handleIncomingStream: (stream, name) ->
    stream.on 'data', (data) =>
      @emit 'trace', "[#{name}] Data received"
    stream.on 'end', =>
      @emit 'trace', "[#{name}] EOF"
    stream.on 'error', (err) =>
      @emit 'warn', "[#{name}] error:", err
    stream.on 'close', (hadErr) =>
      @emit 'trace', "[#{name}] closed", (if hadErr then "with error")

    @emit 'trace', "Pausing stream"
    stream.pause()
    @emit 'trace', "Forwarding to localhost:9798}"
    socket = net.connect 9798, 'localhost', =>
      stream.pipe socket
      socket.pipe stream
      stream.resume()
      @emit 'trace', "Resuming stream"

  shutdown: (callback) ->
    @emit 'trace', 'Shutting down TunnelManager'
    @shuttingDown = true
    for name, connection in @connections
      @emit 'trace', "Killing tunnel #{name}"
      connection.end()
    process.nextTick (callback ? ->)

module.exports = TunnelManager

