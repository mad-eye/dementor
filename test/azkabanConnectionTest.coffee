{AzkabanConnection} = require "../azkabanConnection"
{Dementor} = require "../dementor"
{MockSocket} = require "madeye-common"
{SocketClient} = require "madeye-common"
{HttpConnection} = require "../HttpConnection"
uuid = require 'node-uuid'

assert = require "assert"

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
      connection = new AzkabanConnection(new HttpConnection, new SocketClient(socket))
      connection.enable dementor
      socket.completeConnection()

    it "should create a browser channel", ->
      assert.equal sentMessages.length, 1

    it "should send a 'handshake' message", ->
      assert.equal sentMessages[0].action, 'handshake'
      assert.equal sentMessages[0].projectId, dementor.projectId
