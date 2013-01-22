flow = require 'flow'
{ProjectFiles, fileEventType} = require './projectFiles'
{FileTree} = require 'madeye-common'
{Settings} = require 'madeye-common'
{HttpClient} = require './httpClient'
{messageMaker, messageAction} = require 'madeye-common'
{errors, errorType} = require 'madeye-common'

class Dementor
  constructor: (@directory, @httpClient, socket) ->
    @projectFiles = new ProjectFiles(@directory)
    @projectName = @directory.split('/').pop()
    @projectId = @projectFiles.projectIds()[@directory]
    @fileTree = new FileTree null, @directory
    @attach socket

  handleError: (err) ->
    return unless err?
    console.error "Error:", err
    @runningCallback err

  #callback: (err, flag) ->
  enable: (@runningCallback) ->
    @projectFiles.readFileTree (err, files) =>
      @handleError err
      @runningCallback null, 'READ_FILETREE'
      if @projectId
        @httpClient.put {action: "project/#{@projectId}", json: {files:files}}, (result) =>
          @handleError result.error
          @finishEnabling(result.files)
      else
        @httpClient.post {action:"project/#{@projectName}", json: {files:files}}, (result) =>
          @handleError result.error
          @projectId = result.id
          @projectFiles.saveProjectId @projectId
          @finishEnabling(result.files)

  disable: (callback) ->
    @socket?.disconnect()
    callback?()
 
  finishEnabling: (files) ->
    @fileTree.addFiles files
    @runningCallback null, 'ENABLED'
    #Hack.  The "socket" is actually a SocketNamespace.  Thus we need to access the namespace's socket
    @socket.socket.connect =>
      @watchProject()

  #####
  # Events from ProjectFiles

  # XXX: When files are modified because of server messages, they will fire events.  We should ignore those.
  # TODO: Change this to event-driven code.

  watchProject: ->
    @projectFiles.watchFileTree (err, event) =>
      @handleError err
      @handleFileEvent event

  #callback: () -> ... optional, for additional hooks.
  handleFileEvent: (event, callback) ->
    return unless event
    #console.log "Calling handleFileEvent with event", event
    try
      switch event.type
        when fileEventType.PREEXISTED then "file already read by readFileTree."
        when fileEventType.ADD then @onAddFileEvent event, callback
        when fileEventType.REMOVE then @onRemoveFileEvent event, callback
        when fileEventType.EDIT then @onEditFileEvent event, callback
        else throw new Error "Unrecognized event action: #{event.action}"
    catch err
      console.error "Error in handleFileEvent"
      @handleError err

  #callback : () -> ...
  onAddFileEvent : (event, callback) ->
    #console.log "Calling onFileEvent ADD"
    #addFilesMessage = messageMaker.addFilesMessage(event.data.files)
    #@socketClient.send addFilesMessage, (err, result) =>
      #@handleError err
      #@fileTree.addFiles result.data.files
      #callback?()

  #callback : () -> ...
  onRemoveFileEvent : (event, callback) ->
    #removeFilesMessage = messageMaker.removeFilesMessage(event.data.files)
    #@socketClient.send removeFilesMessage, (err, result) =>
      #@handleError err
      ##TODO: Should check that result has the same files
      #@fileTree.removeFiles event.data.files
      #callback?()

  #callback : () -> ...
  onEditFileEvent : (event, callback) ->
    #file = @fileTree.findByPath event.data.path
    #saveFileMessage = messageMaker.saveFileMessage file.id, event.data.contents
    #@socketClient.send saveFileMessage, (err, result) =>
      #@handleError err
      #callback?()


  #####
  # Incoming message methods
  # errors should *NOT* be sent to @handleError, they
  # should be returned to be encoded as a message to
  # Azkaban

  handshake: (projectId) ->
    @socket.emit messageAction.HANDSHAKE, projectId, =>
      @runningCallback null, 'HANDSHAKE_RECEIVED'
      
  attach: (@socket) ->
    return unless socket?

    socket.on 'connect', =>
      @runningCallback null, "CONNECTED"
      @handshake @projectId
      clearInterval @reconnectInterval

    socket.on 'reconnect', =>
      @runningCallback null, "RECONNECTED"

    socket.on 'connect_failed', (reason) =>
      console.warn "Connection failed:", reason
      @runningCallback null, "CONNECTION_FAILED"

    socket.on 'disconnect', =>
      @runningCallback null, "DISCONNECT"
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
