{EventEmitter} = require 'events'
net = require 'net'
util = require 'util'
Connection = require 'ssh2'
Logger = require 'pince'

remoteAddr = '0.0.0.0' #FIXME: This accepts all IPV4 connections.  Generalize.

class Tunnel extends EventEmitter
  constructor: ({@name, @localPort, @remotePort}) ->
    @remotePort ?= 0
    @state =  'closed'
    @log = new Logger "tunnel:#{@name}"
    @backoffCounter = 2

  shutdown: (callback) ->
    @log.trace 'Shutting down'
    @connection.end()
    process.nextTick (callback ? ->)

  open: (@connectionOptions) ->
    #Useful flag to disable known hosts checking: -oStrictHostKeyChecking=no
    connection = @connection = new Connection

    connection.on 'connect', =>
      @log.debug "Connected to #{@connectionOptions.host}"

    connection.on 'ready', =>
      @log.trace "Connection ready"
      @log.trace "Requesting forwarding for remote port #{@remotePort}"
      connection.forwardIn remoteAddr, @remotePort, (err, remotePort) =>
        if err
          @log.warn "Error opening tunnel #{tunnel.name}:", err
          #XXX: This will currently kill things
          @emit 'error', err
        else
          #remotePort isn't populated if we supplied it with a port.
          #So either @remotePort needs to be replaced with remotePort,
          #or vice-versa.
          if remotePort
            @remotePort = remotePort
          else
            remotePort = @remotePort
          @log.debug "Remote forwarding port: #{remotePort}"
          @emit 'ready', remotePort

    connection.on 'error', (err) =>
      if err.level == 'authentication'
        @log.debug "Authentication error:", err
        @emit 'error', err
      else
        @log.warn "Connection error:", err

    connection.on 'close', (hadError) =>
      @log.debug "Tunnel #{tunnel.name} closing"
      @emit 'close'
      if hadError
        @log.warn "Tunnel closing had error"

    connection.on 'debug', (msg) ->
      @log.trace msg

    connection.on 'end', =>
      @log.debug "Tunnel #{tunnel.name} ending"

    connection.on 'keyboard-interactive', ->
      @log.debug "(keyboard-interactive)", arguments

    connection.on 'change password', ->
      @log.debug "(change password)", arguments

    connection.on 'tcp connection', (info, accept, reject) =>
      @log.trace "tcp incoming connection:", util.inspect info
      stream = accept()
      @_handleIncomingStream stream

    @connect()

  connect: ->
    @connection.connect @connectionOptions

  _handleIncomingStream: (stream) ->
    stream.on 'data', (data) =>
      #@log.trace "tcp Data received"
      0
    stream.on 'end', =>
      @log.trace "tcp EOF"
    stream.on 'error', (err) =>
      @log.warn "tcp error:", err
    stream.on 'close', (hadErr) =>
      @log.trace "tcp closed", (if hadErr then "with error")

    @log.trace "Pausing stream"
    stream.pause()
    @log.trace "Forwarding to localhost:#{@localPort}"
    socket = net.connect @localPort, 'localhost', =>
      stream.pipe socket
      socket.pipe stream
      stream.resume()
      @log.trace "Resuming stream"

module.exports = Tunnel
