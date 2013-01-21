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
{errorType} = require 'madeye-common'


#TODO: Reduce redundancy with better before/etc hooks.

homeDir = fileUtils.homeDir

makeMockSocket = ->
  return new MockSocket
    onsend: (message) ->
      if message.action == messageAction.REPLY
        #need to do this first, to prevent triggering an error
        #if we are testing a reply that's an error
        console.log "Getting reply to #{message.replyTo}"
        callback = @callbacks[message.replyTo]
        callback?(message)
      else if message.error
        assert.fail "Received error message:", message
      else
        switch message.action
          when messageAction.HANDSHAKE
            @handshakeReceived = true
            replyMessage = messageMaker.replyMessage message
            @receive replyMessage
          when messageAction.ADD_FILES
            assert.ok @handshakeReceived, "Must handshake before adding files."
            @addFileMessage = fileUtils.clone message
            file._id = uuid.v4() for file in message.data.files
            replyMessage = messageMaker.replyMessage message, files: message.data.files
            @receive replyMessage
          else assert.fail "Unexpected action received by socket: #{message.action}"

defaultHttpClient = new MockHttpClient (options, params) ->
  match = /project\/(\w*)/.exec options.action
  if match
    if options.method == 'POST'
      files = options.json?['files']
      file._id = uuid.v4() for file in files if files
      return {id:uuid.v4(), name:match[1], files:files }
    else if options.method == 'PUT'
      files = options.json?['files']
      file._id = uuid.v4() for file in files if files
      return {id:match[1], files:files }
    else
      return {error: "Wrong method: #{options.method}"}
  else
    return {error: "Wrong action: #{options.action}"}

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

      dementor = new Dementor projectPath
      assert.equal dementor.projectId, projectId

    it "should have null projectId if not previously registered", ->
      projectPath = fileUtils.createProject "nothinghere"
      dementor = new Dementor projectPath
      assert.equal dementor.projectId, null

  describe "enable", ->
    dementor = null
    projectPath = null

    it "should not allow two dementors to monitor the same directory"

    it "should not allow a dementor to watch a subdir of an existing dementors territory"

    describe "when not registered", ->
      targetFileTree = null
      before (done) ->
        fileMap = fileUtils.defaultFileMap
        targetFileTree = fileUtils.constructFileTree fileMap
        projectPath = fileUtils.createProject "enableTest-#{uuid.v4()}", fileMap
        dementor = new Dementor projectPath, defaultHttpClient, makeMockSocket()
        dementor.enable (err, flag) ->
          assert.equal err, null
          console.log "Running callback received flag: #{flag}"
          if flag == 'ENABLED'
            done()

      it "should register the project if not already registered", ->
        assert.ok dementor.projectId
        assert.equal dementor.projectFiles.projectIds()[projectPath], dementor.projectId, "Stored projectId differs from dementor's"

      it "should populate file tree with files (and ids)", ->
        assert.ok dementor.fileTree
        files = dementor.fileTree.files
        assert.equal files.length, targetFileTree.files.length
        for file in files
          assert.ok file.isDir?
          assert.ok file.path?
          assert.ok file._id

    describe "when already registered", ->
      targetFileTree = projectId = null
      before (done) ->
        fileMap = fileUtils.defaultFileMap
        targetFileTree = fileUtils.constructFileTree fileMap
        projectPath = fileUtils.createProject "alreadyEnableTest-#{uuid.v4()}", fileMap
        projectId = uuid.v4()
        projects = {}
        projects[projectPath] = projectId
        dementor.projectFiles.saveProjectIds projects

        dementor = new Dementor projectPath, defaultHttpClient, makeMockSocket()
        dementor.enable (err, flag) ->
          assert.equal err, null, #"Http should not return an error"
          if flag == 'ENABLED'
            done()

      it "should update project files if already registered", ->
        assert.ok dementor.projectId
        assert.equal dementor.projectFiles.projectIds()[projectPath], dementor.projectId, "Stored projectId differs from dementor's"
        assert.equal dementor.projectId, projectId, "Dementor's projectId differs from original."

      it "should populate file tree with files (and ids)", ->
        assert.ok dementor.fileTree
        files = dementor.fileTree.files
        assert.equal files.length, targetFileTree.files.length
        for file in files
          assert.ok file.isDir?
          assert.ok file.path?
          assert.ok file._id


  describe "disable", ->
    dementor = mockSocket = null
    socketClosed = false
    before (done) ->
      projectPath = fileUtils.createProject "disableTest-#{uuid.v4()}", fileUtils.defaultFileMap

      mockSocket = new MockSocket
      dementor = new Dementor projectPath, defaultHttpClient, mockSocket
      dementor.enable (err, flag) ->
        if flag == 'ENABLED'
          dementor.disable done
        if flag == 'DISCONNECT'
          socketClosed = true

    it "should close down successfull", ->
      return #it would have failed by now!
    it "should call socket.disconnect", ->
      assert.ok mockSocket.disconnected
      assert.ok socketClosed

  describe "receiving REQUEST_FILE message", ->
    dementor = mockSocket = null
    projectPath = projectFiles = null
    filePath = fileBody = null
    before (done) ->
      projectPath = fileUtils.createProject "cleesh", fileUtils.defaultFileMap
      filePath = "dir2/moderateFile"
      fileBody = fileUtils.defaultFileMap.dir2.moderateFile
      projectFiles = new ProjectFiles projectPath

      mockSocket = new MockSocket
      dementor = new Dementor projectPath, defaultHttpClient, mockSocket
      dementor.enable (err, flag) ->
        assert.equal err, null
        console.log "Running callback received flag: #{flag}"
        if flag == 'ENABLED'
          done()

    it "should reply with file body fweep", (done) ->
      fileId = dementor.fileTree.findByPath(filePath)._id
      mockSocket.trigger messageAction.REQUEST_FILE, fileId, (err, body) ->
        assert.equal err, null
        assert.equal body, fileBody
        done()

    it "should give correct error message if no file exists", (done) ->
      mockSocket.trigger messageAction.REQUEST_FILE, uuid.v4(), (err, body) ->
        assert.ok err
        assert.equal err.type, errorType.NO_FILE
        assert.equal body, null
        done()
      
  describe "receiving SAVE_FILE message", ->
    dementor = mockSocket = null
    projectPath = projectFiles = null
    filePath = null
    fileBody = "Two great swans eat the frogs."
    before (done) ->
      projectPath = fileUtils.createProject "cleesh", fileUtils.defaultFileMap
      filePath = "dir2/moderateFile"
      projectFiles = new ProjectFiles projectPath

      mockSocket = new MockSocket
      dementor = new Dementor projectPath, defaultHttpClient, mockSocket
      dementor.enable (err, flag) ->
        assert.equal err, null
        console.log "Running callback received flag: #{flag}"
        if flag == 'READ_FILETREE'
          done()


    it "should save file contents to projectFiles", (done) ->
      fileId = dementor.fileTree.findByPath(filePath)._id
      mockSocket.trigger messageAction.SAVE_FILE, fileId, fileBody, (err) ->
        assert.equal err, null, "Should not have an error."
        readContents = projectFiles.readFile(filePath, sync:true)
        assert.equal readContents, fileBody
        done()

    it "should give correct error message if no file exists", (done) ->
      mockSocket.trigger messageAction.SAVE_FILE, uuid.v4(), fileBody, (err) ->
        assert.ok err
        assert.equal err.type, errorType.NO_FILE
        done()
