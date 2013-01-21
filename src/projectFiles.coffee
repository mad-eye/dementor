fs = require "fs"
_path = require "path"
{errors} = require 'madeye-common'
_ = require 'underscore'

fileEventType =
  ADD : 'add'
  REMOVE: 'remove'
  EDIT: 'edit'
  MOVE: 'move'
  PREEXISTED: 'preexisted'

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

MADEYE_PROJECTS_FILE = ".madeye_projects"
class ProjectFiles
  constructor: (@directory) ->

  handleError: (error, options={}, callback) ->
    newError = null
    switch error.code
      when 'ENOENT' then newError = errors.new 'NO_FILE'
      when 'EISDIR' then newError = errors.new 'IS_DIR'
      #Fill in other error cases here...
    #console.error "Found error:", error
    error = newError ? error
    if options.sync then throw error else callback error


  #callback: (err, body) -> ...
  #options: sync:, absolute:
  readFile: (filePath, options={}, callback) ->
    if typeof options == 'function'
      callback = options
      options = {}
    unless filePath then callback errors.new 'NO_FILE'; return
    filePath = _path.join @directory, filePath unless options.absolute
    try
      #console.log "Reading filepath", filePath
      contents = fs.readFileSync(filePath, "utf-8")
      if options.sync then return contents else callback?(null, contents)
    catch error
      @handleError error, options, callback

  #callback: (err) -> ...
  #options: sync:, absolute:
  writeFile: (filePath, contents, options={}, callback) ->
    if typeof options == 'function'
      callback = options
      options = {}
    unless filePath then callback errors.new 'NO_FILE'; return
    filePath = _path.join @directory, filePath unless options.absolute
    try
      fs.writeFileSync filePath, contents
      if options.sync then return else callback?()
    catch error
      @handleError error, options, callback

  exists: (filePath, absolute=false) ->
    filePath = _path.join @directory, filePath unless absolute
    return fs.existsSync filePath

  homeDir: ->
    return process.env["MADEYE_HOME"] if process.env["MADEYE_HOME"]
    envVarName = if process.platform == "win32" then "USERPROFILE" else "HOME"
    return process.env[envVarName]

  projectsDbPath: ->
    _path.join @homeDir(), MADEYE_PROJECTS_FILE

  saveProjectId: (projectId) ->
    projectIds = @projectIds()
    projectIds[@directory] = projectId
    @saveProjectIds projectIds


  saveProjectIds: (projects) ->
    fs.writeFileSync @projectsDbPath(), JSON.stringify(projects)

  projectIds: ->
    if (@exists @projectsDbPath(), true)
      projects = JSON.parse fs.readFileSync(@projectsDbPath(), "utf-8")
      #console.log "Found projects", projects
      return projects
    else
      #console.log "Found no projectfile."
      {}

  filter: (path) ->
    return false unless path?
    return false if path[path.length-1] == '~'
    components = path.split '/'
    return false if '.git' in components
    return false if 'node_modules' in components
    return true

  #callback: (err, results) -> ...
  readFileTree: (callback) ->
    results = null
    try
      results = readdirSyncRecursive @directory
      results = _.filter results, (result) =>
        @filter result.path
    catch error
      console.warn "Found error:", error
      @handleError error, null, callback; return
    callback null, results

  #callback = (err, event) ->
  watchFileTree: (callback) ->
    @watcher = require('watch-tree-maintained').watchTree(@directory, {'sample-rate': 50})
    @watcher.on "filePreexisted", (path) ->
      event =
        type: fileEventType.PREEXISTED
        data:
          files: [path]
      callback null, event
    @watcher.on "fileCreated", (path)->
      event =
        type: fileEventType.ADD
        data:
          files: [path]
      callback null, event
    @watcher.on "fileModified", (path)->
      #console.log "fileModified: #{path}"
      fs.readFile path, "utf-8", (err, contents)->
        if err then callback err; return
        event =
          type: fileEventType.EDIT
          data:
            path: path
            contents: contents
        callback null, event
    @watcher.on "fileDeleted", (path)->
      #console.log "fileDeleted: #{path}"
      event =
        type: fileEventType.REMOVE
        data:
          files: [path]
      callback null, event

# based on a similar fucntion found in wrench
# https://github.com/ryanmcgrath/wrench-js
# but with an added isDir field
readdirSyncRecursive = (rootDir, relativeDir) ->
  files = []
  nextDirs = []
  newFiles = []
  currentDir = _path.join rootDir, relativeDir
  isDir = (fname) ->
    fs.statSync( _path.join(currentDir, fname) ).isDirectory()
  prependBaseDir = (fname) ->
    _path.join relativeDir, fname

  curFiles = fs.readdirSync(currentDir)
  nextDirs.push(file) for file in curFiles when isDir(file)
  newFiles.push {isDir: file in nextDirs , path: prependBaseDir(file)} for file in curFiles

  files = files.concat newFiles if newFiles

  while nextDirs.length
    files = files.concat(readdirSyncRecursive( rootDir, _path.join(relativeDir, nextDirs.shift()) ) )
  #console.log 'returning files:', files
  return files.sort (a,b)->
    a.path > b.path


exports.ProjectFiles = ProjectFiles
exports.fileEventType = fileEventType
