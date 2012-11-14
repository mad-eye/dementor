#TODO rename test

{BCSocket} = require 'browserchannel'

class AzkabanConnection

  constructor: (@httpHost, @httpPort, @bcHost, @bcPort) ->

  openBrowserChannel: ->
    @socket = new BCSocket 'http://localhost:4321/channel'
    @socket.onopen = =>
      @socket.send {hi:'there'}
    @socket.onmessage = (message) =>
      console.log 'got message', message

  enable: (@dementor, done) ->
    unless @dementor.config.id
      @initialize()
    @openBrowserChannel()
    #@addFiles(@dementor.getfiletree())
    done()

  initialize: ->
    console.log "fetching ID from server"
    #fetch id
    #dementor.setId(adfasd)  set id
    #@dementorId = id

  disable: ->
    @socket.close()

  addFiles: (files) ->
    console.log "adding files #{filesToAdd}"

  removeFiles: (files) ->
    console.log "removing files #{filesToRemove}"

  editFiles: (files, newContents) ->
    console.log "modify file #{file} to be #{newContents}"

  listenForOrders: (orders) ->


exports.AzkabanConnection = AzkabanConnection
