{EventEmitter} = require 'events'
_ = require 'underscore'

class MockDdpClient extends EventEmitter
  constructor: (services) ->
    _.extend this, services

module.exports = MockDdpClient
