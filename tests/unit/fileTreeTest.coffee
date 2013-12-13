FileTree = require("../../src/fileTree")
_path = require "path"
uuid = require "node-uuid"
hat = require 'hat'
_ = require 'underscore'
{assert} = require 'chai'
{EventEmitter} = require 'events'
sinon = require 'sinon'
Logger = require 'pince'
MockDdpClient = require '../mock/mockDdpClient'
DdpFiles = require '../../src/ddpFiles'
{findParentPath} = require '../../madeye-common/common'
{errors} = require '../../madeye-common/common'

randomString = -> hat 32, 16

describe "FileTree", ->

  describe '_addFsFile', ->
    tree = null
    ddpClient = null
    ago = Date.now()
    later = ago + 1000

    before ->
      ddpClient = new MockDdpClient
        addFile: sinon.spy()
        updateFile: sinon.spy()
      tree = new FileTree ddpClient, null, new DdpFiles()

    it 'should not error on null file', ->
      tree._addFsFile null

    it 'should ddp addFile on a new file', ->
      file =
        path: 'tooo.py'
        mtime: ago
      tree._addFsFile file
      assert.isTrue ddpClient.addFile.called
      assert.isTrue ddpClient.addFile.calledWith file



    describe 'over existing file', ->
      projectFiles = null
      ddpFiles = null
      beforeEach ->
        ddpClient = new MockDdpClient
          addFile: sinon.spy()
          updateFile: sinon.spy()
          updateFileContents: sinon.spy()
        projectFiles = {retrieveContents: sinon.stub()}
        ddpFiles = new DdpFiles()
        tree = new FileTree ddpClient, projectFiles, ddpFiles
        Logger.listen tree, 'tree'

      it "should do nothing if new file's mtime is not newer", ->
        file =
          _id: uuid.v4()
          path: 'to.txt'
          mtime: ago
        ddpFiles.addDdpFile file
        newFile =
          path: file.path
          mtime: ago
        tree._addFsFile newFile
        assert.isFalse ddpClient.addFile.called
        assert.isFalse ddpClient.updateFile.called

      it "should should only update mtime if file is not opened", ->
        file =
          _id: uuid.v4()
          path: uuid.v4()
          mtime: ago
        ddpFiles.addDdpFile file
        newFile =
          path: file.path
          mtime: later
        tree._addFsFile newFile
        assert.isFalse ddpClient.addFile.called
        assert.isTrue ddpClient.updateFile.called
        [fileId, updateFields] = ddpClient.updateFile.getCall(0).args
        assert.equal fileId, file._id
        assert.deepEqual updateFields, {mtime: later}

      it "should should update mtime, fsChecksum if file is opened not modified", ->
        file =
          _id: uuid.v4()
          path: uuid.v4()
          mtime: ago
          lastOpened: ago
          fsChecksum: 1235
          loadChecksum: 1235
        ddpFiles.addDdpFile file
        newFile =
          path: file.path
          mtime: later

        contentResults =
          contents : 'asd8asdfjafd'
          checksum : 9987066
        projectFiles.retrieveContents.callsArgWith 1, null, contentResults

        tree._addFsFile newFile
        assert.isFalse ddpClient.addFile.called,
          "shouldn't call addFile"

        assert.isTrue ddpClient.updateFile.called,
          "should call updateFile"
        [fileId, updateFields] = ddpClient.updateFile.getCall(0).args
        assert.equal fileId, file._id
        assert.deepEqual updateFields,
          mtime: later
          fsChecksum: contentResults.checksum
          loadChecksum: contentResults.checksum

        assert.isTrue ddpClient.updateFileContents.called,
          "should call updateFileContents"
        [fileId, contents] = ddpClient.updateFileContents.getCall(0).args
        assert.equal fileId, file._id
        assert.deepEqual contents, contentResults.contents

      it "should update loadChecksum and call updateFileContents if modified", ->
        file =
          _id: uuid.v4()
          path: uuid.v4()
          mtime: ago
          lastOpened: ago
          fsChecksum: 1235
          loadChecksum: 1235
          modified: true
        ddpFiles.addDdpFile file
        newFile =
          path: file.path
          mtime: later

        contentResults =
          contents : 'asdfsdfafd'
          checksum : 99870
        projectFiles.retrieveContents.callsArgWith 1, null, contentResults

        tree._addFsFile newFile
        assert.isFalse ddpClient.addFile.called,
          "shouldn't call addFile"

        assert.isTrue ddpClient.updateFile.called,
          "should call updateFile"
        [fileId, updateFields] = ddpClient.updateFile.getCall(0).args
        assert.equal fileId, file._id
        assert.deepEqual updateFields,
          mtime: later
          fsChecksum: contentResults.checksum

        assert.isFalse ddpClient.updateFileContents.called,
          "shouldn't call updateFileContents"


  describe "loadDirectory", ->
    tree = null
    ddpClient = null
    file1 =
      _id: uuid.v4()
      path: 'a/ways/down/to.txt'
      mtime: 123444
    file2 =
      _id: uuid.v4()
      path: 'a/ways/down/below.txt'
      mtime: 123444
    file3 =
      _id: uuid.v4()
      path: 'a/ways/up/here.txt'
      mtime: 123444
    file4 =
      _id: uuid.v4()
      path: 'top.txt'
      mtime: 123444
    beforeEach ->
      ddpClient = new MockDdpClient
        addFile: sinon.spy()
        updateFile: sinon.spy()
        removeFile: sinon.spy()
        markDirectoryLoaded: sinon.spy()
      ddpFiles = new DdpFiles()
      tree = new FileTree ddpClient, null, ddpFiles
      ddpFiles.addDdpFile file1
      ddpFiles.addDdpFile file2
      ddpFiles.addDdpFile file3
      ddpFiles.addDdpFile file4

    it "call markDirectoryLoaded", ->
      tree.loadDirectory 'a/ways/up', [file3]
      assert.isTrue ddpClient.markDirectoryLoaded.called
      assert.isTrue ddpClient.markDirectoryLoaded.calledWith 'a/ways/up'

    it "should add new files", ->
      newFile =
        path: 'a/ways/down/around.txt'
      tree.loadDirectory 'a/ways/down', [newFile]
      assert.isTrue ddpClient.addFile.called
      assert.isTrue ddpClient.addFile.calledWith newFile

    it "should update existing files", ->
      newFile =
        path: file2.path
        mtime: 223444
      tree.loadDirectory 'a/ways/down', [newFile]
      assert.isTrue ddpClient.updateFile.called
      assert.isTrue ddpClient.updateFile.calledWith(file2._id, mtime:newFile.mtime)

    it "should remove orphaned files", ->
      newFile =
        path: file2.path
        mtime: file2.mtime
      tree.loadDirectory 'a/ways/down', [newFile]
      assert.isTrue ddpClient.removeFile.called
      assert.isTrue ddpClient.removeFile.calledWith(file1._id)

    it "should remove orphaned files in top level directory", ->
      tree.loadDirectory null, []
      assert.isTrue ddpClient.removeFile.called
      assert.isTrue ddpClient.removeFile.calledWith(file4._id)

  describe 'on ddp file event', ->
    tree = null
    ddpFiles = null
    ddpClient = new MockDdpClient
    file = _id: uuid.v4(), path: 'a/path', isDir:false, modified:true
    beforeEach ->
      ddpFiles =
        addDdpFile: sinon.spy()
        removeDdpFile: sinon.spy()
        changeDdpFile: sinon.spy()
      tree = new FileTree ddpClient, null, ddpFiles
      tree.filesPending.push findParentPath file.path

    it 'added should call ddpFiles.addDdpFile', ->
      ddpClient.emit 'added', file
      assert.isTrue ddpFiles.addDdpFile.calledWith file

    it 'removed should call ddpFiles.removeDdpFile', ->
      ddpClient.emit 'removed', file._id
      assert.isTrue ddpFiles.removeDdpFile.calledWith file._id

    it 'changed should call ddpFiles.changeDdpFile', ->
      ddpClient.emit 'changed', file._id, {isDir:true}, ['modified']
      assert.isTrue ddpFiles.changeDdpFile.calledWith file._id, {isDir:true}, ['modified']

  describe 'on ddp activeDir', ->
    tree = null
    projectFiles = null
    ddpClient = null
    dir = file = null
    beforeEach ->
      dir =
        _id : randomString()
        path : "more/#{randomString()}"
      file =
        path: "#{dir.path}/rarrrrrrrrr"
      projectFiles = {readdir: sinon.stub()}
      ddpClient = new MockDdpClient
        addFile: sinon.spy()
        updateFile: sinon.spy()
        removeFile: sinon.spy()
        markDirectoryLoaded: sinon.spy()
      tree = new FileTree ddpClient, projectFiles, new DdpFiles()
      projectFiles.readdir.callsArgWith 1, null, [file]
      dir =
        _id : randomString()
        path : "more/#{randomString()}"
      ddpClient.emit 'activeDir', dir

    it 'should read dir', ->
      assert.isTrue projectFiles.readdir.called, 'Should call readdir'
      assert.isTrue projectFiles.readdir.calledWith(dir.path), 'Should call readdir with dir.path'

    it 'should call markDirectoryLoaded', ->
      assert.isTrue ddpClient.markDirectoryLoaded.called
      assert.isTrue ddpClient.markDirectoryLoaded.calledWith dir.path

    it 'should call ddpClient.addFile for new file', ->
      assert.isTrue ddpClient.addFile.called
      assert.isTrue ddpClient.addFile.calledWith file

    it 'should make directory active', ->
      assert.isTrue tree.isActiveDir dir.path

  describe 'on missing activeDir', ->
    tree = null
    projectFiles = null
    ddpClient = null
    dir = activeDir = file = null
    beforeEach ->
      dir =
        _id : randomString()
        path : "more/#{randomString()}"
      activeDir =
        _id : randomString()
        path : dir.path
      projectFiles = {readdir: sinon.stub()}
      ddpClient = new MockDdpClient
        remove: sinon.spy()
        removeFile: sinon.spy()
        markDirectoryLoaded: sinon.spy()
      ddpFiles = new DdpFiles()
      ddpFiles.addDdpFile dir
      tree = new FileTree ddpClient, projectFiles, ddpFiles
      err = errors.new 'FileNotFound', path: dir.path
      err.path = dir.path
      projectFiles.readdir.callsArgWith 1, err
      ddpClient.emit 'activeDir', activeDir

    it 'should not call markDirectoryLoaded', ->
      assert.isFalse ddpClient.markDirectoryLoaded.called

    it 'should remove the activeDir', ->
      assert.isTrue ddpClient.remove.called
      assert.isTrue ddpClient.remove.calledWith 'activeDirectories', activeDir._id

    it 'should remove the ddp file corresponding to activeDir', ->
      assert.isTrue ddpClient.removeFile.called, "removeFile should be called"
      assert.isTrue ddpClient.removeFile.calledWith(dir._id), "removeFile should be called with id #{dir._id}"

    it 'should not error if the ddp file corresponding to activeDir is missing', ->
      ddpClient.emit 'activeDir', {_id: randomString(), path : "more/#{randomString()}"}


  describe 'removeFsFile', ->
    tree = null
    ddpClient = null
    modifiedFile =
      _id: uuid.v4()
      path: uuid.v4()
      modified: true

    unmodifiedFile =
      _id: uuid.v4()
      path: uuid.v4()

    beforeEach ->
      ddpClient = new MockDdpClient
        updateFile: sinon.spy()
        removeFile: sinon.spy()
      ddpFiles = new DdpFiles()
      tree = new FileTree ddpClient, null, ddpFiles
      ddpFiles.addDdpFile modifiedFile
      ddpFiles.addDdpFile unmodifiedFile

    it 'should remove file if unmodified', ->
      tree.removeFsFile unmodifiedFile.path
      assert.isTrue ddpClient.removeFile.called
      assert.isTrue ddpClient.removeFile.calledWith unmodifiedFile._id
      assert.isFalse ddpClient.updateFile.called

    it 'should set deletedInFs=true if modified', ->
      tree.removeFsFile modifiedFile.path
      assert.isFalse ddpClient.removeFile.called
      assert.isTrue ddpClient.updateFile.called
      assert.isTrue ddpClient.updateFile.calledWith \
        modifiedFile._id, {deletedInFs:true}

    it 'should not error out if file path is unknown', ->
      tree.removeFsFile uuid.v4()

  describe 'addWatchedFile', ->
    tree = ddpClient = ddpFiles = file = null
    grandparentDir =
      path: 'one'
      mtime: 123444
      isDir: true
      isLink: false
    parentDir =
      path: 'one/two'
      mtime: 123554
      isDir: true
      isLink: false
    file =
      path: 'one/two/' + uuid.v4()
      isDir: false
      mtime: 123564
      isLink: false
      
    beforeEach ->
      ddpClient = new MockDdpClient
        addFile: sinon.spy()
      projectFiles = makeFileData: (path, callback) ->
        process.nextTick ->
          callback null, grandparentDir if path == grandparentDir.path
          callback null, parentDir if path == parentDir.path
      ddpFiles = new DdpFiles
      tree = new FileTree ddpClient, projectFiles, ddpFiles

    it 'should add the file if the parent dir is active', ->
      tree.activeDirs['one/two'] = true
      tree.addWatchedFile file
      assert.isTrue ddpClient.addFile.calledWith file

    it 'should add the parent dir if the grandparent dir is active', (done) ->
      tree.activeDirs['one'] = true
      tree.addWatchedFile file
      setTimeout ->
        #Give projectFiles time to return
        assert.isTrue ddpClient.addFile.calledWith parentDir
        done()
      , 10

    it 'should not add anything if neither dir is active', ->
      tree.addWatchedFile file
      assert.isFalse ddpClient.addFile.called

    it 'should add only one dir for two child files', (done) ->
      file1 =
        path: 'one/' + uuid.v4()
        isDir: false
      file2 =
        path: 'one/' + uuid.v4()
        isDir: false
      tree.addWatchedFile file1
      process.nextTick ->
        tree.addWatchedFile file2
      setTimeout ->
        #Give projectFiles time to return
        assert.isTrue ddpClient.addFile.calledOnce
        done()
      , 10
      

  describe 'isActiveDir', ->
    fileTree = null
    beforeEach ->
      ddpClient = new MockDdpClient
      fileTree = new FileTree ddpClient

    it 'should consider root (in various forms) active', ->
      assert.isTrue fileTree.isActiveDir '.'
      assert.isTrue fileTree.isActiveDir null


###
  describe "completeParentFiles", ->
    tree = null
    beforeEach ->
      tree = new FileTree
      tree.projectId = uuid.v4()

    it 'should add missing directories', ->
      file = _id: uuid.v4(), path: 'a1/a2/a.txt', isDir:false
      files = tree.completeParentFiles [file]
      assert.equal files.length, 3

    it 'should not add multiple copies if adding two detached files', ->
      file1 = _id: uuid.v4(), path: 'b1/b2/b.txt', isDir:false
      file2 = _id: uuid.v4(), path: 'b1/a.txt', isDir:false
      files = tree.completeParentFiles [file1, file2]
      assert.equal files.length, 4

    it 'should remember implicitly created directories', ->
      file1 = _id: uuid.v4(), path: 'b1/b2/b.txt', isDir:false
      file2 = _id: uuid.v4(), path: 'b1/a.txt', isDir:false
      files1 = tree.completeParentFiles [file1]
      files2 = tree.completeParentFiles [file2]
      assert.equal files2.length, 1

###
