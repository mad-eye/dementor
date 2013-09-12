{EventEmitter} = require 'events'
_ = require 'underscore'
DDPClient = require "ddp"

DEFAULT_OPTIONS =
  host: "localhost",
  port: 3000,
  auto_reconnect: true,
  auto_reconnect_timer: 500

makeIdSelector = (id) ->
  {"_id":{"$type":"oid","$value":id}}

class DdpClient extends EventEmitter
  constructor: (options) ->
    options = _.extend DEFAULT_OPTIONS, options
    @ddpClient = new DDPClient options
    @initialized = false

  connect: (callback) ->
    @emit 'trace', 'DDP connecting'
    @ddpClient.connect (error) =>
      @emit 'error', error if error
      unless error
        @emit 'debug', 'DDP connected'
      @_initialize()
      callback?(error)

  shutdown: (callback) ->
    @emit 'debug', 'Shutting down ddpClient'
    if @projectId
      @ddpClient.call 'closeProject', [@projectId], (err) =>
        if err
          @emit 'warn', "Error closing project:", err
        else
          @emit 'debug', "Closed project"
        @ddpClient.close()
        process.nextTick callback if callback
    else
      @ddpClient.close()
      process.nextTick callback if callback

  _initialize: ->
    return if @initialized
    @initialized = true
    @ddpClient.on 'message', (msg) =>
      @emit 'trace', 'Ddp message: ' + msg
    @ddpClient.on 'socket-close', (code, message) =>
      @emit 'debug', "DDP closed: [#{code}] #{message}"
    @ddpClient.on 'socket-error', (error) =>
      @emit 'error', error
    @listenForFiles()
    #@listenForCommands()
    
  subscribe: (collectionName, args..., callback) ->
    if callback and 'function' != typeof callback
      args ?= []
      args.push callback
      callback = null
    @emit 'trace', "Subscribing to #{collectionName} with args", args
    @ddpClient.subscribe collectionName, args, =>
      @emit 'debug', "Subscribed to #{collectionName}"
      @emit 'subscribed', collectionName
      callback?()

  registerProject: (params, callback) ->
    @emit 'trace', "Registering project with params", params
    @ddpClient.call 'registerProject', [params], (err, projectId, warning) =>
      return callback err if err
      @emit 'debug', "Registered project and got id #{projectId}"
      @projectId = projectId
      callback null, projectId, warning
      
  addFile: (file) ->
    file.projectId = @projectId
    @ddpClient.call 'addFile', [file], (err) =>
      if err
        @emit 'warn', "Error in adding file:", err
      else
        @emit 'trace', "Added file #{file.path}"

  removeFile: (fileId) ->
    @emit 'trace', "Calling removeFile", fileId
    @ddpClient.call 'removeFile', [fileId], (err) =>
      if err
        @emit 'warn', "Error in removing file:", err
      else
        @emit 'trace', "Removed file #{fileId}"

  listenForCommands: ->
    @ddpClient.on 'message', (message) =>
      msg = JSON.parse message
      return unless msg.collection == 'commands'
      if msg.msg == 'added'
        @emit 'command', msg.fields.command
        @remove 'commands', msg.id
      else
        console.log "Command message:", msg
        
    @subscribe 'commands', @projectId

  listenForFiles: ->
    @ddpClient.on 'message', (message) =>
      msg = JSON.parse message
      return unless msg.collection == 'files'
      switch msg.msg
        when 'added'
          file = msg.fields
          file._id = msg.id
          @emit 'added', file
        when 'removed'
          @emit 'removed', msg.id
        when 'changed'
          @emit 'changed', msg.id, msg.fields, msg.cleared

  remove: (collectionName, id) ->
    @emit 'debug', "Removing file #{id}"
    #@ddpClient.call "/#{collectionName}/remove", [makeIdSelector(id)], (err, result) =>
    @ddpClient.call "/#{collectionName}/remove", [id], (err, result) =>
      @emit 'error', err if err
      #@emit 'debug', "Remove #{collectionName} returned" unless err

  insert: (collectionName, doc) ->
    @emit 'debug', "Inserting file #{JSON.stringify doc}"
    @ddpClient.call "/#{collectionName}/insert", [doc], (err, result) =>
      @emit 'error', err if err
      #@emit 'debug', "Insert #{collectionName} returned" unless err

  update: (collectionName, id, modifier) ->
    @emit 'debug', "Updating file #{id}"
    #@ddpClient.call "/#{collectionName}/update", [makeIdSelector(id)], (err, result) =>
    @ddpClient.call "/#{collectionName}/update", [{_id:id}, modifier], (err, result) =>
      @emit 'error', err if err
      #@emit 'debug', "Update #{collectionName} returned" unless err

module.exports = DdpClient

#{"msg":"method","method":"/stuffs/remove","params":[{"_id":{"$type":"oid","$value":"51e854f41600d88e81000003"}}],"id":"2"}"]

#["{\"msg\":\"method\",\"method\":\"/projectStatus/update\",\"params\":[{\"_id\":\"BjGioZGExJJAtYL8R\"},{\"$set\":{\"filePath\":\"z/y/x/p.txt\"}}],\"id\":\"7\"}"]

