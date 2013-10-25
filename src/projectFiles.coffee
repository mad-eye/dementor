fs = require "fs"
_path = require "path"
{errors} = require '../madeye-common/common'
_ = require 'underscore'
_.str = require 'underscore.string'
clc = require 'cli-color'
events = require 'events'
async = require 'async'
IgnoreRules = require './ignoreRules'
{Logger} = require '../madeye-common/common'
{crc32, cleanupLineEndings, findLineEndingType} = require '../madeye-common/common'
{standardizePath, localizePath} = require '../madeye-common/common'

###
# Directory reading plan:
# To minimize how many files we deluge apogee with, let's only read those
# files that are visible, and those that might be visible soon.
# 
# Before we would 'clean out' the project by deleting those files not in
# the initial scan.  Now we will have to do it dir-by-dir.
#
# The information as to what directories we care about is in the ddp collection
# ActiveDirectories.  On a ddp add, we read the directory, add the files to
# FileTree (which modifies, adds, and deletes orphans for that dir), then mark
# the activeDir with a lastLoaded timestamp
#
# The file watcher we use (chokidar) does not notice when directories are
# added/removed.  So we have to implicitly add dirs that are required for
# a given filesystem event.
# 
#
###

MADEYE_PROJECTS_FILE = ".madeye_projects"
class ProjectFiles extends events.EventEmitter
  constructor: (@directory, ignorepath) ->
    Logger.listen @, 'projectFiles'
    @fileWatcher = require 'chokidar'
    @loadIgnoreRules ignorepath

  cleanPath: (path) ->
    return unless path?
    path = _path.relative(@directory, path)
    standardizePath path

  wrapError: (error) ->
    return null unless error
    newError = null
    switch error.code
      when 'ENOENT'
        newError = errors.new 'FileNotFound', path: error.path
      when 'EISDIR'
        newError = errors.new 'IsDirectory'
      when 'EACCES'
        newError = errors.new 'PermissionDenied', path: error.path
      #Fill in other error cases here...
    @emit 'trace', "Found error:", newError ? error
    return newError ? error

  loadIgnoreRules: (ignorepath) ->
    unless ignorepath
      try
        ignorefile = fs.readFileSync(_path.join @directory, ".madeyeignore")
      catch e
    else
      ignorefile = fs.readFileSync(_path.join @directory, ignorepath)

    @ignoreRules = new IgnoreRules ignorefile
    callback?()

  #callback: (err, body) -> ...
  readFile: (filePath, callback) ->
    return callback errors.new 'NO_FILE' unless filePath
    filePath = localizePath filePath
    filePath = _path.join @directory, filePath
    fs.readFile filePath, 'utf-8', (err, contents) =>
      callback @wrapError(err), contents

  #callback: (err) -> ...
  writeFile: (filePath, contents, callback) ->
    return callback errors.new 'NO_FILE' unless filePath
    filePath = localizePath filePath
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

  getProjectId: ->
    @projectIds()[@directory]

  saveProjectIds: (projects) ->
    fs.writeFileSync @projectsDbPath(), JSON.stringify(projects)

  projectIds: ->
    return {} unless fs.existsSync @projectsDbPath()
    JSON.parse fs.readFileSync(@projectsDbPath(), "utf-8")

  getProjectId: ->
    return @projectIds()[@directory]

  shouldInclude: (path) ->
    not @ignoreRules.shouldIgnore path

  #callback: (err, results) -> ...
  readFileTree: (callback) ->
    try
      @readdirRecursive null, (err, files) =>
        callback @wrapError(err), files
    catch error
      console.error "ERROR", error
      callback @wrapError(error), files

  #Sets up event listeners, and emits messages
  #TODO: Current dies on EACCES for directories with bad permissions
  watchFileTree: ->
    options =
      ignored: (path) =>
        return !@shouldInclude path
      ignoreInitial: true
    @watcher = @fileWatcher.watch @directory, options
    @watcher.on "error", (error) =>
      @_handleScanError error, (err) =>
        @emit 'error', err if err

    @watcher.on "add", (path, stats) =>
      @makeFileData path, (err, file) =>
        return @emit 'error', err if err
        return unless file
        @emit 'debug', "Local file added:", file.path
        @emit 'file added', file

    @watcher.on "change", (path, stats) =>
      @makeFileData path, (err, file) =>
        return @emit 'error', err if err
        return unless file
        @emit 'debug', "Local file modified:", file.path
        @emit 'file changed', file

    @watcher.on "unlink", (path) =>
      relativePath = @cleanPath path
      return unless @shouldInclude relativePath
      @emit 'debug', "Local file removed:", relativePath
      @emit 'file removed', relativePath

    #TODO: Moved

  _handleScanError: (error, callback) ->
    if error.code == 'ELOOP' or error.code == 'ENOENT'
      @emit 'debug', "Ignoring broken link", error
      callback null
    else if error.code == 'EACCES'
      @emit 'debug', "Permission denied for", error #if process.env.MADEYE_DEBUG
      callback null
    else
      callback @wrapError error

  #callback: (error, fileData) ->
  #fileData will be null if file is ignored
  makeFileData: (path, callback) ->
    cleanPath = @cleanPath path
    return callback null unless @shouldInclude cleanPath
    fs.lstat path, (err, stat) =>
      return @_handleScanError err, callback if err
      callback null, {
        path: cleanPath
        isDir: stat.isDirectory()
        isLink: stat.isSymbolicLink()
        mtime: stat.mtime.getTime()
      }

  #callback: (err, {contents, checksum, warning}) ->
  retrieveContents: (path, callback) ->
    @readFile path, (err, contents) =>
      if err
        @emit 'warn', "Error retrieving contents for file #{path}:", err
        return callback @wrapError err
      cleanContents = cleanupLineEndings contents
      checksum = crc32 cleanContents
      warning = null
      unless cleanContents == contents
        lineEndingType = findLineEndingType contents
        warning =
          title: "Inconsistent line endings"
          message: "We've converted them all into #{lineEndingType}."
      callback null, {contents:cleanContents, checksum, warning}

  #callback: (error, files) ->
  readdir: (relDir, callback) ->
    currentDir = _path.join(@directory, relDir)
    @emit 'trace', "readdir", currentDir
    fs.readdir currentDir, (err, fileNames) =>
      return callback @wrapError err if err
      async.map fileNames, (fileName, cb) =>
        @makeFileData _path.join(@directory, relDir, fileName), cb
      , (error, results) =>
        @emit 'trace', "Finished reading", relDir
        #Filter out null results
        results = _.filter results, (result) -> result
        callback error, results


  #callback: (error, files) ->
  readdirRecursive : (relDir='', callback) ->
    currentDir = _path.join(@directory, relDir)
    results = []
    fs.readdir currentDir, (err, fileNames) =>
      if err
        if err.code == 'EACCES'
          @emit 'debug', "Permission denied for #{relDir}"
          callback null
        else
          callback @wrapError err
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


exports.standardizePath = standardizePath = (path) ->
  return unless path?
  return path if _path.sep == '/'
  return path.split(_path.sep).join('/')

exports.localizePath = localizePath = (path) ->
  return unless path?
  return path if _path.sep == '/'
  return path.split('/').join(_path.sep)

exports.ProjectFiles = ProjectFiles
