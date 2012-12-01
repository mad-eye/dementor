fs = require 'fs'
_path = require 'path'
wrench = require 'wrench'
assert = require 'assert'
{fileUtils} = require '../util/fileUtils'
{ProjectFiles} = require '../../src/projectFiles'
{errorType} = require '../../src/errors'


homeDir = fileUtils.homeDir
process.env["MADEYE_HOME"] = fileUtils.homeDir

describe 'ProjectFiles', ->
  projectFiles = null
  before ->
    projectFiles = new ProjectFiles '.'
    
  beforeEach ->
    if fs.existsSync homeDir
      wrench.rmdirSyncRecursive homeDir
    fileUtils.mkDir homeDir

  describe 'readFile', ->
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

    it 'should return the correct error when a file is a directory'
    it 'should read from absolute paths when absolute=true'
    it 'should allow absolute argument to be skipped'

  describe 'writeFile', ->
    it 'should write the contents to the path'
    it 'should overwrite existing files at that path'
    it 'should write to absolute paths when absolute=true'

  describe 'exists', ->
    it 'should return true when a file exists'
    it 'should return false when a file does not exist'

  describe 'readFileTree', ->
    it 'should return error if no directory exists'
    it 'should correctly serialize empty directory'
    it 'should correctly serialize directory with one file'
    it 'should correctly serialize directory with two file'
    it 'should correctly serialize a deep complicated directory structure'

  #TODO: Write event handlers for watchFileTree
