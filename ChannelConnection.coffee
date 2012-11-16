{Settings} = require './Settings'
{BCSocket} = require 'browserchannel'
uuid = require 'node-uuid'

#WARNING: Must call @destroy when done to close the channel.
class ChannelConnection
  constructor: (@socket) ->
    unless @socket
      @socket = new BCSocket "http://#{Settings.bcHost}:#{Settings.bcPort}/channel", reconnect:true
    console.log "ChannelConnection constructed with socket", @socket
    @sentMsgs = {}

  destroy: ->
    @socket.close() if @socket?
    @socket = null

  handleMessage: (messageTxt) ->
    try
      message = JSON.parse(messageTxt)
    catch error
      console.error "Error trying to parse message.\n\tError:", error, "\n\n\tMessage:", messageTxt
      return
    if message.action == 'acknowlege'
      delete @sentMsgs[message.receivedId]
    else
      if @onMessage
        @onMessage message
      else
        console.warn "No onMessage to handle message", message

  openBrowserChannel: ->
    @socket.onopen = =>
      @send {action:'openConnection'}
      console.log "opening connection"
    @socket.onmessage = (message) =>
      console.log 'ChannelConnector got message', message
      @handleMessage message
    @socket.onerror = (message) =>
      console.log "ChannelConnector got error" , message
    @socket.onclose = (message) =>
      console.log "closing time", message

  send: (data) ->
    data.uuid = uuid.v4()
    data.whenSent = new Date()
    @socket.send data
    @sentMsgs[data.uuid] = data

exports.ChannelConnection = ChannelConnection
