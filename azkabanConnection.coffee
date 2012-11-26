{messageMaker, messageAction} = require 'madeye-common'
class AzkabanConnection

  constructor: (@httpConnector, @socketClient) ->
    @socketClient.onMessage = @onMessage

  #message from ChannelConnection should be a JSON object
  onMessage: (message) ->
    if message.error
      @handleError message.error
      return
    console.log "AzkabanConnection received message:", message
    #TODO: Replace these with appropriate messageAction constants.
    switch message.action
      when 'change' then @changeLocalFiles message
      when 'add' then @addLocalFiles message
      when 'remove' then @removeLocalFiles message

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

  addFiles: (files) ->
    #XXX: projectId is passed to @socketClient up above -- should we have a different condition here?
    throw "project id not set!" unless @dementor.projectId
    @socketClient.send messageMaker.addFilesMessage(files)

  deleteFiles: (files) ->
    console.log "delete files #{files}"
    @socketClient.send messageMaker.removeFilesMessage(files)

  editFiles: (files) ->
    console.log("connection got files", files)
    for file in files
      console.log "modifying file #{file['path']} to be #{file['data']}"

  addLocalFiles: (message) ->
    console.log "Adding local files:", message

  removeLocalFiles: (message) ->
    console.log "Removing local files:", message

  changeLocalFiles: (message) ->
    console.log "change local files:", message

exports.AzkabanConnection = AzkabanConnection
