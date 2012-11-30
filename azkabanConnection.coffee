{messageMaker, messageAction} = require 'madeye-common'
class AzkabanConnection

  constructor: (@httpConnector, @socketClient) ->
    @socketClient.controller = new MessageController()

  handleError: (error) ->
    console.error "Error:", error

  handshake: (callback) ->
    @socketClient.projectId = @dementor.projectId
    @socketClient.send messageMaker.handshakeMessage(), callback

  enable: (@dementor, callback) ->
    #FIXME:  This is a really bad way of setting dementor for the controller.
    @socketClient.controller.dementor = dementor
    unless @dementor.projectId
      @initialize =>
        @handshake (err) -> callback
        callback?()
    else
      @handshake()
      callback?()

  initialize: (callback)->
    console.log "fetching ID from server"
    @httpConnector.post {action:'init'}, (result) =>
      console.log "received a result.."
      if result.error
        console.error "Received error from server:" + result.error
        @handleError result.error
      else
        console.log "Received result from server:", result
        @dementor.registerProject(result.id)
        callback?()

  disable: ->
    @socketClient.destroy()

  #callback = (err, results) -> ... results are MongoDb Raw files
  addFiles: (files, callback) ->
    @socketClient.send messageMaker.addFilesMessage(files), callback

  #callback = (err) -> ...
  deleteFiles: (files, callback) ->
    console.log "delete files #{files}"
    @socketClient.send messageMaker.removeFilesMessage(files)

  #TODO: STUB
  #fileData = fileId:, oldPath:, newPath:
  #callback = (err) -> ...
  moveFile: (fileData, callback) ->
    console.log "STUB: Would be sending move file data:", fileData

  #TODO: STUB
  #fileData = fileId:, oldBody:, newBody:, changes:,
  #callback = (err, newFile) -> ...
  editFile: (fileData, callback) ->
    console.log "STUB: Would be sending edit file data:", fileData

class MessageController
  constructor: (@dementor) ->

  #message from ChannelConnection should be a JSON object
  route: (message, callback) ->
    console.log "AzkabanConnection received message:", message
    if message.error
      callback message.error
      return
    #TODO: Replace these with appropriate messageAction constants.
    switch message.action
      when messageAction.REQUEST_FILE then @requestLocalFile message, callback
      when 'change' then @changeLocalFiles message, callback
      when 'add' then @addLocalFiles message, callback
      when 'remove' then @removeLocalFiles message, callback
      else callback? new Error("Unknown action: " + message.action)

  requestLocalFile: (message, callback) ->
    console.log "Request local file:", message
    unless message.fileId then callback new Error "Message does not contain fileId"; return
    @dementor.getFileContents message.fileId, (err, body) ->
      if err then callback err; return
      replyMessage = messageMaker.replyMessage message,
        fileId: message.fileId
        body: body
      callback null, replyMessage

  addLocalFiles: (message, callback) ->
    console.log "Adding local files:", message

  removeLocalFiles: (message, callback) ->
    console.log "Removing local files:", message

  changeLocalFiles: (message, callback) ->
    console.log "change local files:", message



exports.AzkabanConnection = AzkabanConnection
