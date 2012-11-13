class Azkaban
  constructor: (@server) ->

  #does azkaban enforce a one client per id rule on the server?
  enable: (@dementor) ->
    unless @dementor.config.id
      console.log "fetching ID from server"
      #fetch id
      #dementor.setId(adfasd)  set id
      #@dementorId = id
    #try to enable dementor
    #TODO handle excpetional states (this dementor is already running at ..)
    #TODO set up browser channel

  disable: ->
    #tear down browser channel
    #disable dementor

  addFiles: (files) ->
    console.log "adding files #{filesToAdd}"

  removeFiles: (files) ->
    console.log "removing files #{filesToRemove}"

  editFiles: (file, newContents) ->
    console.log "modify file #{file} to be #{newContents}"

  listenForOrders: (orders) ->


exports.Azkaban = Azkaban
