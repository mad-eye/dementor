{AzkabanConnection} = require "../azkabanConnection"
{Dementor} = require "../dementor"
assert = require "assert"

#if azkaban isn't running don't proceed

describe "azkabanConnection", ->
  describe "enable", ->
    it "should create a browser channel", (done)->
      dementor = new Dementor
      connection = new AzkabanConnection("localhost", 4000, "localhost", 4321)
      connection.enable dementor, ->
        assert.equal connection.socket.readyState, 0
        connection.socket.close()
        done()
