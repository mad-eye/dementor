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

