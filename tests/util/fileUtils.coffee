wrench = require 'wrench'
fs = require 'fs'
_path = require 'path'
uuid = require 'node-uuid'
FileTree = require '../../src/fileTree'

TEST_AREA = ".test_area"
class FileUtils
  @mkDir : (dir) ->
    unless fs.existsSync dir
      wrench.mkdirSyncRecursive dir

  @mkDirClean : (dir) ->
    if fs.existsSync dir
      wrench.rmdirSyncRecursive(dir)
    wrench.mkdirSyncRecursive dir

  @testProjectDir: (projName) ->
    return _path.join(TEST_AREA, projName)

  @homeDir : _path.join TEST_AREA, "fake_home"

  @createProject : (name, fileMap) ->
    projectDir = @testProjectDir name
    @mkDirClean projectDir
    fileMap ?= @defaultFileMap
    @createFileTree(projectDir, fileMap)
    return projectDir

  @createFileTree : (root, filetree) ->
    unless fs.existsSync root
      wrench.mkdirSyncRecursive root
    for key, value of filetree
      if typeof value == "string"
        filepath = _path.join(root, key)
        wrench.mkdirSyncRecursive _path.dirname filepath
        fs.writeFileSync(filepath, value)
      else
        @createFileTree(_path.join(root, key), value)

  @defaultFileMap :
    rootFile: "this is the rootfile"
    dir1: {}
    dir2:
      moderateFile: "this is a moderate file"
      dir3:
        leafFile: "this is a leaf file"

  @writeFiles : (root, fileMap) ->
    unless fs.existsSync root
      fs.mkdirSync root
    for key, value of fileMap
      if typeof value == "string"
        fs.writeFileSync(_path.join(root, key), value)
      else
        @writeFiles(_path.join(root, key), value)

  @constructFileTree : (fileMap, root, fileTree) ->
    fileTree ?= new FileTree(null, null)
    makeRawFile = (path, value) ->
      rawFile = {
        _id : uuid.v4()
        path : path
        isDir : (typeof value != "string")
      }
      return rawFile
    for key, value of fileMap
      fileTree.addDdpFile makeRawFile _path.join(root, key), value
      unless typeof value == "string"
        @constructFileTree(value, _path.join(root, key), fileTree)
    return fileTree

  @clone : (obj) ->
    JSON.parse JSON.stringify obj

  @initTestArea: () ->
    @mkDirClean TEST_AREA

  @destroyTestArea: () ->
    if fs.existsSync TEST_AREA
      wrench.rmdirSyncRecursive TEST_AREA


exports.fileUtils = FileUtils
