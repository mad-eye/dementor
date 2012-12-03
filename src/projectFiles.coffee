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

  handleError: (error, callback) ->
    newError = null
    switch error.code
      when 'ENOENT' then newError = errors.new 'NO_FILE'
      when 'EISDIR' then newError = errors.new 'IS_DIR'
      #Fill in other error cases here...
    #console.error "Found error:", error
    callback newError ? error


  #callback: (err, body) -> ...
  readFile: (filePath, absolute=false, callback) ->
    if typeof absolute == 'function'
      callback = absolute
      absolute = false
    filePath = _path.join @directory, filePath unless absolute
    try
      contents = fs.readFileSync(filePath, "utf-8")
      callback(null, contents)
    catch error
      @handleError error, callback

  #callback: (err) -> ...
  writeFile: (filePath, contents, absolute=false, callback) ->
    if typeof absolute == 'function'
      callback = absolute
      absolute = false
    filePath = _path.join @directory, filePath unless absolute
    try
      fs.writeFileSync filePath, contents
      callback?()
    catch error
      @handleError error, callback

  exists: (filePath, absolute=false) ->
    filePath = _path.join @directory, filePath unless absolute
    return fs.existsSync filePath

  #callback: (err, results) -> ...
  readFileTree: (callback) ->
    results = null
    try
      results = readdirSyncRecursive @directory
      #console.log "Read file tree and found", results
    catch error
      console.warn "Found error:", error
      @handleError error, callback
      return
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
  #console.log 'returning files:', files
  return files.sort (a,b)->
    a.path > b.path


exports.ProjectFiles = ProjectFiles
exports.fileEventType = fileEventType
