_ = require 'underscore'

#Initialize with callbacks 'onopen', 'onmessage', etc
#also have 'onsend', which is called on send.
class MockSocket
  constructor: (callbacks) ->
    @readyState = 0
    _.extend(this, callbacks)

  completeConnection: ->
    @readyState = 1
    @onopen() if @onopen?

  send: (message) ->
    @onsend message if @onsend?

  receive: (message) ->
    @onmessage message if @onmessage?

  close: ->
    @closed = true

exports.MockSocket = MockSocket
