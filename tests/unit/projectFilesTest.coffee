fs = require 'fs'
_path = require 'path'
wrench = require 'wrench'
assert = require 'assert'
{fileUtils} = require '../util/fileUtils'
{ProjectFiles} = require '../../src/projectFiles'
{errorType} = require '../../src/errors'


homeDir = fileUtils.homeDir
process.env["MADEYE_HOME"] = fileUtils.homeDir

resetHome = ->
  if fs.existsSync homeDir
    wrench.rmdirSyncRecursive homeDir
  fileUtils.mkDir homeDir

describe 'ProjectFiles', ->
  projectFiles = null
  before ->
    projectFiles = new ProjectFiles '.'
    
  describe 'readFile', ->
    beforeEach ->
      resetHome()
      if fs.existsSync homeDir
        wrench.rmdirSyncRecursive homeDir
      fileUtils.mkDir homeDir

    it 'should return a body when a file exists', (done) ->
      fileName = 'file.txt'
      fileBody = 'this is quite a body'
      filePath = _path.join homeDir, fileName
      fs.writeFileSync filePath, fileBody
      projectFiles.readFile filePath, false, (err, body) ->
        assert.equal err, null
        assert.equal body, fileBody
        done()
      
    it 'should return the correct error when a file does not exist', (done) ->
      fileName = 'nofile.txt'
      filePath = _path.join homeDir, fileName
      projectFiles.readFile filePath, false, (err, body) ->
        assert.ok err
        assert.equal err.type, errorType.NO_FILE
        assert.equal body, null
        done()

    it 'should return the correct error when a file is a directory', (done) ->
      fileName = 'someDir'
      filePath = _path.join homeDir, fileName
      fileUtils.mkDir filePath
      projectFiles.readFile filePath, false, (err, body) ->
        assert.ok err
        assert.equal err.type, errorType.NOT_NORMAL_FILE
        assert.equal body, null
        done()

    it 'should read from absolute paths when absolute=true'
    it 'should allow absolute argument to be skipped'

  describe 'writeFile', ->
    fileName = fileBody = filePath = null
    beforeEach ->
      resetHome()
      fileName = 'file.txt'
      fileBody = 'this is quite a body'
      filePath = _path.join homeDir, fileName

    it 'should write the contents to the path', (done) ->
      projectFiles.writeFile filePath, fileBody, false, (err) ->
        assert.equal err, null
        contents = fs.readFileSync(filePath, "utf-8")
        assert.equal contents, fileBody
        done()

    it 'should overwrite existing files at that path', (done) ->
      projectFiles.writeFile filePath, fileBody, false, (err) ->
        assert.equal err, null
        fileBody = 'this is a different, but equally good, body'
        projectFiles.writeFile filePath, fileBody, false, (err) ->
          assert.equal err, null
          contents = fs.readFileSync(filePath, "utf-8")
          assert.equal contents, fileBody
          done()

    it 'should write to absolute paths when absolute=true'

  describe 'exists', ->
    filePath = null

    before ->
      resetHome()
      fileName = 'file.txt'
      fileBody = 'this is quite a body'
      filePath = _path.join homeDir, fileName
      fs.writeFileSync filePath, fileBody

    it 'should return true when a file exists fweep', ->
      assert.equal projectFiles.exists(filePath), true

    it 'should return false when a file does not exist', ->
      noFilePath = _path.join homeDir, 'nofile'
      assert.equal projectFiles.exists(noFilePath), false

  describe 'readFileTree', ->
    it 'should return error if no directory exists'
    it 'should correctly serialize empty directory'
    it 'should correctly serialize directory with one file'
    it 'should correctly serialize directory with two file'
    it 'should correctly serialize a deep complicated directory structure'

  #TODO: Write event handlers for watchFileTree
