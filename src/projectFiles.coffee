fs = require "fs"
_path = require "path"
{errors} = require '../madeye-common/common'
_ = require 'underscore'
clc = require 'cli-color'
events = require 'events'
{messageAction} = require '../madeye-common/common'

#File Events:
#  type: fileEventType
#  data: #Event specific data
#  [For ADD]
#    files: [file,...]
#  [For REMOVE]
#    files: [path,...]
#  [For EDIT]
#    path:
#    contents:
#  [For MOVE]
#    fileId:
#    oldPath:
#    newPath:

#hack for dealing with excpetions caused by broken links
process.on 'uncaughtException', (err)->
  if err.code == "ENOENT"
    console.log "File does not exist #{err.path}"
  else
    throw err

MADEYE_PROJECTS_FILE = ".madeye_projects"
class ProjectFiles extends events.EventEmitter
  constructor: (@directory) ->
    @watchTree = require('watch-tree-maintained')

  cleanPath: (path) ->
    return unless path?
    pathRe = new RegExp "^#{@directory}#{_path.sep}"
    path = path.replace(pathRe, "")
    @standardizePath path

  standardizePath: (path) ->
    return unless path?
    return path if _path.sep == '/'
    return path.replace _path.sep, '/'

  localizePath: (path) ->
    return unless path?
    return path if _path.sep == '/'
    return path.replace '/', _path.sep

  handleError: (error, options={}, callback) ->
    newError = null
    switch error.code
      when 'ENOENT' then newError = errors.new 'NO_FILE',
        path: @cleanPath error.path
      when 'EISDIR' then newError = errors.new 'IS_DIR'
      when 'EACCES'
        newError = errors.new 'PERMISSION_DENIED', path: @cleanPath error.path
        newError.message += newError.path
      #Fill in other error cases here...
    #console.error "Found error:", error
    error = newError ? error
    #console.log "Returning error:", error
    if options.sync then throw error else callback? error


  #callback: (err, body) -> ...
  #options: sync:, absolute:
  readFile: (filePath, options={}, callback) ->
    if typeof options == 'function'
      callback = options
      options = {}
    unless filePath then callback errors.new 'NO_FILE'; return
    filePath = @localizePath filePath
    filePath = _path.join @directory, filePath unless options.absolute
    try
      contents = fs.readFileSync(filePath, "utf-8")
      if options.sync then return contents else callback null, contents
    catch error
      @handleError error, options, callback

  #callback: (err) -> ...
  #options: sync:, absolute:
  writeFile: (filePath, contents, options={}, callback) ->
    if typeof options == 'function'
      callback = options
      options = {}
    unless filePath then callback errors.new 'NO_FILE'; return
    filePath = @localizePath filePath
    filePath = _path.join @directory, filePath unless options.absolute
    try
      fs.writeFileSync filePath, contents
      if options.sync then return else callback?()
    catch error
      @handleError error, options, callback

  homeDir: ->
    return _path.resolve process.env["MADEYE_HOME"] if process.env["MADEYE_HOME"]
    envVarName = if process.platform == "win32" then "USERPROFILE" else "HOME"
    return _path.resolve process.env[envVarName]

  projectsDbPath: ->
    _path.join @homeDir(), MADEYE_PROJECTS_FILE

  saveProjectId: (projectId) ->
    projectIds = @projectIds()
    projectIds[@directory] = projectId
    @saveProjectIds projectIds


  saveProjectIds: (projects) ->
    fs.writeFileSync @projectsDbPath(), JSON.stringify(projects)

  projectIds: ->
    return {} unless fs.existsSync @projectsDbPath()
    JSON.parse fs.readFileSync(@projectsDbPath(), "utf-8")

  filter: (path) ->
    return false unless path?
    return false if path[path.length-1] == '~'
    return false if path[-4..] == ".swp"
    components = path.split _path.sep
    return false if '.git' in components
    return false if 'node_modules' in components
    return false if '.DS_Store' in components
    return true

  #callback: (err, results) -> ...
  readFileTree: (callback) ->
    results = null
    try
      results = @readdirSyncRecursive @directory
      results = _.filter results, (result) =>
        @filter result.path
    catch error
      @handleError error, null, callback; return
    callback null, results

  #Sets up event listeners, and emits messages
  #TODO: Current dies on EACCES for directories with bad permissions
  watchFileTree: ->
    @watcher = @watchTree.watchTree(@directory, {'sample-rate': 50})
    @watcher.on "filePreexisted", (path) ->
      #console.log "Found preexisting file:", path
      #Currently send this information with the init request.

    @watcher.on "fileCreated", (path) =>
      stat = @getStat path
      return unless stat
      isDir = stat.isDirectory()
      relativePath = @cleanPath path
      return unless @filter relativePath
      @emit messageAction.ADD_FILES, files: [{path:relativePath, isDir:isDir}]

    @watcher.on "fileModified", (path) =>
      relativePath = @cleanPath path
      return unless @filter relativePath
      fs.readFile path, "utf-8", (err, contents) =>
        if err then @emit 'error', err; return
        @emit messageAction.SAVE_FILE, {path: relativePath, contents: contents}

    @watcher.on "fileDeleted", (path) =>
      relativePath = @cleanPath path
      return unless @filter relativePath
      @emit messageAction.REMOVE_FILES, paths: [relativePath]

  getStat : (path) ->
    try
      return fs.statSync( path )
    catch error
      if error.code == 'ELOOP' or error.code == 'ENOENT'
        console.log clc.blackBright "Ignoring broken link at #{path}" #if process.env.MADEYE_DEBUG
      else if error.code == 'EACCES'
        console.log clc.blackBright "Permission denied for #{path}" #if process.env.MADEYE_DEBUG
      else
        @handleError error, sync:true
      return null

  # based on a similar fucntion found in wrench
  # https://github.com/ryanmcgrath/wrench-js
  # but with an added isDir field
  readdirSyncRecursive : (rootDir, relativeDir) ->
    files = []
    nextDirs = []
    newFiles = []
    currentDir = _path.join rootDir, relativeDir
    prependBaseDir = (fname) ->
      _path.join relativeDir, fname

    try
      curFiles = fs.readdirSync(currentDir)
    catch error
      if error.code == 'EACCES'
        console.log clc.blackBright "Permission denied for #{currentDir}" #if process.env.MADEYE_DEBUG
        return
      else
        @handleError error, sync:true

    for file in curFiles
      stat = @getStat _path.join(currentDir, file)
      continue unless stat
      isDir = stat.isDirectory()
      nextDirs.push file if isDir
      newFiles.push {isDir: isDir, path: @cleanPath prependBaseDir file }
    files = files.concat newFiles if newFiles

    while nextDirs.length
      dirFiles = @readdirSyncRecursive( rootDir, _path.join(relativeDir, nextDirs.shift()) )
      files = files.concat dirFiles if dirFiles
    return files.sort (a,b)->
      a.path > b.path

exports.ProjectFiles = ProjectFiles
