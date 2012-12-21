{ProjectFiles, fileEventType} = require './projectFiles'
{FileTree} = require 'madeye-common'
{HttpClient} = require './httpClient'
{SocketClient} = require 'madeye-common'
{MessageController} = require './messageController'
{messageMaker, messageAction} = require 'madeye-common'

class Dementor
  constructor: (@directory, @httpClient, @socketClient) ->
    @projectFiles = new ProjectFiles(@directory)
    @projectName = @directory.split('/').pop()
    @projectId = @projectFiles.projectIds()[@directory]
    @fileTree = new FileTree null, @directory
    @socketClient?.controller = new MessageController this

  handleError: (err) ->
    return unless err?
    console.error "Error:", err
    @runningCallback err

  #callback: (err, flag) ->
  enable: (@runningCallback) ->
    if @projectId
      @httpClient.put {action: "project/#{@projectId}"}, (result) =>
        @handleError result.error
        @finishEnabling()
    else
      @httpClient.post {action:"project/#{@projectName}"}, (result) =>
        @handleError result.error
        @projectId = result.id
        projectIds = @projectFiles.projectIds()
        projectIds[@directory] = @projectId
        @projectFiles.saveProjectIds projectIds
        @finishEnabling()

  #TODO: disable:
 
  finishEnabling: ->
    @runningCallback null, 'ENABLED'
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
    #console.log "Calling onFileEvent ADD"
    addFilesMessage = messageMaker.addFilesMessage(event.data.files)
    @socketClient.send addFilesMessage, (err, result) =>
      @handleError err
      @fileTree.addFiles result.data.files
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
