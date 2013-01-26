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
        @fileTree.addFiles files
        @runningCallback null, 'ENABLED'
        #Hack.  The "socket" is actually a SocketNamespace.  Thus we need to access the namespace's socket
        @socket.socket.connect =>
          @watchProject()

  disable: (callback) ->
    @socket?.disconnect()
    callback?()
 
  #####
  # Events from ProjectFiles

  # XXX: When files are modified because of server messages, they will fire events.  We should ignore those.

  watchProject: ->
    @projectFiles.on messageAction.ADD_FILES, (data) =>
      data.projectId = @projectId
      @socket.emit messageAction.ADD_FILES, data, (err, files) =>
        @handleError err
        @fileTree.addFiles files

    @projectFiles.on messageAction.SAVE_FILE, (data) ->
      #TODO: Send save file message

    @projectFiles.on messageAction.REMOVE_FILES, (data) ->
      #TODO: send remove files message.

    @projectFiles.watchFileTree()
    @runningCallback null, 'WATCHING_FILETREE'


  #####
  # Incoming message methods
  # errors should *NOT* be sent to @handleError, they
  # should be returned to be encoded as a message to
  # Azkaban
      
  attach: (@socket) ->
    return unless socket?

    socket.on 'connect', =>
      @runningCallback null, "CONNECTED"
      clearInterval @reconnectInterval
      @socket.emit messageAction.HANDSHAKE, @projectId, (err) =>
        @runningCallback null, 'HANDSHAKE_RECEIVED'

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
