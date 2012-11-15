{AzkabanConnection} = require "../azkabanConnection"
{Dementor} = require "../dementor"
{MockSocket} = require "./mock/MockSocket"
{ChannelConnector} = require "../ChannelConnector"

assert = require "assert"

#if azkaban isn't running don't proceed

describe "azkabanConnection", ->
  socket = dementor = connection = null
  describe "enable", ->
    before ->
      socket = new MockSocket(
        onsend: (message) ->
          @sentMessages ?= []
          @sentMessages.push message
      )
      ChannelConnector.socket = socket
      dementor = new Dementor
      #FIXME: Need to make an HttpConnection and pass it.
      connection = new AzkabanConnection(null, ChannelConnector.connectionInstance())

    it "should create a browser channel", ->
      connection.enable dementor
      #assert.equal connection.socket.readyState, 0
      #connection.socket.close()
