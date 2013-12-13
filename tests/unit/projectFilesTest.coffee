fs = require 'fs'
util = require 'util'
_path = require 'path'
{assert} = require 'chai'
uuid = require 'node-uuid'
{fileUtils} = require '../util/fileUtils'
{ProjectFiles} = require '../../src/projectFiles'
events = require 'events'
hat = require 'hat'
Logger = require 'pince'

log = new Logger 'projectFilesTest'
randomString = -> hat 32, 16

homeDir = fileUtils.homeDir
process.env["MADEYE_HOME"] = _path.resolve homeDir

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


describe 'ProjectFiles', ->
  before ->
    #fileUtils.initTestArea()
    fileUtils.mkDirClean homeDir

  after ->
    #fileUtils.destroyTestArea()

  describe 'readFile', ->
    projectFiles = projectDir = null
    before ->
      projectDir = fileUtils.createProject 'readFile', fileUtils.defaultFileMap
      projectFiles = new ProjectFiles projectDir
      
    beforeEach ->
      resetHome()

    it 'should return a body when a file exists', (done) ->
      fileName = 'file.txt'
      fileBody = 'this is quite a body'
      fs.writeFileSync (_path.join projectDir, fileName), fileBody
      projectFiles.readFile fileName, (err, body) ->
        assert.equal err, null
        assert.equal body, fileBody
        done()

    it 'should return the correct error when a file does not exist', (done) ->
      fileName = 'nofile.txt'
      projectFiles.readFile fileName, (err, body) ->
        assert.ok err
        assert.equal err.reason, 'FileNotFound'
        assert.equal body, null
        done()

    it 'should return the correct error when a file is a directory', (done) ->
      fileName = 'someDir'
      fileUtils.mkDir _path.join projectDir, fileName
      projectFiles.readFile fileName, (err, body) ->
        assert.ok err
        assert.equal err.reason, 'IsDirectory'
        assert.equal body, null
        done()

  describe 'writeFile', ->
    projectFiles = null
    before ->
      projectFiles = new ProjectFiles '.'
      
    fileName = fileBody = filePath = null
    beforeEach ->
      resetHome()
      fileName = 'file.txt'
      fileBody = 'this is quite some fun time body'
      filePath = _path.join homeDir, fileName

    it 'should write the contents to the path', (done) ->
      projectFiles.writeFile filePath, fileBody, (err) ->
        assert.equal err, null
        contents = fs.readFileSync(filePath, "utf-8")
        assert.equal contents, fileBody
        done()

    it 'should overwrite existing files at that path', (done) ->
      projectFiles.writeFile filePath, fileBody, (err) ->
        assert.equal err, null
        fileBody = 'this is a different, but equally good, body'
        projectFiles.writeFile filePath, fileBody, (err) ->
          assert.equal err, null
          contents = fs.readFileSync(filePath, "utf-8")
          assert.equal contents, fileBody
          done()

  describe 'readdir', ->
    projectFiles = null

    it 'should return error if no directory exists', (done) ->
      noRootDir = _path.join homeDir, 'notADir'
      projectFiles = new ProjectFiles noRootDir
      projectFiles.readdir '', (err, results) ->
        assert.ok err
        assert.equal err.reason, 'FileNotFound'
        done()

    it 'should correctly serialize empty directory', (done) ->
      projectDir = fileUtils.createProject("vacuous", {})
      projectFiles = new ProjectFiles projectDir
      projectFiles.readdir '', (err, results) ->
        assert.equal err, null, "Should not have returned an error."
        assert.ok results, "readdir for empty directory should return true results."
        assert.deepEqual results, []
        done()

    it 'should correctly serialize directory with one file', (done) ->
      projectDir = fileUtils.createProject "oneFile",
        readme: "nothing important here"
      projectFiles = new ProjectFiles projectDir
      projectFiles.readdir '', (err, results) ->
        assert.equal err, null, "Should not have returned an error."
        assert.ok results, "readdir should return true results."
        assertFilesEqual results, [
          isDir: false
          path: "readme"
        ]
        done()

    it 'should correctly serialize directory with two files', (done) ->
      projectDir = fileUtils.createProject "twoFile",
        readme: "nothing important here"
        "app.js": "console.log('hello world');"
      projectFiles = new ProjectFiles projectDir
      projectFiles.readdir '', (err, results) ->
        assert.equal err, null, "Should not have returned an error."
        assert.ok results, "readdir should return true results."
        assertFilesEqual results, [
          {isDir: false
          path: "app.js"},
          {isDir: false
          path: "readme"}
        ]
        done()
      

    it 'should only serialize the top directory of a deep complicated directory structure', (done) ->
      projectDir = fileUtils.createProject "manyFiles",
        readme: "nothing important here"
        "app.js": "console.log('hello world');"
        dir1:
          dir2:
            ninja_turtles: "Cowabunga!"
            dir3: {}
      projectFiles = new ProjectFiles projectDir
      projectFiles.readdir '', (err, results) ->
        assert.equal err, null, "Should not have returned an error."
        assert.ok results, "readdir should return true results."
        results = results.sort (a, b) ->
          a.path > b.path
        assertFilesEqual results, [
          {isDir: false
          path: "app.js"},
          {isDir: true
          path: "dir1"},
          {isDir: false
          path: "readme"}
        ]
        done()

    it "should ignore files included in .madeyignore", (done)->
      ignoreFiles = ["superfluousFile", "superfluousDirectory", "junk", "dir2/moreJunk", "garbage", "dir4/"]
      projectDir = fileUtils.createProject "madeyeignore_test",
        rootFile: "this is the rootfile"
        ".madeyeignore": ignoreFiles.join "\n"
        superfluousFile: "this is a superfluous file"
        dir1: {}
        dir2:
          moreJunk: {}
          moderateFile: "this is a moderate file"
          superfluousDirectory:
            leafFile: "another leaf file"
          dir3:
            leafFile: "this is a leaf file"
            garbage: "garbage"
        dir4:
          stuff: "stuff"
      projectFiles = new ProjectFiles projectDir
      projectFiles.readdir '', (err, results)->
        assert.equal err, null, "Should not have returned an error."
        assert.ok results, "readdir should return true results."
        paths = (result.path for result in results)
        assert.include paths, 'dir1'
        assert.include paths, 'dir2'
        assert.include paths, 'rootFile'
        assert.notInclude paths, 'superfluousFile'
        assert.notInclude paths, 'dir4'

        results.forEach (result)->
          assert.notInclude ignoreFiles, result.path
        done()

    it 'should give relative, not absolute, paths', (done) ->
      projectDir = fileUtils.createProject "relPaths",
        readme: "nothing important here"
        dir1:
          afile: "totally cool"
      projectFiles = new ProjectFiles projectDir
      projectFiles.readdir '', (err, results) ->
        assert.equal err, null, "Should not have returned an error."
        assert.ok results, "readdir should return true results."
        results = results.sort (a, b) ->
          a.path > b.path
        assertFilesEqual results, [
          {isDir: true
          path: "dir1"},
          {isDir: false
          path: "readme"}
        ]
        done()

  describe "watchFileTree", ->
    projectFiles = projectDir = watcher = null
    beforeEach (done) ->
      projectDir = _path.resolve fileUtils.createProject "watchFileTree-#{randomString()}",
        fileUtils.defaultFileMap
      projectFiles = new ProjectFiles projectDir
      #XXX: FRAGILE Have to let the initial fs events fly past
      setTimeout ->
        done()
      , 200

    afterEach ->
      projectFiles.removeAllListeners()

    makeFile = (fileName) ->
      filePath = _path.join projectDir, fileName
      fs.writeFileSync filePath, 'touched'
      return _path.resolve filePath

    makeDir = (dirName) ->
      dirPath = _path.join projectDir, dirName
      fs.mkdirSync dirPath
      return _path.resolve dirPath

    it "should ignore cruft ~ files", (done) ->
      fileName = "file#{randomString()}.txt~"
      projectFiles.on 'file added', (file) ->
        assert.fail "Should not notice file."
      projectFiles.watchFileTree()
      makeFile fileName
      setTimeout done, 250

    it "should ignore cruft .swp files", (done) ->
      fileName = "file#{randomString()}.swp"
      projectFiles.on 'file added', (file) ->
        assert.fail "Should not notice file."
      projectFiles.watchFileTree()
      makeFile fileName
      setTimeout done, 250

    ### TODO: Enable when we upgrade to chokidar 0.8
    it "should notice when i add a file", (done) ->
      fileName = "file#{randomString()}.txt"
      projectFiles.watchFileTree()
      projectFiles.on 'file added', (file) ->
        assert.equal file.path, fileName
        assert.equal file.isDir, false
        done()
      makeFile fileName

    it "should notice when I add a directory", (done) ->
      dirName = "dir1#{randomString()}"
      projectFiles.watchFileTree()
      projectFiles.on 'file added', (file) ->
        assert.equal file.path, dirName
        assert.equal file.isDir, true
        done()
      makeDir dirName

    it "should notice when i delete a file", (done) ->
      filePath = 'dir2/moderateFile'
      projectFiles.watchFileTree()
      projectFiles.on 'file removed', (path) ->
        assert.equal path, filePath
        done()
      fs.unlinkSync _path.join projectDir, filePath

    it "should notice when i remove a directory", (done) ->
      dirPath = 'dir1'
      projectFiles.watchFileTree()
      projectFiles.on 'file removed', (path) ->
        assert.equal path, dirPath
        done()
      fs.rmdirSync _path.join projectDir, dirPath
    ###

    it "should ignore the .git directory"

    #Currently we report them, but mark them as links.
    it "should ignore broken symlinks"
      #fileName = 'DNE'
      #filePath = _path.join projectDir, fileName
      #linkName = 'brokenLink'
      #linkPath = _path.join projectDir, linkName
      #fs.symlinkSync filePath, linkPath
      #projectFiles.on 'file added', (data) ->
        #assert.fail "Should not notice file."
      #projectFiles.on 'stop', (data) ->
        #done()
      #projectFiles.watchFileTree()
      #watcher.emit 'fileCreated', linkPath
      #projectFiles.emit 'stop'



