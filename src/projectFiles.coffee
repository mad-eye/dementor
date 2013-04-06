fs = require "fs"
_path = require "path"
{errors} = require '../madeye-common/common'
_ = require 'underscore'
clc = require 'cli-color'
events = require 'events'
async = require 'async'
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

MADEYE_PROJECTS_FILE = ".madeye_projects"
class ProjectFiles extends events.EventEmitter
  constructor: (@directory) ->
    @watcher = require('watchr')

  cleanPath: (path) ->
    return unless path?
    path = _path.relative(@directory, path)
    @standardizePath path

  standardizePath: (path) ->
    return unless path?
    return path if _path.sep == '/'
    return path.split(_path.sep).join('/')

  localizePath: (path) ->
    return unless path?
    return path if _path.sep == '/'
    return path.split('/').join(_path.sep)

  wrapError: (error) ->
    return null unless error
    newError = null
    switch error.code
      when 'ENOENT'
        newError = errors.new 'NO_FILE', path: error.path
      when 'EISDIR'
        newError = errors.new 'IS_DIR'
      when 'EACCES'
        newError = errors.new 'PERMISSION_DENIED', path: error.path
        newError.message += newError.path
      #Fill in other error cases here...
    #console.error "Found error:", newError ? error
    return newError ? error


  #callback: (err, body) -> ...
  readFile: (filePath, callback) ->
    return callback errors.new 'NO_FILE' unless filePath
    filePath = @localizePath filePath
    filePath = _path.join @directory, filePath
    fs.readFile filePath, 'utf-8', (err, contents) =>
      callback @wrapError(err), contents

  #callback: (err) -> ...
  writeFile: (filePath, contents, callback) ->
    return callback errors.new 'NO_FILE' unless filePath
    filePath = @localizePath filePath
    filePath = _path.join @directory, filePath
    fs.writeFile filePath, contents, (err) =>
      callback @wrapError err

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

  shouldInclude: (path) ->
    return false unless path?
    return false if path[path.length-1] == '~'
    return false if path[-4..] == ".swp" #vim temp file
    return false if path[-4..] == ".swo" #vim temp file
    return false if _path.basename(path)[0..1] == '.#' #emacs temp file
    components = path.split '/'
    return false if '.git' in components
    return false if '.meteor' in components
    return false if 'node_modules' in components
    return false if '.DS_Store' in components
    return true

  #callback: (err, results) -> ...
  readFileTree: (callback) ->
    try
      @readdirRecursive null, (err, files) =>
        callback @wrapError(err), files
    catch error
      callback @wrapError(error), files

  #Sets up event listeners, and emits messages
  #TODO: Current dies on EACCES for directories with bad permissions
  watchFileTree: ->
    @watcher.watch
      path: @directory
      ignoreCustomPatterns: null
      interval: 3007
      duplicateDelay: 500
      persistent: false #Maybe need true?

      next: (err, watcher) =>
        return @emit 'error', err if err
        #Done initial watch.
        @emit 'done'

      listeners:
        error: (err) =>
            @emit 'error', err

        #watching: (err, watcherInstance, isWatching) ->
          #console.log "Watching", watcherInstance.path

        change: (changeType, path, currentStat, previousStat) =>
          console.log "Watcher:", changeType, path, Date.now()
          switch changeType
            when 'create'
              @makeFileData path, (err, file) =>
                return @emit 'error', err if err
                return unless file
                @emit messageAction.LOCAL_FILES_ADDED, files: [file]

            when 'delete'
              relativePath = @cleanPath path
              return unless @shouldInclude relativePath
              @emit messageAction.LOCAL_FILES_REMOVED, paths: [relativePath]

            when 'update'
              relativePath = @cleanPath path
              return unless @shouldInclude relativePath
              fs.readFile path, "utf-8", (err, contents) =>
                if err then @emit 'error', err; return
                @emit messageAction.LOCAL_FILE_SAVED, {path: relativePath, contents: contents}

  _handleScanError: (error, callback) ->
    if error.code == 'ELOOP' or error.code == 'ENOENT'
      console.log clc.blackBright "Ignoring broken link at #{path}" #if process.env.MADEYE_DEBUG
      callback null
    else if error.code == 'EACCES'
      console.log clc.blackBright "Permission denied for #{path}" #if process.env.MADEYE_DEBUG
      callback null
    else
      callback error

  #callback: (error, fileData) ->
  makeFileData: (path, callback) ->
    cleanPath = @cleanPath path
    return callback null unless @shouldInclude cleanPath
    fs.lstat path, (err, stat) =>
      return @_handleScanError err if err
      callback null, {
        path: cleanPath
        isDir: stat.isDirectory()
        isLink: stat.isSymbolicLink()
        mtime: stat.mtime.getTime()
      }

  #callback: (error, files) ->
  readdirRecursive : (relDir='', callback) ->
    currentDir = _path.join(@directory, relDir)
    results = []
    #console.log "calling readdirRecursive for", currentDir
    fs.readdir currentDir, (err, fileNames) =>
      if err
        if err.code == 'EACCES'
          console.log clc.blackBright "Permission denied for #{relDir}" #if process.env.MADEYE_DEBUG
          callback null
        else
          callback err
      else
        async.each fileNames, (fileName, cb) =>
          @makeFileData _path.join(@directory, relDir, fileName), (err, fileData) =>
            return cb err if err or !fileData?
            results.push fileData
            #watch file
            #@emit 'EXISTING_FILE', fileData
            if fileData.isDir
              #console.log "Recusing into", fileData.path
              @readdirRecursive fileData.path, (err, res) =>
                results = results.concat res if res
                cb err
            else
              cb null
        , (error) =>
          #console.log "Finished reading", relDir
          callback error, results


exports.ProjectFiles = ProjectFiles
