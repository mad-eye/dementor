FileTree = require("../../src/fileTree")
assert = require "assert"
_path = require "path"
uuid = require "node-uuid"
_ = require 'underscore'
{assert} = require 'chai'

describe "FileTree", ->

  describe "constructor", ->
    it "accepts a null rawFiles argument", ->
      #Shouldn't throw an error
      tree = new FileTree

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
