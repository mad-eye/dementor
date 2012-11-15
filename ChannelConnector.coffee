{Settings} = require './Settings'
{BCSocket} = require 'browserchannel'
uuid = require 'node-uuid'

#WARNING: Must call @destroy when done to close the channel.
class ChannelConnection
  constructor: (@socket) ->
    console.log "ChannelConnection constructed with socket", socket
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
    @socket.onopen = ->
      @send {action:'openConnection'}
    @socket.onmessage = (message) ->
      console.log 'ChannelConnector got message', message
      @handleMessage message
  
  send: (data) ->
    data.uuid = uuid.v4()
    data.whenSent = new Date()
    @socket.send data
    @sentMsgs[data.uuid] = data


ChannelConnector =
  socket: null,

  connectionInstance: ->
    @socket ?= new BCSocket "http://#{@bcHost}:#{@bcPort}/channel", reconnect:true
    return new ChannelConnection(@socket)

exports.ChannelConnector = ChannelConnector

