fs = require "fs"
_path = require "path"

class Dementor
  constructor: (@directory) ->
    @id = this.config.id if @config

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

  watchFileTree: (callback) ->
    @watcher = require('watch-tree-maintained').watchTree(@directory, {'sample-rate': 50})
    @watcher.on "filePreexisted", (path)->
      callback "preexisted", [{path: path}]
    @watcher.on "fileCreated", (path)->
      callback "add", [{path: path}]
    @watcher.on "fileModified", (path)->
      fs.readFile path, "utf-8", (err, data)->
        callback "edit", [{path: path, data: data}]
    @watcher.on "fileDeleted", (path)->
      callback "delete", [{path: path}]

  disable: ->
    #cancel any file watching etc

  save_config: ->
    fs.writeFileSync(this.configPath, JSON.stringify(@_config))

  readFileTree: (callback) ->
    results = readdirSyncRecursive @directory
    callback results

  setId: (@id) ->
    this.config()["id"]

readdirSyncRecursive = (baseDir) ->
  files = []
  curFiles = null
  nextDirs = null
  isDir = (fname) ->
    fs.statSync( _path.join(baseDir, fname) ).isDirectory()
  prependBaseDir = (fname) ->
    _path.join baseDir, fname

  curFiles = fs.readdirSync(baseDir);
  nextDirs = curFiles.filter(isDir);
  newFiles = {isDir: file in nextDirs , name: prependBaseDir(file)} for file in curFiles
  files = files.concat newFiles

  while nextDirs.length
    files = files.concat(readdirSyncRecursive( _path.join(baseDir, nextDirs.shift()) ) )
  return files;


exports.Dementor = Dementor
