fs = require "fs"
#watcher = require('watch-tree').watchTree(path, {'sample-rate': 5});

class Dementor
  constructor: (@directory) ->
    @id = this.config.id if @config
    #maybe retrieve git information here?

  configPath: ->
    "#{@directory}/.madeye"

  config: ->
    if @_config
      return @_config
    if fs.existsSync(@configPath())
      @_config = JSON.parse fs.readFileSync(@configPath())
    else
      console.log "file not found returning empty config"
      @_config = {}
    return @_config

  disable: ->
    #cancel any file watching etc

  save_config: ->
    fs.writeFileSync(this.configPath, JSON.stringify(@_config))

  watchFileTree: (callback) ->
    callback("edit", "file1")

  readFileTree: (callback) ->
    callback(["file1", "file2"])

  setId: (@id) ->
    this.config()["id"]

exports.Dementor = Dementor
