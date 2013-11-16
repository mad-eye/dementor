fs = require 'fs'
_path = require 'path'
{assert} = require 'chai'
hat = require 'hat'
rimraf = require 'rimraf'
mkdirp = require 'mkdirp'
{fileUtils} = require '../util/fileUtils'
Home = require '../../src/home'

randomString = -> hat 32, 16

homeDir = fileUtils.homeDir
homeDirAbs = _path.resolve homeDir
process.env.MADEYE_HOME_TEST = homeDirAbs
_saveProjectId = (projectPath, projectId) ->
  (new Home projectPath).saveProjectId projectId

resetHome = ->
  fileUtils.mkDirClean homeDir

assertFilesEqual = (files, expectedFiles) ->
  assert.equal files.length, expectedFiles.length
  files.sort (f1,f2) -> f1.path < f2.path
  expectedFiles.sort (f1,f2) -> f1.path < f2.path
  for file, i in files
    expectedFile = expectedFiles[i]
    assert.equal file.path, expectedFile.path
    assert.equal file.isDir, expectedFile.isDir
    assert.isNotNull file.isLink
    assert.equal typeof file.mtime, 'number'


describe 'Home', ->
  describe 'init', ->
    home = null
    beforeEach ->
      rimraf.sync homeDir
      home = new Home randomString()

    it 'should create $MADEYE_HOME if it doesnt exist', ->
      home.init()
      assert.ok fs.existsSync(homeDir), "Should have created #{homeDir}"

    it 'should not remove files from $MADEYE_HOME if it does exist', ->
      mkdirp homeDir
      filename = _path.join homeDir, randomString()
      fs.writeFileSync filename, 'adfsfd'
      home.init()
      assert.ok fs.existsSync filename

  describe "getProjectId", ->
    projects = null
    heavenId = heavenPath = null
    beforeEach ->
      #Make homeDir
      (new Home '').init()
      heavenId = randomString()
      heavenPath = "path/to/heaven/" + randomString()
      _saveProjectId heavenPath, heavenId

    it "should return undefined if a new dir", ->
      home = new Home randomString()
      assert.isUndefined home.getProjectId()

    it 'should return the right projectId if its a known project dir', ->
      home = new Home heavenPath
      assert.equal home.getProjectId(), heavenId

  describe 'saveProjectId', ->

    it "should save a projectId", ->
      projectPath = randomString() + '/' + randomString()
      projectId = randomString()
      home = new Home projectPath
      home.init()
      home.saveProjectId projectId
      assert.equal home.getProjectId(), projectId

