events = require 'events'
net = require 'net'
request = require 'request'
Tunnel = require './tunnel'
Logger = require 'pince'
{errors} = require '../madeye-common/common'

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

  #This can be stubbed out for tests
  _makeTunnel: (tunnelData) ->
    new Tunnel tunnelData

  #@param tunnel: {name, localPort, remotePort}
  #@param hooks: map of event names to callbacks for that event
  startTunnel: (tunnelData, hooks) ->
    tunnel = @tunnels[tunnelData.name] = @_makeTunnel tunnelData
    log.debug "Starting tunnel #{tunnel.name} for local port #{tunnel.localPort}"

    #Prevent infinite loop of attempting to authenticate if there's a problem
    #We'll mark hadAuthenticationError=true when we have one, and on the second
    #one we'll just give up. The first error can simply be a missing key on the
    #prison server. The second error is an unknown unknown so we bail.
    hadAuthenticationError = false

    tunnel.on 'ready', (remotePort) =>
      hadAuthenticationError = false
      clearTimeout @reconnectTimeouts[tunnel.name]
      delete @reconnectTimeouts[tunnel.name]
      @backoffCounter = 2
      hooks.ready remotePort

    tunnel.on 'close', =>
      hooks.close()
      unless @shuttingDown or hadAuthenticationError
        log.trace "Setting up reconnection timeout for #{tunnel.name}"
        clearTimeout @reconnectTimeouts[tunnel.name]
        @reconnectTimeouts[tunnel.name] = setTimeout =>
          log.trace "Trying to reopen tunnel #{tunnel.name}"
          tunnel.open()
        , (@backoffCounter++)*1000

    tunnel.on 'error', (err) =>
      if hadAuthenticationError
        #We've already had one authentication error; bail.
        log.warn "Could not authenticate for tunnels; skipping tunnels."
        hooks.error err
        return
      else
        #Try again, but mark that we've had at least one error.
        hadAuthenticationError = true
        log.debug "Had authentication error establishing tunnels, submitting public key again."
        @home.clearPublicKeyRegistered()
        @initializeKeys (err) =>
          if err
            log.warn "Could not authenticate for tunnels; skipping tunnels."
            hooks.error err
            return
          log.trace "Submitted public key.  Reconnecting"
          tunnel.open()

    tunnel.open @connectionOptions

  #callback: (err, keys={public:, private}) ->
  initializeKeys: (callback) ->
    @home.getKeys (err, keys) =>
      return callback err if err
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
    for name, tunnel of @tunnels
      log.trace "Killing tunnel #{name}"
      tunnel.shutdown()
    process.nextTick (callback ? ->)

module.exports = TunnelManager

