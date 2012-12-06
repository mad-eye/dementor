{ProjectFiles, fileEventType} = require './projectFiles'
{FileTree} = require 'madeye-common'
{HttpClient} = require './httpClient'
{SocketClient} = require 'madeye-common'
{MessageController} = require './messageController'
{messageMaker, messageAction} = require 'madeye-common'

#XXX: Check that project ids are written
class Dementor
  constructor: (@directory, @httpClient, @socketClient) ->
    @projectFiles = new ProjectFiles(@directory)
    @projectId = @projectFiles.projectIds()[@directory]
    @fileTree = new FileTree null, @directory
    @socketClient?.controller = new MessageController this

  handleError: (err) ->
    return unless err?
    console.error "Error:", err
    @runningCallback err

  #callback: (err) ->
  enable: (@runningCallback) ->
    unless @projectId
      @registerProject (err) =>
        @handleError err
        @finishEnabling()
    else
      @finishEnabling()

  #TODO: disable:
 
  registerProject: (callback) ->
    console.log "fetching ID from server"
    @httpClient.post {action:'init'}, (result) =>
      if result.error
        console.error "Received error from server:" + result.error
        callback result.error
      else
        @projectId = result.id
        callback()

  finishEnabling: ->
    @runningCallback null, 'ENABLED'
    console.log "Sending handshake."
    @handshake (err, replyMessage) =>
      @handleError err
      @runningCallback null, 'HANDSHAKE_RECEIVED'
      @watchProject()

  #callback : (err, replyMessage) -> ...
  handshake: (callback) ->
    @socketClient.projectId = @projectId
    @socketClient.send messageMaker.handshakeMessage(), callback

  watchProject: ->
    @projectFiles.readFileTree (err, results) =>
      @handleError err
      @handleFileEvent {
        type: fileEventType.ADD
        data:
          files: results
      }, () =>
        @runningCallback null, 'READ_FILETREE'
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
        else throw new Error "Unrecognized event action: #{event.action}"
    catch err
      @handleError err

  #callback : () -> ...
  onAddFileEvent : (event, callback) ->
    console.log "Calling onFileEvent ADD"
    addFilesMessage = messageMaker.addFilesMessage(event.data.files)
    @socketClient.send addFilesMessage, (err, result) =>
      @handleError err
      @fileTree.setFiles result.data.files
      callback?()


  #####
  # Incoming message methods
  # errors should *NOT* be sent to @handleError, they
  # should be returned to be encoded as a message to
  # Azkaban

  #callback : (err, body) ->
  getFileContents : (fileId, callback) ->
    path = @fileTree.findById(fileId)?.path
    @projectFiles.readFile path, callback

  #callback : (err) -> ...
  saveFileContents : (fileId, contents, callback) ->
    path = @fileTree.findById(fileId)?.path
    @projectFiles.writeFile path, contents, callback


exports.Dementor = Dementor
