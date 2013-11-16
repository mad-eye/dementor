fs = require 'fs'
_path = require 'path'
_ = require 'underscore'
mkdirp = require 'mkdirp'
createKeys = require 'rsa-json'
async = require 'async'

MADEYE_HOME = '.madeye'
PROJECTS_FILE = '.madeye_projects'
KEY_FILE = '.madeye_keys'
KEY_TOUCH_FILE = '.madeye_keys_registered.ok'

log = new Logger 'home'
class Home
  constructor: (@directory) ->
    @homeDir = process.env["MADEYE_HOME_TEST"] ? _path.join(__systemHomeDir(), MADEYE_HOME)
    log.trace "Using madeye home #{@homeDir}"
    @projectsDb = _path.join @homeDir, PROJECTS_FILE
    @keyFile = _path.join @homeDir, KEY_FILE
    @keysRegisteredTouchFile = _path.join @homeDir, KEY_TOUCH_FILE

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

  #callback: (err, keys) ->
  getKeys: (callback) ->
    #Define this here; we need it in a couple places
    makeNewKeys = (cb) =>
      log.trace "Making new RSA keys"
      @_clearPublicKeyRegistered()
      createKeys (err, newKeys) =>
        return cb err if err
        @_writeKeys newKeys, (err) ->
          cb err, newKeys

    fs.exists @keyFile, (exists) =>
      unless exists
        makeNewKeys callback
      else
        log.trace "Keys exist, reading"
        fs.readFile @keyFile, 'utf-8', (err, contents) ->
          return callback err if err
          try
            keys = JSON.parse contents
            callback null, keys
          catch e
            log.debug "Malformed keyfile found. Resetting keys"
            makeNewKeys callback

  _writeKeys: (keys, callback=->) ->
    log.trace "Writing keys to #{@keyFile}"
    fs.writeFile @keyFile, JSON.stringify(keys), {mode: 0o600}, callback

  hasAlreadyRegisteredPublicKey: ->
    fs.existsSync @keysRegisteredTouchFile

  markPublicKeyRegistered: ->
    log.trace 'Marking key as registered'
    fs.writeFileSync @keysRegisteredTouchFile, ''

  _clearPublicKeyRegistered: ->
    try
      fs.unlinkSync @keysRegisteredTouchFile
    catch err
      #no file, no problem
      return if err.code == "ENOENT"
      throw err

__systemHomeDir = ->
  envVarName = if process.platform == "win32" then "USERPROFILE" else "HOME"
  return _path.resolve process.env[envVarName]



module.exports = Home
