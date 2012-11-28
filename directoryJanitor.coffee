fs = require "fs"
_path = require "path"

class DirectoryJanitor
  constructor: (@directory) ->


  #TODO: stub
  readFile: (filePath) ->
    return "contents!"

  #TODO: stub
  writeFile: (filePath, contents) ->
    null

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

  readFileTree: (callback) ->
    results = readdirSyncRecursive @directory
    callback results



# based on a similar fucntion found in wrench
# https://github.com/ryanmcgrath/wrench-js
# but with an added isDir field
readdirSyncRecursive = (baseDir) ->
  files = []
  nextDirs = []
  newFiles = []
  isDir = (fname) ->
    fs.statSync( _path.join(baseDir, fname) ).isDirectory()
  prependBaseDir = (fname) ->
    _path.join baseDir, fname

  curFiles = fs.readdirSync(baseDir)
  nextDirs.push(file) for file in curFiles when isDir(file)
  newFiles.push {isDir: file in nextDirs , path: prependBaseDir(file)} for file in curFiles

  files = files.concat newFiles if newFiles

  while nextDirs.length
    files = files.concat(readdirSyncRecursive( _path.join(baseDir, nextDirs.shift()) ) )

  return files.sort (a,b)->
    a.path > b.path


exports.DirectoryJanitor = DirectoryJanitor
