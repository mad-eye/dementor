events = require 'events'
_ = require 'underscore'
DDPClient = require("ddp")
{hook_stdout, hook_stderr} = require './hookOutputs'

DEFAULT_OPTIONS =
  host: "localhost",
  port: 3000,
  auto_reconnect: true,
  auto_reconnect_timer: 500

class OutputWrapper extends events.EventEmitter
  constructor: (options) ->
    @projectId = options.projectId
    @options = _.extend DEFAULT_OPTIONS, options
    @ddpClient = new DDPClient @options
    @initialized = false

  shutdown: (callback) ->
    @stdoutHandle?()
    @stderrHandle?()
    @stdoutHandle = null
    @stderrHandle = null
    callback?()

  initialize : ->
    return if @initialized
    @initialized = true
    @emit 'debug', 'Initializing outputWrapper'

    #@ddpClient.on 'message', (msg)->
      #Do nothing for now
      #obj = JSON.parse(msg)
      #if obj.msg == "added" and obj.collection == "inputter"
        #term.write "#{obj.fields.cmd}\n"

    @stdoutHandle = hook_stdout (chunk, encoding) =>
      #TODO: Handle encoding in future version
      @ddpClient.call 'output', [@projectId, 'stdout', chunk]

    @stderrHandle = hook_stderr (chunk, encoding) =>
      #TODO: Handle encoding in future version
      @ddpClient.call 'output', [@projectId, 'stderr', chunk]

  connect: (callback) ->
    @ddpClient.connect (error) =>
      @emit 'error', error if error
      @emit 'debug', 'DDP connected' unless error
      @initialize()
      callback?(error)



module.exports = OutputWrapper
