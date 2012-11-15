{AzkabanConnection} = require "../azkabanConnection"
{Dementor} = require "../dementor"
{MockSocket} = require "./mock/MockSocket"
{ChannelConnector} = require "../ChannelConnector"

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
      #FIXME: Need to make an HttpConnection and pass it.
      connection = new AzkabanConnection(null, ChannelConnector.connectionInstance())

    it "should create a browser channel", ->
      connection.enable dementor
      socket.completeConnection()
      assert.equal sentMessages.length, 1
      assert.equal sentMessages[0].action, 'openConnection'
