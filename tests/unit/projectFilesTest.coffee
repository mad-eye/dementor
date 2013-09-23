fs = require 'fs'
_path = require 'path'
wrench = require 'wrench'
{assert} = require 'chai'
uuid = require 'node-uuid'
{fileUtils} = require '../util/fileUtils'
{ProjectFiles} = require '../../src/projectFiles'
{errorType} = require '../../madeye-common/common'
events = require 'events'


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
        assert.equal err.type, errorType.NO_FILE
        assert.equal body, null
        done()

    it 'should return the correct error when a file is a directory', (done) ->
      fileName = 'someDir'
      fileUtils.mkDir _path.join projectDir, fileName
      projectFiles.readFile fileName, (err, body) ->
        assert.ok err
        assert.equal err.type, errorType.IS_DIR
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

  describe 'readFileTree', ->
    projectFiles = null

    it 'should return error if no directory exists', (done) ->
      noRootDir = _path.join homeDir, 'notADir'
      projectFiles = new ProjectFiles noRootDir
      projectFiles.readFileTree (err, results) ->
        assert.ok err
        assert.equal err.type, errorType.NO_FILE
        done()

    it 'should correctly serialize empty directory', (done) ->
      projectDir = fileUtils.createProject("vacuous", {})
      projectFiles = new ProjectFiles projectDir
      projectFiles.readFileTree (err, results) ->
        assert.equal err, null, "Should not have returned an error."
        assert.ok results, "readFileTree for empty directory should return true results."
        assert.deepEqual results, []
        done()

    it 'should correctly serialize directory with one file', (done) ->
      projectDir = fileUtils.createProject "oneFile",
        readme: "nothing important here"
      projectFiles = new ProjectFiles projectDir
      projectFiles.readFileTree (err, results) ->
        assert.equal err, null, "Should not have returned an error."
        assert.ok results, "readFileTree should return true results."
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
      projectFiles.readFileTree (err, results) ->
        assert.equal err, null, "Should not have returned an error."
        assert.ok results, "readFileTree should return true results."
        assertFilesEqual results, [
          {isDir: false
          path: "app.js"},
          {isDir: false
          path: "readme"}
        ]
        done()
      

    it 'should correctly serialize a deep complicated directory structure', (done) ->
      projectDir = fileUtils.createProject "manyFiles",
        readme: "nothing important here"
        "app.js": "console.log('hello world');"
        dir1:
          dir2:
            ninja_turtles: "Cowabunga!"
            dir3: {}
      projectFiles = new ProjectFiles projectDir
      projectFiles.readFileTree (err, results) ->
        assert.equal err, null, "Should not have returned an error."
        assert.ok results, "readFileTree should return true results."
        results = results.sort (a, b) ->
          a.path > b.path
        assertFilesEqual results, [
          {isDir: false
          path: "app.js"},
          {isDir: true
          path: "dir1"},
          {isDir: true
          path: "dir1/dir2"},
          {isDir: true
          path: "dir1/dir2/dir3"},
          {isDir: false
          path: "dir1/dir2/ninja_turtles"},
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
      projectFiles.readFileTree (err, results)->
        assert.equal err, null, "Should not have returned an error."
        assert.ok results, "readFileTree should return true results."
        paths = (result.path for result in results)
        assert.include paths, 'dir1'
        assert.include paths, 'dir2/moderateFile'
        assert.notInclude paths, 'dir2/dir3/garbage'
        assert.notInclude paths, 'dir4'
        assert.notInclude paths, 'dir4/stuff'

        results.forEach (result)->
          assert.notInclude ignoreFiles, result.path
        done()

    it 'should give relative, not absolute, paths', (done) ->
      projectDir = fileUtils.createProject "relPaths",
        readme: "nothing important here"
        dir1:
          afile: "totally cool"
      projectFiles = new ProjectFiles projectDir
      projectFiles.readFileTree (err, results) ->
        assert.equal err, null, "Should not have returned an error."
        assert.ok results, "readFileTree should return true results."
        results = results.sort (a, b) ->
          a.path > b.path
        assertFilesEqual results, [
          {isDir: true
          path: "dir1"},
          {isDir: false
          path: "dir1/afile"},
          {isDir: false
          path: "readme"}
        ]
        done()


  describe "projectIds", ->
    projects = projectFiles = null
    before ->
      projects =
        "path/to/heaven" : uuid.v4()
        "/path/to/hell/" : uuid.v4()
      projectFiles = new ProjectFiles
      if fs.existsSync projectFiles.projectsDbPath()
        fs.unlinkSync projectFiles.projectsDbPath()
    it "should return {} if no config file", ->
      readProjects = projectFiles.projectIds()
      assert.deepEqual readProjects, {}

    it "should return a JSON config if it exists", ->
      fs.writeFileSync projectFiles.projectsDbPath(), JSON.stringify(projects)
      assert.deepEqual projectFiles.projectIds(), projects

    it "should save a config file", ->
      projectFiles.saveProjectIds projects
      assert.ok fs.existsSync projectFiles.projectsDbPath()
      readProjects = JSON.parse fs.readFileSync(projectFiles.projectsDbPath(), 'utf-8')
      assert.deepEqual projects, readProjects
      
    it "should save over an existing config file", ->
      projectFiles.saveProjectIds projects
      newProjects =
        "one/two/three" : uuid.v4()
      projectFiles.saveProjectIds newProjects
      assert.ok fs.existsSync projectFiles.projectsDbPath()
      readProjects = JSON.parse fs.readFileSync(projectFiles.projectsDbPath(), 'utf-8')
      assert.deepEqual newProjects, readProjects


  describe "watchFileTree", ->
    projectFiles = projectDir = watcher = null
    before ->
      projectDir = _path.resolve fileUtils.createProject 'watchFileTree', fileUtils.defaultFileMap
      projectFiles = new ProjectFiles projectDir
      projectFiles.fileWatcher =
        watch: (directory) ->
          watcher = new events.EventEmitter
          watcher.directory = directory
          return watcher

    beforeEach ->
      resetHome()
      projectFiles.removeAllListeners 'stop'
      projectFiles.removeAllListeners 'file added'

    makeFile = (fileName) ->
      filePath = _path.join projectDir, fileName
      fs.writeFileSync filePath, 'touched'
      return _path.resolve filePath

    makeDir = (dirName) ->
      dirPath = _path.join projectDir, dirName
      fs.mkdir dirPath
      return _path.resolve dirPath

    ###
    #FIXME: Very strange error sometimes on this test
    #It is caused somehow by deleted/recreating the test dir.
    1) ProjectFiles watchFileTree should notice when i add a file:
      
      actual expected
      
      4f1e7bac54d6fc2c-7c3497e2-4fd14b3c-bea189d3-4b8b11bd965095bdbfd6c18c
      
  AssertionError: "54d6fc2c-97e2-4b3c-89d3-95bdbfd6c18c" == "4f1e7bac-7c34-4fd1-bea1-4b8b11bd9650"
      at MockIoSocket.mockSocket.onEmit (/Users/jag/Dropbox/madeye/dementor/tests/unit/dementorTest.coffee:442:20)
      at MockIoSocket.emit (/Users/jag/Dropbox/madeye/dementor/node_modules/madeye-common/tests/mock/MockIoSocket.coffee:32:55)
      at ProjectFiles.Dementor.watchProject (/Users/jag/Dropbox/madeye/dementor/src/dementor.coffee:131:29)
      at ProjectFiles.EventEmitter.emit (events.js:96:17)
      at StatWatcher.ProjectFiles.watchFileTree (/Users/jag/Dropbox/madeye/dementor/src/projectFiles.coffee:265:22)
      at StatWatcher.EventEmitter.emit (events.js:96:17)
      at exports.StatWatcher.StatWatcher.statPath (/Users/jag/Dropbox/madeye/dementor/node_modules/watch-tree-maintained/lib/watchers/stat.js:102:21)
      at Object.oncomplete (fs.js:297:15)
    ###
    it "should notice when i add a file", (done) ->
      fileName = 'file.txt'
      filePath = makeFile fileName
      projectFiles.on 'file added', (file) ->
        assert.equal file.path, fileName
        assert.equal file.isDir, false
        done()
      projectFiles.watchFileTree()
      watcher.emit 'add', filePath

    #FIXME: Same strange error here
    it "should ignore cruft ~ files", (done) ->
      #TODO include a few other file types here (i.e. garbage.swp)
      fileName = 'file.txt~'
      filePath = makeFile fileName
      projectFiles.on 'file added', (data) ->
        assert.fail "Should not notice file."
      projectFiles.on 'stop', (data) ->
        done()
      projectFiles.watchFileTree()
      watcher.emit 'add', filePath
      projectFiles.emit 'stop'

    it "should ignore cruft .swp files", (done) ->
      #TODO include a few other file types here (i.e. garbage.swp)
      fileName = '.file.txt.swp'
      filePath = makeFile fileName
      projectFiles.on 'file added', (data) ->
        assert.fail "Should not notice file."
      projectFiles.on 'stop', (data) ->
        done()
      projectFiles.watchFileTree()
      watcher.emit 'add', filePath
      projectFiles.emit 'stop'

    it "should notice when I add a directory"

    it "should notice when i delete a file"

    it "should notice when i change a file"

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



