fs = require "fs"

class Dementor
  constructor: (@directory) ->
    @id = this.config.id if @config
    #maybe retrieve git information here?

  configPath: ->
    "#{@directory}/."

  config: ->
    return @config if @config
    if fs.existsSync(@configPath())
      @config = JSON.parse fs.readFileSync(@configPath())
    else
      @config = {}
    return @config

  save_config: ->
    fs.writeFileSync(this.configPath, JSON.stringify(@config))

  watchFileTree: (callback) ->
    callback("edit", "file1")

  readFileTree: (callback) ->
    callback(["file1", "file2"])

  setId: (@id) ->
    this.config()["id"]

exports.Dementor = Dementor
