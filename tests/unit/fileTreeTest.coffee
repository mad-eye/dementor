FileTree = require("../../src/fileTree")
_path = require "path"
uuid = require "node-uuid"
hat = require 'hat'
_ = require 'underscore'
{assert} = require 'chai'
{EventEmitter} = require 'events'
sinon = require 'sinon'
{Logger} = require '../../madeye-common/common'
MockDdpClient = require '../mock/mockDdpClient'

randomString = -> hat 32, 16

describe "FileTree", ->

  describe 'addDdpFile', ->
    tree = null
    ddpClient = null
    file =
      _id: uuid.v4()
      path: 'a/ways/down/to.txt'
      parentPath: 'a/ways/down'
    before ->
      ddpClient = new MockDdpClient
      tree = new FileTree ddpClient
      tree.addDdpFile file

    it 'should populate filesById', ->
      assert.equal tree.filesById[file._id], file

    it 'should populate filesByPath', ->
      assert.equal tree.filesByPath[file.path], file

    it 'should not error on null file', ->
      tree.addDdpFile null

    it 'should replace files on second add', ->
      file2 =
        _id: file._id
        path: file.path
        a: 2
      tree.addDdpFile file2
      assert.equal tree.filesById[file._id], file2
      assert.equal tree.filesByPath[file.path], file2

    it 'should add filePath to filePathsByParent', ->
      assert.deepEqual tree.filePathsByParent[file.parentPath], [file.path]


  describe 'addFsFile', ->
    tree = null
    ddpClient = null
    ago = Date.now()
    later = ago + 1000

    before ->
      ddpClient = new MockDdpClient
        addFile: sinon.spy()
        updateFile: sinon.spy()
      tree = new FileTree ddpClient

    it 'should not error on null file', ->
      tree.addFsFile null

    it 'should ddp addFile on a new file', ->
      file =
        path: 'tooo.py'
        mtime: ago
      tree.addFsFile file
      assert.isTrue ddpClient.addFile.called
      assert.isTrue ddpClient.addFile.calledWith file



    describe 'over existing file', ->
      projectFiles = null
      beforeEach ->
        ddpClient = new MockDdpClient
          addFile: sinon.spy()
          updateFile: sinon.spy()
          updateFileContents: sinon.spy()
        projectFiles = {retrieveContents: sinon.stub()}
        tree = new FileTree ddpClient, projectFiles
        Logger.listen tree, 'tree'

      it "should do nothing if new file's mtime is not newer", ->
        file =
          _id: uuid.v4()
          path: 'to.txt'
          mtime: ago
        tree.addDdpFile file
        newFile =
          path: file.path
          mtime: ago
        tree.addFsFile newFile
        assert.isFalse ddpClient.addFile.called
        assert.isFalse ddpClient.updateFile.called

      it "should should only update mtime if file is not opened", ->
        file =
          _id: uuid.v4()
          path: uuid.v4()
          mtime: ago
        tree.addDdpFile file
        newFile =
          path: file.path
          mtime: later
        tree.addFsFile newFile
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
        tree.addDdpFile file
        newFile =
          path: file.path
          mtime: later

        contentResults =
          contents : 'asd8asdfjafd'
          checksum : 9987066
        projectFiles.retrieveContents.callsArgWith 1, null, contentResults

        tree.addFsFile newFile
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
        tree.addDdpFile file
        newFile =
          path: file.path
          mtime: later

        contentResults =
          contents : 'asdfsdfafd'
          checksum : 99870
        projectFiles.retrieveContents.callsArgWith 1, null, contentResults

        tree.addFsFile newFile
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
      parentPath: 'a/ways/down'
      mtime: 123444
    file2 =
      _id: uuid.v4()
      path: 'a/ways/down/below.txt'
      parentPath: 'a/ways/down'
      mtime: 123444
    file3 =
      _id: uuid.v4()
      path: 'a/ways/up/here.txt'
      parentPath: 'a/ways/up'
      mtime: 123444
    beforeEach ->
      ddpClient = new MockDdpClient
        addFile: sinon.spy()
        updateFile: sinon.spy()
        removeFile: sinon.spy()
        markDirectoryLoaded: sinon.spy()
      tree = new FileTree ddpClient
      tree.addDdpFile file1
      tree.addDdpFile file2
      tree.addDdpFile file3

    it "call markDirectoryLoaded", ->
      tree.loadDirectory 'a/ways/up', [file3]
      assert.isTrue ddpClient.markDirectoryLoaded.called
      assert.isTrue ddpClient.markDirectoryLoaded.calledWith 'a/ways/up'

    it "should add new files", ->
      newFile =
        path: 'a/ways/down/around.txt'
        parentPath: 'a/ways/down'
      tree.loadDirectory 'a/ways/down', [newFile]
      assert.isTrue ddpClient.addFile.called
      assert.isTrue ddpClient.addFile.calledWith newFile

    it "should update existing files", ->
      newFile =
        path: file2.path
        parentPath: file2.parentPath
        mtime: 223444
      tree.loadDirectory 'a/ways/down', [newFile]
      assert.isTrue ddpClient.updateFile.called
      assert.isTrue ddpClient.updateFile.calledWith(file2._id, mtime:newFile.mtime)

    it "should remove orphaned files", ->
      newFile =
        path: file2.path
        parentPath: file2.parentPath
        mtime: file2.mtime
      tree.loadDirectory 'a/ways/down', [newFile]
      assert.isTrue ddpClient.removeFile.called
      assert.isTrue ddpClient.removeFile.calledWith(file1._id)

  describe 'on ddp file change', ->
    tree = null
    ddpClient = new MockDdpClient
    file = _id: uuid.v4(), path: 'a/path', isDir:false, modified:true
    beforeEach ->
      tree = new FileTree ddpClient
      tree.addDdpFile file

    it 'should set fields', ->
      ddpClient.emit 'changed', file._id, {'b':2}
      assert.equal tree.findById(file._id).b, 2
      assert.equal tree.findByPath(file.path).b, 2

    it 'should overwrite fields', ->
      ddpClient.emit 'changed', file._id, {isDir:true}
      assert.equal tree.findById(file._id).isDir, true
      assert.equal tree.findByPath(file.path).isDir, true

    it 'should delete cleared fields', ->
      ddpClient.emit 'changed', file._id, null, ['modified']
      assert.isUndefined tree.findById(file._id).modified
      assert.isUndefined tree.findByPath(file.path).modified

    it "should not touch unmentioned fields"

  describe 'on ddp readDir', ->
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
        parentPath: dir.path
      projectFiles = {readdir: sinon.stub()}
      ddpClient = new MockDdpClient
        addFile: sinon.spy()
        updateFile: sinon.spy()
        removeFile: sinon.spy()
        markDirectoryLoaded: sinon.spy()
      tree = new FileTree ddpClient, projectFiles
      projectFiles.readdir.callsArgWith 1, null, [file]
      dir =
        _id : randomString()
        path : "more/#{randomString()}"
      ddpClient.emit 'readDir', dir

    it 'should read dir', ->
      assert.isTrue projectFiles.readdir.called, 'Should call readdir'
      assert.isTrue projectFiles.readdir.calledWith(dir.path), 'Should call readdir with dir.path'

    it 'should call markDirectoryLoaded', ->
      assert.isTrue ddpClient.markDirectoryLoaded.called
      assert.isTrue ddpClient.markDirectoryLoaded.calledWith dir.path

    it 'should call ddpClient.addFile for new file', ->
      assert.isTrue ddpClient.addFile.called
      assert.isTrue ddpClient.addFile.calledWith file


  describe 'removeDdpFile', ->
    tree = null
    ddpClient = null
    file =
      _id: uuid.v4()
      path: uuid.v4()
    before ->
      ddpClient = new MockDdpClient
      tree = new FileTree ddpClient
      tree.addDdpFile file
      tree.removeDdpFile file._id

    it 'should clear filesById', ->
      assert.ok !tree.filesById[file._id]

    it 'should clear filesByPath', ->
      assert.ok !tree.filesByPath[file.path]

    it 'should not error on null file', ->
      tree.removeDdpFile null

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
      tree = new FileTree ddpClient
      tree.addDdpFile modifiedFile
      tree.addDdpFile unmodifiedFile

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
    tree = ddpClient = null
    dirOne =
      path: 'one'
      mtime: 123444
      isDir: true
      isLink: false
    dirTwo =
      path: 'one/two'
      mtime: 123554
      isDir: true
      isLink: false
    beforeEach ->
      ddpClient = new MockDdpClient
        addFile: (file) ->
          file._id = uuid.v4()
          process.nextTick =>
            @emit 'added', file
      projectFiles = makeFileData: (path, callback) ->
        process.nextTick ->
          callback null, dirOne if path == dirOne.path
          callback null, dirTwo if path == dirTwo.path
      tree = new FileTree ddpClient, projectFiles


    it 'should add the parent dirs of a file', (done) ->
      file =
        path: 'one/two/' + uuid.v4()
        isDir: false
      tree.addWatchedFile file
      #Wait for the async fns to finish
      setTimeout ->
        files = tree.getFiles()
        assert.equal files.length, 3
        assert.isTrue dirOne in files
        assert.isTrue dirTwo in files
        assert.isTrue file in files
        done()
      , 10

    it 'should add only one dir for two child files', (done) ->
      file1 =
        path: 'one/' + uuid.v4()
        isDir: false
      file2 =
        path: 'one/' + uuid.v4()
        isDir: false
      tree.addWatchedFile file1
      tree.addWatchedFile file2
      #Wait for the async fns to finish
      setTimeout ->
        files = tree.getFiles()
        assert.equal files.length, 3
        assert.isTrue dirOne in files
        assert.isTrue file1 in files
        assert.isTrue file2 in files
        done()
      , 10
      


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
