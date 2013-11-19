fs = require 'fs'
_path = require 'path'
_ = require 'underscore'
mkdirp = require 'mkdirp'
createKeys = require 'rsa-json'
async = require 'async'
{exec} = require 'child_process'

MADEYE_HOME = '.madeye'
PROJECTS_FILE = '.madeye_projects'
KEY_TOUCH_FILE = '.madeye_keys_registered.ok'

log = new Logger 'home'
class Home
  constructor: (@directory) ->
    @homeDir = process.env["MADEYE_HOME_TEST"] ? _path.join(__systemHomeDir(), MADEYE_HOME)
    log.trace "Using madeye home #{@homeDir}"
    @projectsDb = _path.join @homeDir, PROJECTS_FILE
    @keysRegisteredTouchFile = _path.join @homeDir, KEY_TOUCH_FILE
    @privateKeyFile = _path.join @homeDir, 'id_rsa'
    @publicKeyFile = @privateKeyFile + '.pub'


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
    unless @_hasKeys()
      log.trace "Making new RSA keys"
      @_clearPublicKeyRegistered()
      __generateKeys @privateKeyFile, (err) =>
        return cb err if err
        @_readKeys callback
    else
      @_readKeys callback

  #callback: err, keys={public:, private:}
  _readKeys: (callback) ->
    async.parallel
      private: (cb) =>
        fs.readFile @privateKeyFile, 'utf-8', cb
      public: (cb) =>
        fs.readFile @publicKeyFile, 'utf-8', cb
    , callback

  _hasKeys: ->
    return false unless fs.existsSync @privateKeyFile
    return fs.existsSync @publicKeyFile

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

#callback: (err) ->
__generateKeys = (privateKeyFile, callback) ->
  exec "ssh-keygen -f #{privateKeyFile} -C tunnel_key -N '' -q -t rsa", callback


module.exports = Home
