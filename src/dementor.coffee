{ProjectFiles, fileEventType} = require './projectFiles'
{FileTree, File} = require '../madeye-common/common'
{HttpClient} = require './httpClient'
{messageMaker, messageAction} = require '../madeye-common/common'
{errors, errorType} = require '../madeye-common/common'
events = require 'events'
clc = require 'cli-color'
_path = require 'path'

class Dementor extends events.EventEmitter
  constructor: (@directory, @httpClient, socket, clean=false) ->
    @projectFiles = new ProjectFiles(@directory)
    @projectName = _path.basename directory
    @projectId = @projectFiles.projectIds()[@directory] unless clean
    @fileTree = new FileTree null
    @attach socket
    @version = require('../package.json').version
    @serverOps = {}

  handleError: (err, silent=false) ->
    return unless err?
    message = err.message ? err
    metric =
      level : 'error'
      message: message
      timestamp : new Date()
      projectId : @projectId
    @socket.emit messageAction.METRIC, metric
    @emit 'error', err unless silent

  handleWarning: (msg) ->
    return unless msg?
    metric =
      level : 'warn'
      message : msg
      timestamp : new Date()
      projectId : @projectId
    @socket.emit messageAction.METRIC, metric
    @emit messageAction.WARNING, msg

  enable: ->
    @projectFiles.readFileTree (err, files) =>
      return @handleError err if err
      if files? and files.length > 5000
        throw "MadEye currently only supports projects with less than 5000 files"
      @addMetric 'READ_FILETREE'
      action = method = null
      if @projectId
        action = "project/#{@projectId}"
        method = 'PUT'
      else
        action = "project"
        method = 'POST'
      json =
        projectName: @projectName
        files: files
        version: @version
        nodeVersion: process.version

      @httpClient.request {method: method, action:action, json: json}, (result) =>
        return @handleError result.error if result.error
        @handleWarning result.warning
        @projectId = result.project._id
        @projectFiles.saveProjectId @projectId
        @fileTree.addFiles result.files
        @addMetric 'enabled'
        #Hack.  The "socket" is actually a SocketNamespace.  Thus we need to access the namespace's socket
        @socket.socket.connect =>
          @watchProject()

  disable: (callback) ->
    @socket?.disconnect()
    callback?()

  addMetric: (type, metric={}) ->
    metric.level ?= 'debug'
    metric.message = type
    metric.timestamp = new Date()
    metric.projectId = @projectId
    @socket.emit messageAction.METRIC, metric
    @emit type
 
  #####
  # Events from ProjectFiles

  # XXX: When files are modified because of server messages, they will fire events.  We should ignore those.

  watchProject: ->
    @projectFiles.on messageAction.LOCAL_FILES_ADDED, (data) =>
      data.projectId = @projectId
      @socket.emit messageAction.LOCAL_FILES_ADDED, data, (err, files) =>
        return @handleError err if err
        @fileTree.addFiles files

    @projectFiles.on messageAction.LOCAL_FILE_SAVED, (data) =>
      data.projectId = @projectId
      data.file = @fileTree.findByPath(data.path)
      serverOp = @serverOps[data.file._id]
      if serverOp && serverOp.action == messageAction.SAVE_LOCAL_FILE
        delete @serverOps[data.file._id]
        now = (new Date()).valueOf()
        #Make sure it's not an old possibly stuck serverOp? 
        if serverOp.timestamp.valueOf() > now - 10*1000
          return
        else
          @addMetric "SERVER_OP_STUCK",
            level: 'info'
            fileId: data.file._id
            serverOp: serverOp

      @socket.emit messageAction.LOCAL_FILE_SAVED, data, (err, response) =>
        return @handleError err if err
        if response?.action == messageAction.WARNING
          @handleWarning response.message

    @projectFiles.on messageAction.LOCAL_FILES_REMOVED, (data) =>
      data.projectId = @projectId
      file = @fileTree.findByPath(data.paths[0])
      #FIXME: This was happening in production.  Write tests for it.
      unless file?
        @handleError "#{errorType.MISSING_PARAM}: filePath #{data.paths[0]} not found in fileTree", true
        return
      data.files = [file]
      @socket.emit messageAction.LOCAL_FILES_REMOVED, data, (err, response) =>
        return @handleError err if err
        if response?.action == messageAction.WARNING
          @handleWarning response.message
        #XXX: Should we remove the file from the filetree? or leave it in case of being resaved?

    @projectFiles.watchFileTree()
    @addMetric 'WATCHING_FILETREE'


  #####
  # Incoming message methods
  # errors from events from messageActions should *NOT* be
  # sent to @handleError, they
  # should be returned to be encoded as a message to
  # Azkaban.
      
  attach: (@socket) ->
    return unless socket?

    socket.on 'connect', =>
      @addMetric "CONNECTED"
      clearInterval @reconnectInterval
      @reconnectInterval = null
      @socket.emit messageAction.HANDSHAKE, @projectId, (err) =>
        @addMetric 'HANDSHAKE_RECEIVED'

    socket.on 'reconnect', =>
      @addMetric "RECONNECTED"

    socket.on 'connect_failed', (reason) =>
      console.warn "Connection failed:", reason
      @addMetric "CONNECTION_FAILED"

    socket.on 'disconnect', =>
      @addMetric "DISCONNECT"
      @reconnectInterval = setInterval (->
        socket.socket.connect()
      ), 10*1000

    socket.on 'error', (reason) =>
      @handleError reason

    #callback: (err, body) =>, errors are encoded as {error:}
    socket.on messageAction.REQUEST_FILE, (data, callback) =>
      fileId = data.fileId
      unless fileId then callback errors.new 'MISSING_PARAM'; return
      path = @fileTree.findById(fileId)?.path
      @projectFiles.readFile path, callback

    #callback: (err) =>, errors are encoded as {error:}
    socket.on messageAction.SAVE_LOCAL_FILE, (data, callback) =>
      fileId = data.fileId
      contents = data.contents
      unless fileId && contents?
        callback errors.new 'MISSING_PARAM'; return
      @serverOps[fileId] = action: messageAction.SAVE_LOCAL_FILE, timestamp: new Date
      path = @fileTree.findById(fileId)?.path
      @projectFiles.writeFile path, contents, (err) ->
        console.log "Saving file " + clc.bold path unless err
        callback err

exports.Dementor = Dementor
