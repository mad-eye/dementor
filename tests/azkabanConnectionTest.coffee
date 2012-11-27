{AzkabanConnection} = require "../azkabanConnection"
{Dementor} = require "../dementor"
{MockSocket} = require "madeye-common"
{SocketClient} = require "madeye-common"
{messageAction} = require 'madeye-common'
{HttpConnection} = require "../HttpConnection"
uuid = require 'node-uuid'

assert = require "assert"
{messageMaker, messageAction} = require 'madeye-common'
uuid = require 'node-uuid'
#if azkaban isn't running don't proceed

describe "azkabanConnection", ->
  socket = dementor = connection = null
  sentMessages = []
  describe "enable", ->
    before ->
      socket = new MockSocket(
        onsend: (message) ->
          sentMessages.push message
      )
      dementor = new Dementor
      dementor.projectId = uuid.v4()
      socketClient = new SocketClient()
      connection = new AzkabanConnection(new HttpConnection, new SocketClient(socket))
      connection.enable dementor
      socket.completeConnection()

    it "should create a browser channel"
      #assert.equal sentMessages.length, 1

    it "should send a 'handshake' message"
      #assert.equal sentMessages[0].action, messageAction.HANDSHAKE
      #assert.equal sentMessages[0].projectId, dementor.projectId

    it "shoud respond to a REQUEST_FILE message", ->
      fileId = uuid.v4()
      rfMessage = messageMaker.requestFileMessage fileId
      socket.receive rfMessage
      #XXX: find a way to listen to a reponse/callback.
