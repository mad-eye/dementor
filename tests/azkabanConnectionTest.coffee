uuid = require 'node-uuid'
assert = require "assert"
wrench = require 'wrench'
fs = require 'fs'
_path = require "path"
{AzkabanConnection} = require "../azkabanConnection"
{Dementor} = require "../dementor"
{MockSocket} = require "madeye-common"
{MockProjectFiles} = require "./mock/MockProjectFiles"
{SocketClient} = require "madeye-common"
{FileTree} = require "madeye-common"
{messageMaker, messageAction} = require 'madeye-common'
{HttpConnection} = require "../HttpConnection"


#TODO: Replace this with new code in madeye-common
homeDir = _path.join ".test_area", "fake_home"
process.env["MADEYE_HOME"] = homeDir

mkDir = (dir) ->
  unless fs.existsSync dir
    wrench.mkdirSyncRecursive dir

createProject = (name, fileMap) ->
  mkDir ".test_area"
  projectDir = _path.join(".test_area", name)
  if fs.existsSync projectDir
    wrench.rmdirSyncRecursive(projectDir)
  fs.mkdirSync projectDir
  fileMap = defaultFileMap unless fileMap
  createFileTree(projectDir, fileMap)
  return projectDir

defaultFileMap =
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
      createFileTree(_path.join(root, key), value)

constructFileTree = (fileMap, root, fileTree) ->
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


describe "AzkabanConnection", ->
  socket = dementor = connection = mockProjFiles = null
  sentMessages = null
  before ->
    socket = new MockSocket(
      onsend: (message) ->
        sentMessages.push message
    )
    #FIXME: There's got to be a better way to handle this web of ivars.
    mockProjFiles = new MockProjectFiles
    mockProjFiles.importFileMap defaultFileMap
    dementor = new Dementor
    dementor.projectId = uuid.v4()
    dementor.directoryJanitor = mockProjFiles
    socketClient = new SocketClient(socket)
    connection = new AzkabanConnection(new HttpConnection(), socketClient)
    socketClient.controller.dementor = dementor
    socket.completeConnection()

  describe "enable", ->
    before (done) ->
      sentMessages = []
      connection.enable dementor, (err) ->
        if err
          console.log "Found error enabling dementor", err
          return
        done()
      
    it "should send a 'handshake' message", ->
      assert.equal sentMessages.length, 1
    it "should set a 'handshake' message action", ->
      assert.equal sentMessages[0].action, messageAction.HANDSHAKE
    it "should have set projectId on handshake message", ->
      assert.equal sentMessages[0].projectId, dementor.projectId

  describe "receiving REQUEST_FILE messages:", ->
    messageId = null
    fileId = null
    fileBody =  "this is a moderate file"
    before ->
      fileTree = constructFileTree defaultFileMap
      dementor.fileTree = fileTree
      fileId = fileTree.findByPath("dir2/moderateFile")._id
      mockProjFiles.importFileMap defaultFileMap

      mockProjFiles.files[fileId] = fileBody
      sentMessages = []
      rfMessage = messageMaker.requestFileMessage fileId
      messageId = rfMessage.id
      socket.receive rfMessage
    it "should send a replyMessage", ->
      assert.equal sentMessages.length, 1
    it "should send a 'reply' message action", ->
      console.log "Reply message:", sentMessages[0]
      assert.equal sentMessages[0].action, messageAction.REPLY
    it "should have set projectId on message", ->
      assert.equal sentMessages[0].projectId, dementor.projectId
    it "should have set replyTo to message.id", ->
      assert.equal sentMessages[0].replyTo, messageId
    it "should return fileId and body in message.data", ->
      assert.equal sentMessages[0].data.fileId, fileId
      assert.equal sentMessages[0].data.body, fileBody

