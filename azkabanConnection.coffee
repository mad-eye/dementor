{messageMaker, messageAction} = require 'madeye-common'
class AzkabanConnection

  constructor: (@httpConnector, @socketClient) ->
    @socketClient.controller = new MessageController()

  handleError: (error) ->
    console.error "Error:", error

  enable: (@dementor, callback) ->
    unless @dementor.projectId
      @initialize =>
        @socketClient.openConnection(@dementor.projectId)
        callback?()
    else
      @socketClient.openConnection(@dementor.projectId)
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

  addFiles: (files, callback) ->
    #XXX: projectId is passed to @socketClient up above -- should we have a different condition here?
    throw "project id not set!" unless @dementor.projectId
    @socketClient.send messageMaker.addFilesMessage(files), callback

  deleteFiles: (files) ->
    console.log "delete files #{files}"
    @socketClient.send messageMaker.removeFilesMessage(files)

  editFiles: (files) ->
    console.log("connection got files", files)
    for file in files
      console.log "modifying file #{file['path']} to be #{file['data']}"

class MessageController
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
    unless message.fileId
      callback new Error "Message does not contain fileId"
      return
    replyMessage = messageMaker.replyMessage message,
      fileId: message.fileId
      body: 'This is a test body.'
    callback null, replyMessage

  addLocalFiles: (message, callback) ->
    console.log "Adding local files:", message

  removeLocalFiles: (message, callback) ->
    console.log "Removing local files:", message

  changeLocalFiles: (message, callback) ->
    console.log "change local files:", message



exports.AzkabanConnection = AzkabanConnection
