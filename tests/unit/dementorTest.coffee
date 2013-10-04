_ = require 'underscore'
{assert} = require 'chai'
hat = require 'hat'
wrench = require 'wrench'
fs = require 'fs'
_path = require 'path'
sinon = require 'sinon'

Dementor = require '../../src/dementor'
{ProjectFiles} = require '../../src/projectFiles'
{fileUtils} = require '../util/fileUtils'
MockDdpClient = require '../mock/mockDdpClient'
{errors, errorType} = require '../../madeye-common/common'
{Logger} = require '../../madeye-common/common'
{crc32} = require '../../madeye-common/common'

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
          files = dementor.fileTree.ddpFiles.getFiles()
          #HACK: Find a better way to find how many top-level files there are
          assert.equal files.length, 3
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

    describe "when already registered", ->
      targetFileTree = projectId = null
      before (done) ->
        fileMap = fileUtils.defaultFileMap
        targetFileTree = fileUtils.constructFileTree fileMap, "."
        projectPath = fileUtils.createProject "alreadyEnableTest-#{randomString()}", fileMap
        projectId = randomString()

        ddpClient = new MockDdpClient
          connect: ->
            process.nextTick => @emit 'connected'
          registerProject: sinon.stub()
          subscribe: sinon.stub()
          addFile: (file) ->
            file._id = randomString()
            process.nextTick =>
              @emit 'added', file
        ddpClient.registerProject.callsArgWith 1, null, projectId
        ddpClient.subscribe.withArgs('files').callsArg 2

        #Make a dementor to save project files
        #This one doesn't have projectId set right, so have to make a new one
        dementor = new Dementor
          directory: projectPath
          ddpClient: ddpClient
        dementor.projectFiles.saveProjectId projectId

        dementor = new Dementor
          directory: projectPath
          ddpClient: ddpClient
        dementor.fileTree.on 'added initial files', ->
          done()
        dementor.enable()

      it "should call ddpClient.registerProject with projectId", ->
        params = ddpClient.registerProject.args[0][0]
        assert.equal params.projectId, projectId

      it "should update project files if already registered", ->
        assert.ok dementor.projectId
        assert.equal dementor.projectFiles.projectIds()[projectPath], dementor.projectId, "Stored projectId differs from dementor's"
        assert.equal dementor.projectId, projectId, "Dementor's projectId differs from original."

      it "should populate file tree with files (and ids)", (done) ->
        #Give the async bits time to process.
        setTimeout ->
          assert.ok dementor.fileTree
          files = dementor.fileTree.ddpFiles.getFiles()
          #HACK: Find a better way to find how many top-level files there are
          assert.equal files.length, 3
          for file in files
            assert.ok file.isDir?
            assert.ok file.path
            assert.ok file._id
          done()
        , 100

  describe "receiving 'request file' command", ->
    dementor = ddpClient = projectFiles = null
    commandId = fileId = null

    beforeEach ->
      commandId = randomString()
      fileId = randomString()
      projectFiles =
        getProjectId: -> randomString()
        retrieveContents: sinon.stub()
      ddpClient = new MockDdpClient
        commandReceived: sinon.spy()
        updateFile: sinon.spy()
        
      dementor = new Dementor
        directory: randomString()
        projectFiles: projectFiles
        ddpClient: ddpClient


    checkCommandError = (reason, commandId) ->
      assert.isTrue ddpClient.commandReceived.called
      error = ddpClient.commandReceived.getCall(0).args[0]
      data = ddpClient.commandReceived.getCall(0).args[1]
      assert.ok error, "There should be an error"
      assert.equal error.reason, reason
      assert.equal data.commandId, commandId

    it 'should return MissingParameter error if no fileId is sent', ->
      ddpClient.emit 'command', 'request file', {commandId}
      checkCommandError 'MissingParameter', commandId

    it 'should return FileNotFound error if no file is found is sent', ->
      ddpClient.emit 'command', 'request file', {commandId, fileId:randomString()}
      checkCommandError 'FileNotFound', commandId

    it 'should return errors given by projectFiles', ->
      projectFiles.retrieveContents.callsArgWith 1, errors.new 'IsDirectory'
      #XXX: This is awkward, and looks at internal details
      dementor.fileTree.ddpFiles.addDdpFile {_id:fileId, path: 'a/path.txt'}
      ddpClient.emit 'command', 'request file', {commandId, fileId}
      checkCommandError 'IsDirectory', commandId

    it 'should call updateFile with correct data', ->
      contents = 'With a kitten, is life real, or just imgur?'
      checksum = 123311
      projectFiles.retrieveContents.callsArgWith 1, null, {checksum, contents}
      #XXX: This is awkward, and looks at internal details
      dementor.fileTree.ddpFiles.addDdpFile {_id:fileId, path: 'a/path.txt'}
      ddpClient.emit 'command', 'request file', {commandId, fileId}
      assert.isTrue ddpClient.updateFile.calledWith fileId
      updateData = ddpClient.updateFile.args[0][1]
      assert.equal updateData.loadChecksum, checksum
      assert.equal updateData.fsChecksum, checksum
      assert.ok updateData.lastOpened

    it 'should call commandReceived with contents', ->
      contents = 'With a kitten, is life real, or just imgur?'
      checksum = 123311
      projectFiles.retrieveContents.callsArgWith 1, null, {checksum, contents}
      #XXX: This is awkward, and looks at internal details
      dementor.fileTree.ddpFiles.addDdpFile {_id:fileId, path: 'a/path.txt'}
      ddpClient.emit 'command', 'request file', {commandId, fileId}
      assert.isTrue ddpClient.commandReceived.calledWith null
      results = ddpClient.commandReceived.args[0][1]
      assert.equal results.commandId, commandId
      assert.equal results.fileId, fileId
      assert.equal results.contents, contents


  describe "receiving 'save file' command", ->
    dementor = ddpClient = projectFiles = null
    commandId = fileId = null
    contents = "somehow, somewhere, a kitten is falling suddenly alseep"

    beforeEach ->
      commandId = randomString()
      fileId = randomString()
      projectFiles =
        getProjectId: -> randomString()
        writeFile: sinon.stub()
      ddpClient = new MockDdpClient
        commandReceived: sinon.spy()
        updateFile: sinon.spy()
        
      dementor = new Dementor
        directory: randomString()
        projectFiles: projectFiles
        ddpClient: ddpClient


    checkCommandError = (reason, commandId) ->
      assert.isTrue ddpClient.commandReceived.called
      error = ddpClient.commandReceived.getCall(0).args[0]
      data = ddpClient.commandReceived.getCall(0).args[1]
      assert.ok error, "There should be an error"
      assert.equal error.reason, reason
      assert.equal data.commandId, commandId

    it 'should return MissingParameter error if no fileId is sent', ->
      ddpClient.emit 'command', 'save file', {commandId, contents}
      checkCommandError 'MissingParameter', commandId

    it 'should return MissingParameter error if no contents is sent', ->
      ddpClient.emit 'command', 'save file', {commandId, fileId}
      checkCommandError 'MissingParameter', commandId

    it 'should return FileNotFound error if no file is found is sent', ->
      ddpClient.emit 'command', 'save file', {commandId, fileId, contents}
      checkCommandError 'FileNotFound', commandId

    it 'should return errors given by projectFiles', ->
      projectFiles.writeFile.callsArgWith 2, errors.new 'IsDirectory'
      #XXX: This is awkward, and looks at internal details
      dementor.fileTree.ddpFiles.addDdpFile {_id:fileId, path: 'a/path.txt'}
      ddpClient.emit 'command', 'save file', {commandId, fileId, contents}
      checkCommandError 'IsDirectory', commandId

    it 'should call updateFile with correct data', ->
      projectFiles.writeFile.callsArgWith 2, null
      #XXX: This is awkward, and looks at internal details
      dementor.fileTree.ddpFiles.addDdpFile {_id:fileId, path: 'a/path.txt'}
      ddpClient.emit 'command', 'save file', {commandId, fileId, contents}
      assert.isTrue ddpClient.updateFile.calledWith fileId
      updateData = ddpClient.updateFile.args[0][1]
      checksum = crc32 contents
      assert.equal updateData.loadChecksum, checksum
      assert.equal updateData.fsChecksum, checksum

    it 'should call commandReceived', ->
      projectFiles.writeFile.callsArgWith 2, null
      #XXX: This is awkward, and looks at internal details
      dementor.fileTree.ddpFiles.addDdpFile {_id:fileId, path: 'a/path.txt'}
      ddpClient.emit 'command', 'save file', {commandId, fileId, contents}
      assert.isTrue ddpClient.commandReceived.calledWith null
      results = ddpClient.commandReceived.args[0][1]
      assert.equal results.commandId, commandId


