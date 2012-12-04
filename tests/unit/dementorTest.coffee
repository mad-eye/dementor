uuid = require 'node-uuid'
wrench = require 'wrench'
assert = require 'assert'
fs = require 'fs'
_path = require 'path'
{Dementor} = require '../../src/dementor'
{ProjectFiles} = require '../../src/projectFiles'
{fileUtils} = require '../util/fileUtils'
{MockHttpClient} = require '../mock/mockHttpClient'
{MockSocket} = require 'madeye-common'
{SocketClient} = require 'madeye-common'
{messageMaker, messageAction} = require 'madeye-common'


#TODO: Reduce redundancy with better before/etc hooks.

homeDir = fileUtils.homeDir

describe "Dementor", ->
  describe "constructor", ->
    registeredDir = fileUtils.testProjectDir 'alreadyRegistered'
    projectFiles = null
    before ->
      fileUtils.mkDirClean homeDir
      projectFiles = new ProjectFiles

    it "should find previously registered projectId", ->
      projectId = uuid.v4()
      projectPath = fileUtils.createProject "polyjuice"
      projects = {}
      projects[projectPath] = projectId
      projectFiles.saveProjectIds projects
      console.log "Saved projects:", projectFiles.projectIds()

      dementor = new Dementor projectPath
      assert.equal dementor.projectId, projectId

    it "should have null projectId if not previously registered", ->
      projectPath = fileUtils.createProject "nothinghere"
      dementor = new Dementor projectPath
      assert.equal dementor.projectId, null

  describe "enable", ->
    dementor = null
    projectPath = null
    projectFiles = null
    before ->
      projectFiles = new ProjectFiles
      projectPath = fileUtils.createProject "unenabled"
      socketClient = new SocketClient new MockSocket
      dementor = new Dementor projectPath, null, socketClient

    it "should register the project if not already registered", (done) ->
      projectId = uuid.v4()
      dementor.httpClient = new MockHttpClient (action, params) ->
        if action == 'init'
          return {id:projectId}
        else
          return {error: "Wrong action."}

      dementor.enable (err) ->
        assert.equal err, null
        assert.ok dementor.projectId
        done()

    it "should not register the project if already registered fweep", (done) ->
      projectId = uuid.v4()
      projects = {}
      projects[projectPath] = projectId
      projectFiles.saveProjectIds projects
      dementor.httpClient = new MockHttpClient (action, params) ->
        assert.fail "Should not call httpClient"

      dementor.enable (err) ->
        if err then console.warn "Received error: #{err}"
        assert.equal err, null, "Socket should not return an error"
        assert.ok dementor.projectId
        done()

  describe "watchProject", ->
    dementor = null
    projectPath = null
    projectFiles = null
    addFileMessage = null
    before (done) ->
      projectPath = fileUtils.createProject "tinsot", fileUtils.defaultFileMap
      projectFiles = new ProjectFiles projectPath

      httpClient = new MockHttpClient (action, params) ->
        if action == 'init'
          return {id:uuid.v4()}
        else
          return {error: "Wrong action."}

      socket = new MockSocket
        onsend: (message) ->
          switch message.action
            when messageAction.HANDSHAKE
              @handshakeReceived = true
            when messageAction.ADD_FILES
              assert.ok @handshakeReceived, "Must handshake before adding files."
              addFileMessage = fileUtils.clone message
              file._id = uuid.v4() for file in message.data.files
              replyMessage = messageMaker.replyMessage message, files: message.data.files
              @receive replyMessage
            else assert.fail "Unexpected action received by socket: #{message.action}"
      socketClient = new SocketClient socket
      
      dementor = new Dementor projectPath, httpClient, socketClient
      dementor.enable (err) ->
        assert.equal err, null
        done()

    it "should send a project's file tree to azkaban via socket", ->
      assert.ok addFileMessage
      files = addFileMessage.data.files
      for file in files
        assert.ok file.isDir?
        assert.ok file.path?
        
    it "should construct fileTree on azakban's response", ->
      assert.ok dementor.fileTree
      files = dementor.fileTree.files
      assert.equal files.length, addFileMessage.data.files.length
      for file in files
        assert.ok file.isDir?
        assert.ok file.path?
        assert.ok file._id

    it "should start watching the project"

  describe "receiving REQUEST_FILE message", ->
    it "should reply with file body"

