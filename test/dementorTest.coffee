wrench = require 'wrench'
assert = require 'assert'
fs = require 'fs'
_path = require 'path'

{Dementor} = require('../dementor.coffee')

describe "dementor", ->
  homeDir = _path.join ".test_area", "fake_home"
  process.env["MADEYE_HOME"] = homeDir

  mkDir = (dir) ->
    unless fs.existsSync dir
      wrench.mkdirSyncRecursive dir

  createProject = (name, fileTree) ->
    mkDir ".test_area"
    projectDir = _path.join(".test_area", name)
    if fs.existsSync projectDir
      wrench.rmdirSyncRecursive(projectDir)
    fs.mkdirSync projectDir
    fileTree = defaultFileTree unless fileTree
    createFileTree(projectDir, fileTree)
    return projectDir

  defaultFileTree = ->
    rootFile: "this is the rootfile"
    dir1: {}
    dir2:
      moderateFile: "this is a moderate file"
      dir3:
        leafFile: "this is a leaf file"

  createFileTree = (root, filetree) ->
    unless fs.existsSync root
      fs.mkdirSync root
    for key, value of filetree
      if typeof value == "string"
        fs.writeFileSync(_path.join(root, key), value)
      else
        createFileTree(key, value)

  describe "constructor", ->
    beforeEach ->
      if fs.existsSync homeDir
        wrench.rmdirSyncRecursive homeDir
      mkDir homeDir

    it "populates the project id if a record exists in .madeye_projects", ->
      projectsDb = {}
      projectsDb[_path.join(".test_area", "polyjuice")] = "ABC123"
      projectsDbPath = _path.join homeDir, ".madeye_projects"
      fs.writeFileSync(projectsDbPath, JSON.stringify projectsDb)

      projectPath = createProject "polyjuice"
      dementor = new Dementor projectPath
      assert.equal dementor.project_id, "ABC123"

    it "returns an undefined projecId when .madeye_projects does not exist", ->
      projectPath = createProject("madeyeless")
      dementor = new Dementor projectPath
      assert !dementor.projectId

    it "should not allow two dementors to monitor the same directory"

    it "should not allow a dementor to watch a subdir of an existing dementors territory"

  describe "registerProject", ->
    it "should persist projectIdacross multliple dementor instances", ->

  describe "watchFileTree", ->
    it "should notice when i change a file"

    it "should notice when i delete a file"

    it "should notice when i add a file"

    it "should not noice imgages"

    it "should ignore the .git directory"

    it "should ignore the contents of the .gitignore or should it?"

    it "should not choke on errors like Error: ENOENT, no such file or directory '/Users/mike/dementor/test/.#dementorTest.coffee'"

  describe "readFileTree", ->
