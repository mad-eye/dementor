{AzkabanConnection} = require "../azkabanConnection"
{Dementor} = require "../dementor"
{MockSocket} = require "./mock/MockSocket"
{ChannelConnector} = require "../ChannelConnector"
{HttpConnection} = require "../HttpConnection"

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
      ChannelConnector.socket = socket
      dementor = new Dementor
      connection = new AzkabanConnection(new HttpConnection, ChannelConnector.connection())
      connection.enable dementor
      socket.completeConnection()

    it "should create a browser channel", ->
      assert.equal sentMessages.length, 1

    it "should sent an 'openConnection' message", ->
      assert.equal sentMessages[0].action, 'openConnection'
