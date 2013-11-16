fs = require 'fs'
_path = require 'path'
mkdirp = require 'mkdirp'

MADEYE_HOME = '.madeye'
MADEYE_PROJECTS_FILE = ".madeye_projects"

log = new Logger 'home'
class Home
  constructor: (@directory) ->
    @homeDir = process.env["MADEYE_HOME_TEST"] ? _path.join(__systemHomeDir(), MADEYE_HOME)
    log.trace "Using madeye home #{@homeDir}"
    @projectsDb = _path.join @homeDir, MADEYE_PROJECTS_FILE

  init: ->
    mkdirp.sync @homeDir

  saveProjectId: (projectId) ->
    log.trace "Saving projectId #{projectId} for project #{@directory}"
    projectIds = @_getProjectIds()
    projectIds[@directory] = projectId
    fs.writeFileSync @projectsDb, JSON.stringify(projectIds)

  _getProjectIds: ->
    return {} unless fs.existsSync @projectsDb
    try
      return JSON.parse fs.readFileSync(@projectsDb, "utf-8")
    catch e
      #might be malformed, or deleted out from under us.
      log.warn "Projects file #{@projectsDb} malformed."
      return {}


  getProjectId: ->
    return @_getProjectIds()[@directory]


__systemHomeDir = ->
  envVarName = if process.platform == "win32" then "USERPROFILE" else "HOME"
  return _path.resolve process.env[envVarName]



module.exports = Home
