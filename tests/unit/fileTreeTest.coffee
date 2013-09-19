FileTree = require("../../src/fileTree")
_path = require "path"
uuid = require "node-uuid"
_ = require 'underscore'
{assert} = require 'chai'
{EventEmitter} = require 'events'
sinon = require 'sinon'
{LogListener} = require '../../madeye-common/common'

listener = new LogListener logLevel: 'trace'

class MockDdpClient extends EventEmitter
  constructor: (services) ->
    _.extend this, services


describe "FileTree", ->

  describe 'addDdpFile', ->
    tree = null
    ddpClient = null
    file =
      _id: uuid.v4()
      path: 'a/ways/down/to.txt'
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
        path: 'a/q/tooo.py'
        mtime: ago
      tree.addFsFile file
      assert.isTrue ddpClient.addFile.called
      assert.isTrue ddpClient.addFile.calledWith file

    describe 'over existing file', ->
      dementor = null
      beforeEach ->
        ddpClient = new MockDdpClient
          addFile: sinon.spy()
          updateFile: sinon.spy()
          updateFileContents: sinon.spy()
        dementor = {retrieveContents: sinon.stub()}
        tree = new FileTree ddpClient, dementor
        listener.listen tree, 'tree'

      it "should do nothing if new file's mtime is not newer", ->
        file =
          _id: uuid.v4()
          path: 'a/ways/down/to.txt'
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
          path: 'a/ways/down/to.txt'
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
          path: 'a/ways/down/to.txt'
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
        dementor.retrieveContents.callsArgWith 1, null, contentResults

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
          path: 'a/ways/down/to.txt'
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
        dementor.retrieveContents.callsArgWith 1, null, contentResults

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


###
  describe "addFiles", ->
    it "accepts a null rawFiles argument", ->
      #Shouldn't throw an error
      tree = new FileTree
      tree.addFiles null

  describe "addFile", ->
    tree = null
    file = _id: uuid.v4(), path: 'my/path', isDir:false
    before ->
      tree = new FileTree
      tree.addFile file
      
    it "accepts a null rawFile argument", ->
      #Shouldn't throw an error
      tree.addFile null

    it "adds the file to filesById", ->
      assert.equal tree.filesById[file._id], file

    it "adds the file to filesByPath", ->
      assert.equal tree.filesByPath[file.path], file

  describe "find", ->
    tree = null
    file = _id: uuid.v4(), path: 'my/other/path', isDir:false
    before ->
      tree = new FileTree
      tree.addFile file
      
    it "should find by id", ->
      assert.equal tree.findById(file._id), file

    it "should find by path", ->
      assert.equal tree.findByPath(file.path), file

  describe 'change', ->
    tree = null
    file = _id: uuid.v4(), path: 'a/path', isDir:false, modified:true
    beforeEach ->
      tree = new FileTree
      tree.addFile file

    it 'should set fields', ->
      tree.change file._id, {'b':2}
      assert.equal tree.findById(file._id).b, 2
      assert.equal tree.findByPath(file.path).b, 2

    it 'should overwrite fields', ->
      tree.change file._id, {isDir:true}
      assert.equal tree.findById(file._id).isDir, true
      assert.equal tree.findByPath(file.path).isDir, true

    it 'should delete cleared fields', ->
      tree.change file._id, null, ['modified']
      assert.isUndefined tree.findById(file._id).modified
      assert.isUndefined tree.findByPath(file.path).modified

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
