#TODO rename test

{BCSocket} = require 'browserchannel'

class AzkabanConnection

  constructor: (@httpHost, @httpPort, @bcHost, @bcPort) ->

  openBrowserChannel: ->
    @socket = new BCSocket 'http://#{@bcHost}:#{@bcPort}/channel'
    @socket.onopen = ->
      console.log "socket opened"
      @socket.send {hi:'there'}
    @socket.onmessage = (message) ->
      console.log 'got message', message

  #does azkaban enforce a one client per id rule on the server?
  enable: (@dementor) ->
    unless @dementor.config.id
      @initialize()
    openBrowserChannel()
    #try to enable dementor
    #TODO handle exceptional states (this dementor is already running at ..)
    #@addFiles(@dementor.getfiletre)

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
