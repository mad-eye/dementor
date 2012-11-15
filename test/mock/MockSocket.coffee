_ = require 'underscore'

#Initialize with callbacks 'onopen', 'onmessage', etc
#also have 'onsend', which is called on send.
class MockSocket
  constructor: (callbacks) ->
    _.extend(this, callbacks)

  send: (message) ->
    @onsend message if @onsend?

  receive: (message) ->
    @onmessage message if @onmessage?

  close: ->
    @closed = true

exports.MockSocket = MockSocket
