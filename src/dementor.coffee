{ProjectFiles, fileEventType} = require './projectFiles'
{FileTree, File} = require 'madeye-common'
{HttpClient} = require './httpClient'
{messageMaker, messageAction} = require 'madeye-common'
{errors, errorType} = require 'madeye-common'
events = require 'events'

class Dementor extends events.EventEmitter
  constructor: (@directory, @httpClient, socket) ->
    @projectFiles = new ProjectFiles(@directory)
    @projectName = @findProjectName @directory
    @projectId = @projectFiles.projectIds()[@directory]
    @fileTree = new FileTree null, @directory
    @attach socket

  findProjectName: (dir) ->
    d = new File path:dir
    return d.filename


  handleError: (err) ->
    return unless err?
    metric =
      type : 'error'
      timestamp : new Date()
      projectId : @projectId
      level : 'error'
    @socket.emit messageAction.METRIC, metric
    @emit 'error', err

  enable: ->
    @projectFiles.readFileTree (err, files) =>
      @handleError err
      @addMetric 'READ_FILETREE'
      action = method = null
      if @projectId
        action = "project/#{@projectId}"
        method = 'PUT'
      else
        action = "project"
        method = 'POST'
      @httpClient.request {method: method, action:action, json: {projectName:@projectName, files:files}}, (result) =>
        @handleError result.error
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
    metric.type = type
    metric.timestamp = new Date()
    metric.projectId = @projectId
    @socket.emit messageAction.METRIC, metric
    @emit type
 
  #####
  # Events from ProjectFiles

  # XXX: When files are modified because of server messages, they will fire events.  We should ignore those.

  watchProject: ->
    @projectFiles.on messageAction.ADD_FILES, (data) =>
      data.projectId = @projectId
      @socket.emit messageAction.ADD_FILES, data, (err, files) =>
        @handleError err
        @fileTree.addFiles files

    @projectFiles.on messageAction.SAVE_FILE, (data) =>
      data.projectId = @projectId
      data.file = @fileTree.findByPath(data.path)
      @socket.emit messageAction.SAVE_FILE, data, (err) =>
        @handleError err

    @projectFiles.on messageAction.REMOVE_FILES, (data) =>
      data.projectId = @projectId
      file = @fileTree.findByPath(data.paths[0])
      data.files = [file]
      @socket.emit messageAction.REMOVE_FILES, data, (err) =>
        @handleError err

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
    socket.on messageAction.SAVE_FILE, (data, callback) =>
      fileId = data.fileId
      contents = data.contents
      unless fileId && contents
        callback errors.new 'MISSING_PARAM'; return
      path = @fileTree.findById(fileId)?.path
      @projectFiles.writeFile path, contents, callback

exports.Dementor = Dementor
