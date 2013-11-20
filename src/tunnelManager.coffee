events = require 'events'
net = require 'net'
Tunnel = require './tunnel'
Logger = require 'pince'

log = new Logger 'tunnelManager'
class TunnelManager extends events.EventEmitter
  constructor: ({@tunnelHost, @home, @azkabanUrl}) ->
    log.trace 'Constructing TunnelManager'
    @shuttingDown = false
    @tunnels = {}
    @reconnectTimeouts = {}
    @backoffCounter = 2

    @connectionOptions =
      host: @tunnelHost
      port: 22
      username: 'prisoner'
      privateKey: null #Will be supplied later.

  #callback: (err) ->
  init: (callback) ->
    @initializeKeys (err, keys) =>
      return callback err if err
      @setPrivateKey keys.private
      callback()

  setPrivateKey: (privateKey) ->
    @connectionOptions.privateKey = privateKey

  #@param tunnel: {name, localPort, remotePort}
  #@param hooks: map of event names to callbacks for that event
  startTunnel: (tunnelData, hooks) ->
    tunnel = @tunnels[tunnelData.name] = new Tunnel tunnelData
    log.debug "Starting tunnel #{tunnel.name} for local port #{tunnel.localPort}"

    tunnel.on 'ready', (remotePort) =>
      clearTimeout @reconnectTimeouts[tunnel.name]
      delete @reconnectTimeouts[tunnel.name]
      @backoffCounter = 2
      hooks.ready remotePort

    tunnel.on 'close', =>
      hooks.close()
      unless @shuttingDown
        log.trace "Setting up reconnection timeout for #{tunnel.name}"
        clearTimeout @reconnectTimeouts[tunnel.name]
        @reconnectTimeouts[tunnel.name] = setTimeout =>
          log.trace "Trying to reopen tunnel #{tunnel.name}"
          tunnel.connect()
        , (@backoffCounter++)*1000

    tunnel.on 'error', hooks.error

    tunnel.open @connectionOptions


  #callback: (err, keys={public:, private}) ->
  initializeKeys: (callback) ->
    @home.getKeys (err, keys) =>
      return callback err if err
      log.trace 'Found keys', keys
      if @home.hasAlreadyRegisteredPublicKey()
        log.trace "Public key already registered"
        callback null, keys
      else
        log.debug "Registering public key"
        @submitPublicKey keys.public, (err) =>
          callback err, keys

  #callback: (err) ->
  submitPublicKey: (publicKey, callback) ->
    url = @azkabanUrl + "/prisonKey"
    log.debug "Submitting public key to", url
    request
      url: url
      method: 'POST'
      form: {publicKey}
    , (err, res, body) =>
      if err
        callback err
      else if res.statusCode != 200
        log.debug "Response had bad code:", res.statusCode
        callback errors.new 'NetworkError'
      else
        log.trace "Public key submitted successfully."
        @home.markPublicKeyRegistered()
        callback null



  shutdown: (callback) ->
    log.trace 'Shutting down TunnelManager'
    @shuttingDown = true
    for name, tunnel in @tunnels
      log.trace "Killing tunnel #{name}"
      tunnel.shutdown()
    process.nextTick (callback ? ->)

module.exports = TunnelManager

