class AzkabanConnection

  constructor: (@httpConnector, @channelConnector) ->
    @channelConnector.onMessage = @onMessage

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
    unless @dementor.config.id
      @initialize()
    @channelConnector.openBrowserChannel()
    #@addFiles(@dementor.getfiletree())

  initialize: ->
    console.log "fetching ID from server"
    @httpConnector.post {action:'init'}, (result) =>
      if result.error
        console.error "Received error from server:" + result.error
        @handleError result.error
      else
        console.log "Received result from server:", result
        @dementor.setId(result._id)

  disable: ->
    @channelConnector.destroy()

  addFiles: (files, projectId) ->
    console.log "adding files #{files}"
    data =
      action: 'addFiles',
      projectId: projectId,
      files: files
    @channelConnector.send data

  removeFiles: (files, projectId) ->
    console.log "removing files #{files}"
    data =
      action: 'removeFiles',
      projectId: projectId,
      files: files
    @channelConnector.send data

  editFiles: (files, newContents, projectId) ->
    console.log "modify file #{file} to be #{newContents}"

  @addLocalFiles: (message) ->
    console.log "Adding local files:", message

  @removeLocalFiles: (message) ->
    console.log "Removing local files:", message

  @changeLocalFiles: (message) ->
    console.log "Changing local files:", message


exports.AzkabanConnection = AzkabanConnection
