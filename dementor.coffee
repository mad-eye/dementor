{DirectoryJanitor} = require './directoryJanitor'

class Dementor

  constructor: (@directory) ->
    @projectId = @projects()[@directory]
    @directoryJanitor = new DirectoryJanitor(@directory)

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
    @directoryJanitor.readFileTree (results) ->
      callback "add", [results]
    @directoryJanitor.watchFileTree callback

  disable: ->
    #cancel any file watching etc, flush config?


exports.Dementor = Dementor
