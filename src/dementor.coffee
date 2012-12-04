{ProjectFiles, fileEventType} = require './projectFiles'
{FileTree} = require 'madeye-common'
{HttpClient} = require './httpClient'
{SocketClient} = require 'madeye-common'
{MessageController} = require './MessageController'
{messageMaker, messageAction} = require 'madeye-common'

class Dementor
  constructor: (@directory, @httpClient, @socketClient) ->
    @projectFiles = new ProjectFiles(@directory)
    @projectId = @projectFiles.projectIds()[@directory]
    @fileTree = new FileTree
    @socketClient?.controller = new MessageController this

  handleError: (err) ->
    console.error "Error:", err
    @runningCallback? err

  #callback: (err) ->
  enable: (@runningCallback) ->
    unless @projectId
      @registerProject (err, projectId) =>
        @socketClient.projectId = projectId
        @watchProject @runningCallback
        @runningCallback err
    else
      @socketClient.projectId = @projectId
      @watchProject @runningCallback
      @runningCallback()
      
  registerProject: (callback) ->
    console.log "fetching ID from server"
    @httpClient.post {action:'init'}, (result) =>
      console.log "received a result from init."
      if result.error
        console.error "Received error from server:" + result.error
        @handleError result.error
      else
        console.log "Received result from server:", result
        @projectId = result.id
        callback?()

  handshake: (callback) ->
    @socketClient.projectId = @projectId
    @socketClient.send messageMaker.handshakeMessage(), callback

  #callback: (err) ->
  watchProject: (callback) ->
    @handshake @runningCallback
    console.log "Reading filetree"
    @projectFiles.readFileTree (err, results) =>
      if err? then callback? err; return
      @handleFileEvent {
        type: fileEventType.ADD
        data:
          files: results
      }, callback
    @projectFiles.watchFileTree (err, event) =>
      callback? err if err?
      @handleFileEvent event

  handleFileEvent: (event, callback) ->
    return unless event
    #console.log "Calling handleFileEvent with event", event
    try
      switch event.type
        when fileEventType.PREEXISTED then "file already read by readFileTree."
        when fileEventType.ADD then @onAddFileEvent(event, callback)
        else throw new Error "Unrecognized event action: #{event.action}"
    catch err
      @handleError err

  #callback : (err) -> ...
  onAddFileEvent : (event, callback) ->
    console.log "Calling onFileEvent ADD"
    addFilesMessage = messageMaker.addFilesMessage(event.data.files)
    @socketClient.send addFilesMessage, (err, result) =>
      if err then @handleError err; return
      @fileTree.setFiles result.data.files
      console.log "Set fileTree files"

exports.Dementor = Dementor
