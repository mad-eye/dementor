class AzkabanConnection

  constructor: (@httpConnector, @channelConnection) ->
    @channelConnection.onMessage = @onMessage

  #message from ChannelConnection should be a JSON object
  onMessage: (message) ->
    if message.error
      @handleError message.error
      return
    console.log "AzkabanConnection received message:", message
    switch message.action
      when 'change' then @changeLocalFiles message
      when 'add' then @addLocalFiles message
      when 'remove' then @removeLocalFiles message

  handleError: (error) ->
    console.error "Error:", error

  enable: (@dementor) ->
    unless @dementor.projectId
      @initialize()
    @channelConnection.openBrowserChannel()

  initialize: ->
    console.log "fetching ID from server"
    @httpConnector.post {action:'init'}, (result) =>
      console.log "received a result.."
      if result.error
        console.error "Received error from server:" + result.error
        @handleError result.error
      else
        console.log "Received result from server:", result
        @dementor.registerProject(result._id)

  disable: ->
    @channelConnection.destroy()

  addFiles: (files) ->
    console.log "adding files #{files}"
    @channelConnection.send
      action: 'addFiles',
      projectId: @dementor.projectId
      data:
        files: files

  deleteFiles: (files) ->
    console.log "delete files #{files}"
    data =
      action: 'removeFiles',
      projectId: @dementor.projectId
      files: files
    @channelConnection.send data

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
