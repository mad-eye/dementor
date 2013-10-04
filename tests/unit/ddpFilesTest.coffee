_ = require 'underscore'
{assert} = require 'chai'
hat = require 'hat'
_path = require 'path'
sinon = require 'sinon'
uuid = require 'node-uuid'

{Logger} = require '../../madeye-common/common'
DdpFiles = require '../../src/ddpFiles'

randomString = -> hat 32, 16

describe 'DdpFiles', ->
  
  describe 'addDdpFile', ->
    ddpFiles = null
    file =
      _id: randomString()
      path: 'a/ways/down/to.txt'
      parentPath: 'a/ways/down'
    before ->
      ddpFiles = new DdpFiles
      ddpFiles.addDdpFile file

    it 'should populate getFiles', ->
      assert.equal ddpFiles.getFiles()[0], file

    it 'should populate filesById', ->
      assert.equal ddpFiles.findById(file._id), file

    it 'should populate filesByPath', ->
      assert.equal ddpFiles.findByPath(file.path), file

    it 'should not error on null file', ->
      ddpFiles.addDdpFile null

    it 'should replace files on second add', ->
      file2 =
        _id: file._id
        path: file.path
        a: 2
      ddpFiles.addDdpFile file2
      assert.equal ddpFiles.findById(file._id), file2
      assert.equal ddpFiles.findByPath(file.path), file2

    it 'should add filePath to filePathsByParent', ->
      assert.deepEqual ddpFiles.filePathsByParent[file.parentPath], [file.path]


  describe 'removeDdpFile', ->
    ddpFiles = null
    file =
      _id: uuid.v4()
      path: 'abd/' + uuid.v4()
      parentPath: 'abd'
    before ->
      ddpFiles = new DdpFiles
      ddpFiles.addDdpFile file
      ddpFiles.removeDdpFile file._id

    it 'should clear filesById', ->
      assert.ok !ddpFiles.findById(file._id)

    it 'should clear filesByPath', ->
      assert.ok !ddpFiles.findByPath(file.path)

    it 'should not error on null file', ->
      ddpFiles.removeDdpFile null
      
      
  describe 'updateDdpFile', ->
    ddpFiles = null
    file =
      _id: uuid.v4()
      path: 'abd/' + uuid.v4()
      parentPath: 'abd'
      isDir:false
      modified:true
    before ->
      ddpFiles = new DdpFiles
      ddpFiles.addDdpFile file
      
    it 'should add new fields', ->
      ddpFiles.changeDdpFile file._id, {'b':2}
      assert.equal ddpFiles.findById(file._id).b, 2
      assert.equal ddpFiles.findByPath(file.path).b, 2

    it 'should change existing fields', ->
      ddpFiles.changeDdpFile file._id, {isDir:true}
      assert.equal ddpFiles.findById(file._id).isDir, true
      assert.equal ddpFiles.findByPath(file.path).isDir, true
      
    it 'should remove cleared fields', ->
      ddpFiles.changeDdpFile file._id, null, ['modified']
      assert.isUndefined ddpFiles.findById(file._id).modified
      assert.isUndefined ddpFiles.findByPath(file.path).modified

    it "should not touch unmentioned fields", ->
      ddpFiles.changeDdpFile file._id, {'b':2}
      f = ddpFiles.findById(file._id)
      assert.equal f.parentPath, file.parentPath
      assert.equal f._id, file._id

    