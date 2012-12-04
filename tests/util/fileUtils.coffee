wrench = require 'wrench'
fs = require 'fs'
_path = require 'path'

#TODO: Move this to madeye-common

TEST_AREA = ".test_area"
fileUtils =
  mkDir : (dir) ->
    unless fs.existsSync dir
      wrench.mkdirSyncRecursive dir

  mkDirClean : (dir) ->
    if fs.existsSync dir
      wrench.rmdirSyncRecursive(dir)
    fs.mkdirSync dir


  testProjectDir: (projName) ->
    return _path.join(TEST_AREA, projName)

  homeDir : _path.join TEST_AREA, "fake_home"

  createProject : (name, fileMap) ->
    projectDir = @testProjectDir name
    if fs.existsSync projectDir
      wrench.rmdirSyncRecursive(projectDir)
    fs.mkdirSync projectDir
    fileMap ?= @defaultFileMap
    @createFileTree(projectDir, fileMap)
    return projectDir

  createFileTree : (root, filetree) ->
    unless fs.existsSync root
      fs.mkdirSync root
    for key, value of filetree
      if typeof value == "string"
        fs.writeFileSync(_path.join(root, key), value)
      else
        @createFileTree(_path.join(root, key), value)

  defaultFileMap :
    rootFile: "this is the rootfile"
    dir1: {}
    dir2:
      moderateFile: "this is a moderate file"
      dir3:
        leafFile: "this is a leaf file"

  writeFiles : (root, fileMap) ->
    unless fs.existsSync root
      fs.mkdirSync root
    for key, value of fileMap
      if typeof value == "string"
        fs.writeFileSync(_path.join(root, key), value)
      else
        @writeFiles(_path.join(root, key), value)

  constructFileTree : (fileMap, root, fileTree) ->
    fileTree ?= new FileTree(null, root)
    makeRawFile = (path, value) ->
      console.log "Making raw file with path #{path} and value #{value}"
      rawFile = {
        _id : uuid.v4()
        path : path
        isDir : (typeof value != "string")
      }
      console.log "Made rawfile:", rawFile
      return rawFile
    for key, value of fileMap
      fileTree.addFile makeRawFile _path.join(root, key), value
      unless typeof value == "string"
        constructFileTree(value, _path.join(root, key), fileTree)
    console.log "Contructed fileTree:", fileTree unless root?
    return fileTree

  clone : (obj) ->
    JSON.parse JSON.stringify obj

exports.fileUtils = fileUtils
