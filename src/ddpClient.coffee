{EventEmitter} = require 'events'
_ = require 'underscore'
DDPClient = require "ddp"
_path = require 'path'
{normalizePath} = require '../madeye-common/common'
{standardizePath, localizePath} = require './projectFiles'
Logger = require 'pince'
#require('https').globalAgent.options.rejectUnauthorized = false

DEFAULT_OPTIONS =
  host: "localhost"
  port: 3000
  auto_reconnect: true
  auto_reconnect_timer: 500
  use_ejson: true

makeIdSelector = (id) ->
  {"_id":{"$type":"oid","$value":id}}

log = new Logger 'ddpClient'
#state in [closed, connecting, connected, reconnecting]
class DdpClient extends EventEmitter
  constructor: (options) ->
    options = _.extend DEFAULT_OPTIONS, options
    log.trace "Initializing DdpClient with options", options
    @ddpClient = new DDPClient options
    @initialized = false
    @state = 'closed'
    @_initialize()

  #This will emit a 'connected' event on each connection.
  connect: ->
    @state = 'connecting'
    log.trace 'DDP connecting'
    @ddpClient.connect (error) =>
      log.error "Ddp error while connecting:", error if error
      unless error
        @emit 'connected'
        log.debug 'DDP connected'

  #TODO: Write tests for these
  shutdown: (callback=->) ->
    log.debug 'Shutting down ddpClient'
    closeProject = (timeoutHandle) =>
      @ddpClient.call 'closeProject', [@projectId], (err) =>
        clearTimeout timeoutHandle
        if err
          log.warn "Error closing project:", err
        else
          log.debug "Closed project"
        @ddpClient.close()
        process.nextTick callback

    switch @state
      when 'closed'
        process.nextTick callback
      when 'connected'
        closeProject()
      when 'connecting'
        #No project to close
        @ddpClient.close()
        process.nextTick callback
      when 'reconnecting'
        #Give it a bit to try to close the project, but don't hang.
        timeoutHandle = setTimeout =>
          @ddpClient.close()
          process.nextTick callback
        , 10*1000
        closeProject timeoutHandle

  _initialize: ->
    return if @initialized
    @initialized = true
    log.trace 'Initializing ddp'
    @ddpClient.on 'message', (msg) =>
      log.trace 'Ddp message: ' + msg
    @ddpClient.on 'socket-close', (code, message) =>
      #TODO: Check if connecting, if so close (we view error on connecting as fatal)
      @state = 'reconnecting'
      log.debug "DDP closed: [#{code}] #{message}"
    @ddpClient.on 'socket-error', (error) =>
      #faye-websocket produces a huge number of these on disconnect. Just ignore unless we are actively connecting.
      if @state == 'connecting' #We haven't connected yet
        log.debug "Error while connecting:", error.message ? error
        log.error "Unable to connect to server; please try again later."
    @ddpClient.on 'connected', =>
      @state = 'connected'
      log.trace "ddpClient connected"
    @listenForFiles()
    @listenForCommands()
    @listenForDirs()
    @_startHeartbeat()

  _startHeartbeat: ->
    @heartbeatInterval = setInterval =>
      if @state == 'connected' and @projectId
        @ddpClient.call 'dementorHeartbeat', [@projectId]
    , 4*1000
    
  subscribe: (collectionName, args..., callback) ->
    if callback and 'function' != typeof callback
      args ?= []
      args.push callback
      callback = null
    log.trace "Subscribing to #{collectionName} with args", args
    @ddpClient.subscribe collectionName, args, =>
      log.debug "Subscribed to #{collectionName}"
      @emit 'subscribed', collectionName
      callback?()

  registerProject: (params, callback) ->
    #Don't trigger this on reconnect.
    return if @projectId
    params.dementor = true
    log.trace "Registering project with params", params
    @ddpClient.call 'registerProject', [params], (err, result) =>
      return callback err if err
      {projectId, warning} = result
      log.debug "Registered project and got id #{projectId}"
      @projectId = projectId
      #Resubscribe on reconnection
      #Initial connected event is already gone, this is for the future
      @ddpClient.on 'connected', =>
        @subscribe 'files', @projectId
        @subscribe 'commands', @projectId
        @subscribe 'activeDirectories', @projectId
      callback null, projectId, warning
      
  addFile: (file) ->
    @cleanFile file
    @ddpClient.call 'addFile', [file], (err) =>
      if err
        log.warn "Error in adding file #{file.path}:", err
      else
        log.trace "Added file #{file.path}"

  removeFile: (fileId) ->
    log.trace "Calling removeFile", fileId
    @ddpClient.call 'removeFile', [fileId], (err) =>
      if err
        log.warn "Error in removing file:", err
      else
        log.trace "Removed file #{fileId}"

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

  #Listen for ActiveDirectories
  listenForDirs: ->
    @ddpClient.on 'message', (message) =>
      msg = JSON.parse message
      return unless msg.collection == 'activeDirectories'
      return unless msg.msg == 'added'
      dir = msg.fields
      dir._id = msg.id
      @emit 'activeDir', dir


  #data: {commandId, fields...:}
  commandReceived: (err, data) ->
    @ddpClient.call 'commandReceived', [err, data]

  #Modifier is the changed fields
  updateFile: (fileId, modifier) ->
    modifier = {$set:modifier}
    @ddpClient.call 'updateFile', [fileId, modifier], (err) =>
      if err
        log.warn "Error updating file:", err
      else
        log.trace "Updated file #{fileId}"

  markDirectoryLoaded: (path) ->
    @ddpClient.call 'markDirectoryLoaded', [@projectId, path], (err) =>
      if err
        log.warn "Error marking directory #{path} as loaded:", err
      else
        log.trace "Marked directory #{path} as loaded"

  updateFileContents: (fileId, contents) ->
    @ddpClient.call 'updateFileContents', [fileId, contents], (err) =>
      if err
        log.warn "Error updating file contents:", err
      else
        log.trace "Updated file contents #{fileId}"


  #callback: (err) ->
  updateTunnel: (tunnel, callback) ->
    @ddpClient.call 'updateTunnel', [@projectId, tunnel.name, tunnel], callback

  remove: (collectionName, id) ->
    log.debug "Removing #{collectionName} #{id}"
    #@ddpClient.call "/#{collectionName}/remove", [makeIdSelector(id)], (err, result) =>
    @ddpClient.call "/#{collectionName}/remove", [id], (err, result) =>
      log.error 'remove error:', err if err
      #log.debug "Remove #{collectionName} returned" unless err

  insert: (collectionName, doc) ->
    log.debug "Inserting #{collectionName} #{JSON.stringify doc}"
    @ddpClient.call "/#{collectionName}/insert", [doc], (err, result) =>
      log.error 'insert error:', err if err
      #log.debug "Insert #{collectionName} returned" unless err

  update: (collectionName, id, modifier) ->
    log.debug "Updating #{collectionName} #{id}"
    #@ddpClient.call "/#{collectionName}/update", [makeIdSelector(id)], (err, result) =>
    @ddpClient.call "/#{collectionName}/update", [{_id:id}, modifier], (err, result) =>
      log.error 'update error:', err if err
      #log.debug "Update #{collectionName} returned" unless err

module.exports = DdpClient

#{"msg":"method","method":"/stuffs/remove","params":[{"_id":{"$type":"oid","$value":"51e854f41600d88e81000003"}}],"id":"2"}"]

#["{\"msg\":\"method\",\"method\":\"/projectStatus/update\",\"params\":[{\"_id\":\"BjGioZGExJJAtYL8R\"},{\"$set\":{\"filePath\":\"z/y/x/p.txt\"}}],\"id\":\"7\"}"]

