{AzkabanConnection} = require "../azkabanConnection"
{Dementor} = require "../dementor"
{MockSocket} = require "madeye-common"
{SocketClient} = require "madeye-common"
{messageMaker, messageAction} = require 'madeye-common'
{HttpConnection} = require "../HttpConnection"
uuid = require 'node-uuid'

assert = require "assert"
{messageMaker, messageAction} = require 'madeye-common'
uuid = require 'node-uuid'
#if azkaban isn't running don't proceed

describe "AzkabanConnection", ->
  socket = dementor = connection = null
  sentMessages = null
  before ->
    socket = new MockSocket(
      onsend: (message) ->
        sentMessages.push message
    )
    dementor = new Dementor
    dementor.projectId = uuid.v4()
    socketClient = new SocketClient(socket)
    connection = new AzkabanConnection(new HttpConnection(), socketClient)
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
    fileId = uuid.v4()
    before ->
      sentMessages = []
      rfMessage = messageMaker.requestFileMessage fileId
      messageId = rfMessage.id
      socket.receive rfMessage
    it "should send a replyMessage", ->
      assert.equal sentMessages.length, 1
    it "should set a 'reply' message action", ->
      assert.equal sentMessages[0].action, messageAction.REPLY
    it "should have set projectId on message", ->
      assert.equal sentMessages[0].projectId, dementor.projectId
    it "should have set replyTo to message.id", ->
      assert.equal sentMessages[0].replyTo, messageId
    it "should return fileId and body in message.data", ->
      assert.equal sentMessages[0].data.fileId, fileId
      assert.ok sentMessages[0].data.body

