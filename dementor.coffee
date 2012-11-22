fs = require "fs"
_path = require "path"

class Dementor

  constructor: (@directory) ->
    @projectId = @projects()[@directory]

  homeDir: ->
    return process.env["MADEYE_HOME"] if process.env["MADEYE_HOME"]
    envVarName = if process.platform == "win32" then "USERPROFILE" else "HOME"
    return process.env[envVarName]

  projectsDbPath: ->
    _path.join @homeDir(), ".madeye_projects"

  projects: ->
    if (fs.existsSync @projectsDbPath())
      projects = JSON.parse fs.readFileSync(@projectsDbPath(), "utf-8")
      return projects
    else
      {}

  registerProject: (projectId)->
    projects = @projects()
    @projects()[@directory] = projectId
    @projectId = projectId
    fs.writeFileSync @projectsDbPath(), JSON.stringify(projects)

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
    #cancel any file watching etc, flush config?

  readFileTree: (callback) ->
    results = readdirSyncRecursive @directory
    callback results

readdirSyncRecursive = (baseDir) ->
  files = []
  nextDirs = []
  newFiles = []
  isDir = (fname) ->
    fs.statSync( _path.join(baseDir, fname) ).isDirectory()
  prependBaseDir = (fname) ->
    _path.join baseDir, fname

  curFiles = fs.readdirSync(baseDir);
  nextDirs.push(file) for file in curFiles when isDir(file)
  newFiles.push {isDir: file in nextDirs , path: prependBaseDir(file)} for file in curFiles

  files = files.concat newFiles if newFiles

  while nextDirs.length
    files = files.concat(readdirSyncRecursive( _path.join(baseDir, nextDirs.shift()) ) )

  return files.sort (a,b)->
    a.name > b.name

exports.Dementor = Dementor
