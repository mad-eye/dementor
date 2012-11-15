wrench = require 'wrench'
assert = require 'assert'
fs = require 'fs'
path = require 'path'

#TODO make paths windows compatible
{Dementor} = require('../dementor.coffee')

describe "dementor", ->

  createProject = (name, fileTree) ->
    projectDir = path.join(".test_projects", name)
    unless fs.existsSync ".test_projects"
      fs.mkdirSync ".test_projects"
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
        fs.writeFileSync(path.join(root, key), value)
      else
        createFileTree(key, value)

  describe "constructor", ->
    it "should populate the config object if a .madeye file exists", ->
      projectPath = createProject("polyjuice", {".madeye": JSON.stringify({id: "ABC123"})})
      dementor = new Dementor projectPath
      assert.equal dementor.config().id, "ABC123"

    it "should return an empty config object if no .madeye file exists", ->
      projectPath = createProject("madeyeless")
      dementor = new Dementor projectPath
      #TODO, figure out how to compare objects by values
      assert.deepEqual dementor.config(), {}

    it "should not allow two dementors to monitor the same directory"

    it "should not allow a dementor to watch a subdir of an existing dementor's territory"

  describe "setId", ->
    it "should persist across multliple dementor instances"

  describe "watchFileTree", ->
    it "should notice when i change a file"

    it "should notice when i delete a file"

    it "should notice when i add a file"

    it "should not noice imgages"

    it "should ignore the .git directory"

    it "should ignore the contents of the .gitignore or should it?"

    it "should not choke on errors like Error: ENOENT, no such file or directory '/Users/mike/dementor/test/.#dementorTest.coffee'"

#  describe "readFileTree", ->
