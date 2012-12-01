fs = require "fs"
_path = require "path"
{errors} = require './errors'

fileEventType =
  ADD : 'add'
  REMOVE: 'remove'
  EDIT: 'edit'
  MOVE: 'move'

#File Events:
#  type: fileEventType
#  data: #Event specific data
#  [For ADD]
#    files: [file,...]
#  [For REMOVE]
#    files: [file,...]
#  [For EDIT]
#    fileId:
#    oldBody:
#    newBody:
#    changes:
#  [For MOVE]
#    fileId:
#    oldPath:
#    newPath:

class ProjectFiles
  constructor: (@directory) ->


  #Callback = (err, body) -> ...
  readFile: (filePath, absolute=false, callback) ->
    if typeof absolute == 'function'
      callback = absolute
      absolute = false
    unless @exists filePath, absolute
      console.warn filePath, "doesn't exist, returning error"
      callback errors.new 'NO_FILE'
      return
    filePath = _path.join @directory, filePath unless absolute
    unless fs.statSync(filePath).isFile()
      console.warn filePath, "isn't a normal file, returning error"
      callback errors.new 'NOT_NORMAL_FILE'
      return
    contents = fs.readFileSync(filePath, "utf-8")
    callback(null, contents)

  #Callback = (err) -> ...
  writeFile: (filePath, contents, absolute=false, callback) ->
    if typeof absolute == 'function'
      callback = absolute
      absolute = false
    filePath = _path.join @directory, filePath unless absolute
    #TODO: Change this to async and use callback
    fs.writeFileSync filePath, contents
    callback?()

  exists: (filePath, absolute=false) ->
    filePath = _path.join @directory, filePath unless absolute
    return fs.existsSync filePath

  readFileTree: (callback) ->
    results = readdirSyncRecursive @directory
    console.log "Read file tree and found", results
    callback null, results

  #callback = (err, event) ->
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


exports.ProjectFiles = ProjectFiles
exports.fileEventType = fileEventType
