fs = require 'fs'
_path = require 'path'
wrench = require 'wrench'
assert = require 'assert'
uuid = require 'node-uuid'
{fileUtils} = require '../util/fileUtils'
{ProjectFiles} = require '../../src/projectFiles'
{errorType, messageAction} = require 'madeye-common'
events = require 'events'


baseDir = process.cwd()
homeDir = fileUtils.homeDir
process.env["MADEYE_HOME"] = _path.join baseDir, homeDir

resetHome = ->
  resetProject homeDir

resetProject = (rootDir) ->
  if fs.existsSync rootDir
    wrench.rmdirSyncRecursive rootDir
  fileUtils.mkDir rootDir

describe 'ProjectFiles', ->
  describe 'readFile', ->
    projectFiles = null
    before ->
      projectFiles = new ProjectFiles '.'
      
      beforeEach ->
        resetHome()

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
        assert.equal err.type, errorType.IS_DIR
        assert.equal body, null
        done()

    it 'should read from absolute paths when absolute=true'
    it 'should allow absolute argument to be skipped'

  describe 'writeFile', ->
    projectFiles = null
    before ->
      projectFiles = new ProjectFiles '.'
      
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

  describe 'readFileTree', ->
    projectFiles = null

    it 'should return error if no directory exists', (done) ->
      noRootDir = _path.join homeDir, 'notADir'
      projectFiles = new ProjectFiles noRootDir
      projectFiles.readFileTree (err, results) ->
        assert.ok err
        assert.equal err.type, errorType.NO_FILE
        assert.equal results, null
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
        assert.deepEqual results, [
          isDir: false
          path: "readme"
        ]
        done()

    it 'should correctly serialize directory with two file', (done) ->
      projectDir = fileUtils.createProject "twoFile",
        readme: "nothing important here"
        "app.js": "console.log('hello world');"
      projectFiles = new ProjectFiles projectDir
      projectFiles.readFileTree (err, results) ->
        assert.equal err, null, "Should not have returned an error."
        assert.ok results, "readFileTree should return true results."
        assert.deepEqual results, [
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
        assert.deepEqual results, [
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

    it 'should give relative, not absolute, paths', (done) ->
      projectDir = fileUtils.createProject "relPaths",
        readme: "nothing important here"
        dir1:
          afile: "totally cool"
      projectFiles = new ProjectFiles projectDir
      projectFiles.readFileTree (err, results) ->
        assert.equal err, null, "Should not have returned an error."
        assert.ok results, "readFileTree should return true results."
        assert.deepEqual results, [
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
    projectFiles = watcher = null
    beforeEach ->
      resetHome()
      projectFiles = new ProjectFiles _path.join baseDir, homeDir
      projectFiles.watchTree =
        watchTree: (directory) ->
          watcher = new events.EventEmitter
          watcher.directory = directory
          return watcher

    makeFile = (fileName) ->
      filePath = _path.join baseDir, homeDir, fileName
      fs.writeFileSync filePath, 'touched'
      return filePath

    it "should notice when i add a file", (done) ->
      fileName = 'file.txt'
      filePath = makeFile fileName
      projectFiles.on messageAction.ADD_FILES, (data) ->
        file = data.files[0]
        assert.equal file.path, fileName
        assert.equal file.isDir, false
        done()
      projectFiles.watchFileTree()
      watcher.emit 'fileCreated', filePath

    it "should ignore cruft files", (done) ->
      fileName = 'file.txt~'
      filePath = makeFile fileName
      projectFiles.on messageAction.ADD_FILES, (data) ->
        assert.fail "Should not notice file."
      projectFiles.on 'stop', (data) ->
        done()
      projectFiles.watchFileTree()
      watcher.emit 'fileCreated', filePath
      process.nextTick ->
        projectFiles.emit 'stop'

    it "should notice when I add a directory"
      
    it "should notice when i delete a file"

    it "should notice when i change a file"

    it "should not notice images"

    it "should ignore the .git directory"

    it "should ignore the contents of the .gitignore or should it?"

    it "should ignore broken symlinks fweep", (done) ->
      fileName = 'DNE'
      filePath = _path.join baseDir, homeDir, fileName
      linkName = 'brokenLink'
      linkPath = _path.join baseDir, homeDir, linkName
      fs.symlinkSync filePath, linkPath
      projectFiles.on messageAction.ADD_FILES, (data) ->
        assert.fail "Should not notice file."
      projectFiles.on 'stop', (data) ->
        done()
      projectFiles.watchFileTree()
      watcher.emit 'fileCreated', linkPath
      process.nextTick ->
        projectFiles.emit 'stop'



