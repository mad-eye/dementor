_ = require 'underscore'
{assert} = require 'chai'
hat = require 'hat'
wrench = require 'wrench'
fs = require 'fs'
_path = require 'path'
sinon = require 'sinon'

{Dementor} = require '../../src/dementor'
{ProjectFiles} = require '../../src/projectFiles'
{fileUtils} = require '../util/fileUtils'
MockDdpClient = require '../mock/mockDdpClient'
{errors, errorType} = require '../../madeye-common/common'
{Logger} = require '../../madeye-common/common'
Logger.setLevel process.env.MADEYE_LOGLEVEL

randomString = -> hat 32, 16

#TODO: Reduce redundancy with better before/etc hooks.

homeDir = fileUtils.homeDir

describe "Dementor", ->
  before ->
    #fileUtils.initTestArea()
    fileUtils.mkDirClean homeDir

  after ->
    #fileUtils.destroyTestArea()

  describe "constructor", ->
    registeredDir = fileUtils.testProjectDir 'alreadyRegistered'
    projectFiles = null
    before ->
      fileUtils.mkDirClean registeredDir
      projectFiles = new ProjectFiles "."

    it "should find previously registered projectId", ->
      projectId = randomString()
      projectPath = fileUtils.createProject "polyjuice"
      projects = {}
      projects[projectPath] = projectId
      projectFiles.saveProjectIds projects

      dementor = new Dementor
        directory:projectPath
        ddpClient: new MockDdpClient
      assert.equal dementor.projectId, projectId

    it "should have null projectId if not previously registered", ->
      projectPath = fileUtils.createProject "nothinghere"
      dementor = new Dementor
        directory:projectPath
        ddpClient: new MockDdpClient
      assert.equal dementor.projectId, null

    it "should set dementor.version", ->
      projectPath = fileUtils.createProject "version"
      dementor = new Dementor
        directory:projectPath
        ddpClient: new MockDdpClient
      assert.equal dementor.version, (require '../../package.json').version

  describe "enable", ->
    dementor = null
    projectPath = null
    ddpClient = null

    describe "when not registered", ->
      targetFileTree = null
      newProjectId = null
      before (done) ->
        fileMap = fileUtils.defaultFileMap
        targetFileTree = fileUtils.constructFileTree fileMap, "."
        projectPath = fileUtils.createProject "enableTest-#{randomString()}", fileMap
        newProjectId = randomString()

        ddpClient = new MockDdpClient
          connect: ->
            process.nextTick => @emit 'connected'
          registerProject: sinon.stub()
          subscribe: sinon.stub()
          addFile: (file) ->
            file._id = randomString()
            process.nextTick =>
              @emit 'added', file
        ddpClient.registerProject.callsArgWith 1, null, newProjectId
        ddpClient.subscribe.withArgs('files').callsArg 2

        dementor = new Dementor
          directory: projectPath
          ddpClient: ddpClient
        dementor.fileTree.on 'added initial files', ->
          debugger
          done()
        dementor.enable()

      it "should call ddpClient.registerProject without projectId", ->
        params = ddpClient.registerProject.args[0][0]
        assert.ok !params.projectId

      it 'should set new projectId', ->
        assert.equal dementor.projectId, newProjectId

      it 'should save new projectId', ->
        assert.equal dementor.projectFiles.projectIds()[projectPath], newProjectId

      it "should populate file tree with files (and ids)", (done) ->
        #Give the async bits time to process.
        setTimeout ->
          assert.ok dementor.fileTree
          files = dementor.fileTree.getFiles()
          assert.equal files.length, targetFileTree.getFiles().length
          for file in files
            assert.ok file.isDir?
            assert.ok file.path
            assert.ok file._id
          done()
        , 100

    ###
    describe "with outdated NodeJs"
      targetFileTree = null
      before (done) ->
        fileMap = fileUtils.defaultFileMap
        targetFileTree = fileUtils.constructFileTree fileMap, "."
        projectPath = fileUtils.createProject "outdatedNodeJsTest-#{randomString()}", fileMap
        warningMsg = "its not right!"
        httpClient = new MockHttpClient (options, params) ->
          assert.equal options.json?['nodeVersion'], process.version
          projectName = options.json?['projectName']
          files = options.json?['files']
          return {project: {_id:randomString(), name:projectName}, files:files, warning: warningMsg}

        dementor = new Dementor projectPath, httpClient, new MockSocket
        dementor.on 'warn', (msg) ->
          assert.equal msg, warningMsg
          done()
        dementor.enable()
    ###
