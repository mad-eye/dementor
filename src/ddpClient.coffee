{EventEmitter} = require 'events'
_ = require 'underscore'
DDPClient = require "ddp"
{normalizePath} = require '../madeye-common/common'

DEFAULT_OPTIONS =
  host: "localhost"
  port: 3000
  auto_reconnect: true
  auto_reconnect_timer: 500
  use_ejson: true

makeIdSelector = (id) ->
  {"_id":{"$type":"oid","$value":id}}

class DdpClient extends EventEmitter
  constructor: (options) ->
    options = _.extend DEFAULT_OPTIONS, options
    @ddpClient = new DDPClient options
    @initialized = false
    @state = 'closed'

  #FIXME: This hangs when apogee is down -- set timeout and report error?
  #This will emit a 'connected' event on each connection.
  connect: ->
    @state = 'connecting'
    @emit 'trace', 'DDP connecting'
    @ddpClient.connect (error) =>
      @emit 'error', "Ddp error while connecting:", error if error
      unless error
        @emit 'connected'
        @emit 'debug', 'DDP connected'
      @_initialize()

  shutdown: (callback) ->
    @emit 'debug', 'Shutting down ddpClient'
    if @projectId
      #This hangs if the connection is down and the socket is trying to reconnect.
      #TODO: Make connected status and check that.
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
    @emit 'trace', 'Initializing ddp'
    @initialized = true
    @ddpClient.on 'message', (msg) =>
      @emit 'trace', 'Ddp message: ' + msg
    @ddpClient.on 'socket-close', (code, message) =>
      @state = 'closed'
      @emit 'debug', "DDP closed: [#{code}] #{message}"
    @ddpClient.on 'socket-error', (error) =>
      #Get this when apogee goes down: {"code":"ECONNREFUSED","errno":"ECONNREFUSED","syscall":"connect"}
      #TODO: Be more quiet about that error, maybe set internal state.
      if @state != 'connected' and error.code == 'ECONNREFUSED'
        @emit 'trace', "Socket error while not connected:", error
      else
        @emit 'warn', "Socket error:", error
    @ddpClient.on 'connected', =>
      @state = 'connected'
      @emit 'trace', "ddpClient connected"
    @listenForFiles()
    @listenForCommands()
    
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
    #Don't trigger this on reconnect.
    return if @projectId
    @emit 'trace', "Registering project with params", params
    @ddpClient.call 'registerProject', [params], (err, projectId, warning) =>
      return callback err if err
      @emit 'debug', "Registered project and got id #{projectId}"
      @projectId = projectId
      #Resubscribe on reconnection
      @ddpClient.on 'connected', =>
        @subscribe 'files', @projectId
        @subscribe 'commands', @projectId
      callback null, projectId, warning
      
  addFile: (file) ->
    @cleanFile file
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

  cleanFile: (file) ->
    file.projectId = @projectId
    file.orderingPath = normalizePath file.path

  listenForCommands: ->
    @ddpClient.on 'message', (message) =>
      msg = JSON.parse message
      return unless msg.collection == 'commands'
      data = msg.fields
      if msg.msg == 'added'
        data.commandId = msg.id
        @emit 'command', msg.fields.command, data

  listenForFiles: ->
    @ddpClient.on 'message', (message) =>
      msg = JSON.parse message
      return unless msg.collection == 'files'
      switch msg.msg
        when 'added'
          #eg {"msg":"added","collection":"files","id":"7772ea62-9673-43bd-86ee-9d64f497a21b","fields":{"path":"foo/frotz","isDir":true,"projectId":"c17973a5-ec8d-4282-b5f9-30ef3d3741bb","orderingPath":"foo frotz","modified_locally":false,"removed":false,"modified":false,"mtime":1355185662000,"isLink":false,"__v":0}}
          file = msg.fields
          file._id = msg.id
          @emit 'added', file
        when 'removed'
          @emit 'removed', msg.id
        when 'changed'
          #eg {"msg":"changed","collection":"files","id":"57204c04-4d73-474b-8c25-259b38c06dce","fields":{"modified":false}}
          @emit 'changed', msg.id, msg.fields, msg.cleared

  reportError: (err) ->
    @ddpClient.call 'reportError', [err, projectId]

  #Modifier is the changed fields
  updateFile: (fileId, modifier) ->
    modifier = {$set:modifier}
    @ddpClient.call 'updateFile', [fileId, modifier], (err) =>
      if err
        @emit 'warn', "Error updating file:", err
      else
        @emit 'trace', "Updating file #{fileId}"

  #data = {commandId, fileId, contents}
  sendFileContents: (error, data) ->
    @updateFile data.fileId,
      lastOpened: data.lastOpened
      fsChecksum: data.fsChecksum
      loadChecksum: data.loadChecksum

    @ddpClient.call 'commandReceived', [error, data], (err) =>
      if err
        @emit 'warn', "Error sending file contents:", err
      else
        @emit 'trace', "Sent file contents for #{data.fileId}"


  remove: (collectionName, id) ->
    @emit 'debug', "Removing #{collectionName} #{id}"
    #@ddpClient.call "/#{collectionName}/remove", [makeIdSelector(id)], (err, result) =>
    @ddpClient.call "/#{collectionName}/remove", [id], (err, result) =>
      @emit 'error', 'remove error:', err if err
      #@emit 'debug', "Remove #{collectionName} returned" unless err

  insert: (collectionName, doc) ->
    @emit 'debug', "Inserting #{collectionName} #{JSON.stringify doc}"
    @ddpClient.call "/#{collectionName}/insert", [doc], (err, result) =>
      @emit 'error', 'insert error:', err if err
      #@emit 'debug', "Insert #{collectionName} returned" unless err

  update: (collectionName, id, modifier) ->
    @emit 'debug', "Updating #{collectionName} #{id}"
    #@ddpClient.call "/#{collectionName}/update", [makeIdSelector(id)], (err, result) =>
    @ddpClient.call "/#{collectionName}/update", [{_id:id}, modifier], (err, result) =>
      @emit 'error', 'update error:', err if err
      #@emit 'debug', "Update #{collectionName} returned" unless err

module.exports = DdpClient

#{"msg":"method","method":"/stuffs/remove","params":[{"_id":{"$type":"oid","$value":"51e854f41600d88e81000003"}}],"id":"2"}"]

#["{\"msg\":\"method\",\"method\":\"/projectStatus/update\",\"params\":[{\"_id\":\"BjGioZGExJJAtYL8R\"},{\"$set\":{\"filePath\":\"z/y/x/p.txt\"}}],\"id\":\"7\"}"]

