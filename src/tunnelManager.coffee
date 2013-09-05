events = require 'events'
{spawn, exec} = require 'child_process'
fs = require 'fs'
util = require 'util'
_path = require 'path'

ID_FILE_PATH = _path.normalize "#{__dirname}/../lib/id_rsa"

class TunnelManager extends events.EventEmitter
  constructor: (@shareServer) ->
    @emit 'trace', 'Constructing TunnelManager'
    @shuttingDown = false
    @tunnels = {}
    @Connection = require 'ssh2'
    @connections = {}
    @reconnectIntervals = {}

    @connectionOptions =
      host: @shareServer
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
      connection.forwardIn '', tunnel.remotePort, (err, remotePort) =>
        if err
          @emit 'warn', "Error opening tunnel #{tunnel.name}:", err
        else
          #remotePort isn't populated if we supplied it with a port.
          remotePort ?= tunnel.remotePort
          @emit 'debug', "Remote forwarding port: #{remotePort}"
        callback? err, remotePort
    connection.on 'error', (err) =>
      @emit 'error', err
    connection.on 'end', =>
      @emit 'debug', "Tunnel #{tunnel.name} ending"
    connection.on 'close', (hadError) =>
      @emit 'debug', "Tunnel #{tunnel.name} closing", @shuttingDown
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
      stream.on 'data', (data) =>
        @emit 'trace', "[#{tunnel.name}]", data
      stream.on 'end', =>
        @emit 'trace', "[#{tunnel.name}] EOF"
      stream.on 'error', (err) =>
        @emit 'warn', "[#{tunnel.name}] error:", err
      stream.on 'close', (hadErr) =>
        @emit 'trace', "[#{tunnel.name}] closed, with error:", hadErr


    connection.connect @connectionOptions

  shutdown: (callback) ->
    @emit 'trace', 'Shutting down TunnelManager'
    @shuttingDown = true
    for name, connection in @connections
      @emit 'trace', "Killing tunnel #{name}"
      connection.end()
    process.nextTick (callback ? ->)

module.exports = TunnelManager