###
    describe "when already registered", ->
      targetFileTree = projectId = null
      before (done) ->
        fileMap = fileUtils.defaultFileMap
        targetFileTree = fileUtils.constructFileTree fileMap, "."
        projectPath = fileUtils.createProject "alreadyEnableTest-#{randomString()}", fileMap
        projectId = randomString()
        dementor = new Dementor projectPath, defaultHttpClient, new MockSocket
        dementor.projectFiles.saveProjectId projectId

        dementor = new Dementor projectPath, defaultHttpClient, new MockSocket
        dementor.on 'enabled', ->
          done()
        dementor.enable()

      it "should update project files if already registered", ->
        assert.ok dementor.projectId
        assert.equal dementor.projectFiles.projectIds()[projectPath], dementor.projectId, "Stored projectId differs from dementor's"
        assert.equal dementor.projectId, projectId, "Dementor's projectId differs from original."

      it "should populate file tree with files (and ids)", ->
        assert.ok dementor.fileTree
        files = dementor.fileTree.getFiles()
        assert.equal files.length, targetFileTree.getFiles().length
        for file in files
          assert.ok file.isDir?
          assert.ok file.path?
          assert.ok file._id


  describe "shutdown", ->
    dementor = mockSocket = null
    socketClosed = false
    before (done) ->
      projectPath = fileUtils.createProject "disableTest-#{randomString()}", fileUtils.defaultFileMap

      mockSocket = new MockSocket
      dementor = new Dementor projectPath, defaultHttpClient, mockSocket
      dementor.on 'CONNECTED', ->
        dementor.shutdown done
      dementor.on 'DISCONNECT', ->
        socketClosed = true
      dementor.enable()

    it "should close down successfully", ->
      return #it would have failed by now!
    it "should call socket.disconnect", ->
      assert.isFalse mockSocket.connected, 'Socket should be disconnected'
      assert.ok socketClosed, 'Dementor should emit disconnect event.'

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
      dementor.on 'enabled', ->
        done()
      dementor.enable()

    it "should reply with file body", (done) ->
      data = fileId: dementor.fileTree.findByPath(filePath)._id
      mockSocket.trigger messageAction.REQUEST_FILE, data, (err, body) ->
        assert.equal err, null
        assert.equal body, fileBody
        done()

    it "should give correct error message if no file exists", (done) ->
      data = fileId: randomString()
      mockSocket.trigger messageAction.REQUEST_FILE, data, (err, body) ->
        assert.ok err
        assert.equal err.type, errorType.NO_FILE
        assert.equal body, null
        done()
      
    #Needed to check dementor-created errors
    it 'should return the correct error if fileId parameter is missing', (done) ->
      mockSocket.trigger messageAction.REQUEST_FILE, randomString(), (err, body) ->
        assert.ok err
        assert.equal err.type, errorType.MISSING_PARAM
        assert.equal body, null
        done()

  describe "receiving SAVE_LOCAL_FILE message", ->
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
      dementor.on 'READ_FILETREE', ->
        done()
      dementor.enable()

    it "should save file contents to projectFiles", (done) ->
      fileId = dementor.fileTree.findByPath(filePath)._id
      data =
        fileId: fileId
        contents: fileBody
      mockSocket.trigger messageAction.SAVE_LOCAL_FILE, data, (err) ->
        assert.equal err, null, "Should not have an error."
        readContents = fs.readFileSync _path.join projectPath, filePath
        assert.equal readContents, fileBody
        done()

    it "should give correct error message if no file exists", (done) ->
      data =
        fileId: randomString()
        contents: fileBody
      mockSocket.trigger messageAction.SAVE_LOCAL_FILE, data, (err) ->
        assert.ok err
        assert.equal err.type, errorType.NO_FILE
        done()

    #Needed to check dementor-created errors
    it 'should return the correct error if fileId parameter is missing', (done) ->
      data =
        contents: fileBody
      mockSocket.trigger messageAction.SAVE_LOCAL_FILE, data, (err) ->
        assert.ok err
        assert.equal err.type, errorType.MISSING_PARAM
        done()

    it 'should return the correct error if contents parameter is missing', (done) ->
      data =
        fileId: randomString()
      mockSocket.trigger messageAction.SAVE_LOCAL_FILE, data, (err) ->
        assert.ok err
        assert.equal err.type, errorType.MISSING_PARAM
        done()

  describe 'watchProject', ->
    dementor = mockSocket = null
    projectPath = projectFiles = null
    filePath = null
    fileBody = "Two great swans eat the frogs."
    before (done) ->
      projectPath = fileUtils.createProject "flaxo", fileUtils.defaultFileMap
      filePath = "testFile.txt"

      mockSocket = new MockSocket
      dementor = new Dementor projectPath, defaultHttpClient, mockSocket
      dementor.on 'WATCHING_FILETREE', ->
        done()
      dementor.enable()

    it 'should send LOCAL_FILES_ADDED message when projectFiles emits one', (done) ->
      mockSocket.onEmit = (action, data, cb) ->
        unless action == messageAction.LOCAL_FILES_ADDED
          console.log "Got action", action
          return
        assert.ok data.projectId
        assert.equal data.projectId, dementor.projectId
        assert.equal data.files.length, 1
        file = data.files[0]
        assert.equal file.path, filePath
        assert.equal file.isDir, false
        done()

      dementor.projectFiles.emit messageAction.LOCAL_FILES_ADDED, files:[{path:filePath, isDir:false}]

    it 'should send LOCAL_FILE_SAVED message when projectFiles emits one', (done) ->
      path = "a/path"
      contents = "Too readily we admit that the cost of inaction is failure."
      file = _id:randomString(), path:path, isDir:false
      dementor.fileTree.addFile file
      mockSocket.onEmit = (action, data, cb) ->
        unless action == messageAction.LOCAL_FILE_SAVED
          console.log "Got action", action
          return
        assert.ok data.projectId
        assert.equal data.projectId, dementor.projectId
        for k,v of file
          assert.equal data.file[k], v
        assert.equal data.contents, contents
        done()

      dementor.projectFiles.emit messageAction.LOCAL_FILE_SAVED, path:path, contents:contents

    it 'should send LOCAL_FILES_REMOVED message when projectFiles emits one', (done) ->
      path = "another/path"
      file = _id:randomString(), path:path, isDir:false
      dementor.fileTree.addFile file
      mockSocket.onEmit = (action, data, cb) ->
        unless action == messageAction.LOCAL_FILES_REMOVED
          console.log "Got action", action
          return
        assert.ok data.projectId
        assert.equal data.projectId, dementor.projectId
        assert.equal data.files.length, 1
        for k,v of file
          assert.equal data.files[0][k], v
        done()

      dementor.projectFiles.emit messageAction.LOCAL_FILES_REMOVED, paths:[path]

    it 'should send an error a file not in fileTree is removed', (done) ->
      path = "missing/path"
      mockSocket.onEmit = (action, data, cb) ->
        if action == messageAction.LOCAL_FILES_REMOVED
          fail "Should not receive a LOCAL_FILES_REMOVED message"
        else if action == messageAction.METRIC and data.level == 'warn'
          done()

      dementor.projectFiles.emit messageAction.LOCAL_FILES_REMOVED, paths:[path]
###

