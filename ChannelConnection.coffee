{Settings} = require './Settings'
{BCSocket} = require 'browserchannel'
uuid = require 'node-uuid'

#WARNING: Must call @destroy when done to close the channel.
class ChannelConnection
  constructor: (@socket) ->
    unless @socket
      @socket = new BCSocket "http://#{Settings.bcHost}:#{Settings.bcPort}/channel", reconnect:true
    @sentMsgs = {}

  destroy: ->
    @socket.close() if @socket?
    @socket = null

  handleMessage: (message) ->
    if message.action == 'confirm'
      delete @sentMsgs[message.receivedId]
    else
      if @onMessage
        @onMessage message
      else
        console.warn "No onMessage to handle message", message

  openBrowserChannel: (@projectId) ->
    @socket.onopen = =>
      @send {action:'handshake'}
      console.log "opening connection"
    @socket.onmessage = (message) =>
      console.log 'ChannelConnector got message', message
      @handleMessage message
    @socket.onerror = (message) =>
      console.log "ChannelConnector got error" , message
    @socket.onclose = (message) =>
      console.log "closing time", message

  send: (message) ->
    message.uuid = uuid.v4()
    message.timestamp = new Date().getTime()
    message.projectId = @projectId
    @socket.send message
    @sentMsgs[message.uuid] = message



exports.ChannelConnection = ChannelConnection
