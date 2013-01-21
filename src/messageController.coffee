util = require "util"
events = require "events"
{messageAction, messageMaker} = require 'madeye-common'
{errors, errorType} = require 'madeye-common'

class MessageController
  constructor: (@socket) ->
    events.EventEmitter.call this
    @attach socket


  attach: (@socket) ->
    socket.on 'connect', =>
      @handshake @projectId

    socket.on 'reconnect', =>
      @handshake @projectId

    socket.on 'connect_failed', =>
      #TODO: Should use running callback
      console.error "Connection Failed"

    socket.on 'disconnect', =>
      #TODO: Should use running callback
      console.log "Socket disconnected"

    #callback: (err, body) =>, errors are encoded as {error:}
    socket.on messageAction.REQUEST_FILE, (fileId, callback) =>
      unless fileId then callback errors.new 'MISSING_PARAM'; return
      @emit messageAction.REQUEST_FILE, fileId, (err, contents) =>
        if err then console.warn "Found getFileContents error:", err
        if err then callback err; return
        callback null, contents

    #callback: (err, body) =>, errors are encoded as {error:}
    socket.on messageAction.SAVE_FILE, (fileId, contents, callback) =>
      unless data.fileId && contents
        callback errors.new 'MISSING_PARAM'; return
      @emit messageAction.SAVE_FILE, fileId, contents, callback
      @dementor.saveFileContents message.data.fileId, message.data.contents, (err) ->
        if err then console.warn "Found saveFileContents error:", err
        if err then callback err; return
        #Confirm success.
        replyMessage = messageMaker.replyMessage message
        callback null, replyMessage


  #message from ChannelConnection should be a JSON object
  route: (message, callback) ->
    #console.log "messageController received message:", message
    if message.error
      callback message.error
      return
    #TODO: Replace these with appropriate messageAction constants.
    switch message.action
      when messageAction.REQUEST_FILE then @requestLocalFile message, callback
      when messageAction.SAVE_FILE then @saveLocalFile message, callback
      when messageAction.REPLY then "Callback should have handled it"
      else callback? errors.new errorType.UNKNOWN_ACTION, {action: message.action}

  saveLocalFile: (message, callback) ->

  addLocalFiles: (message, callback) ->
    console.log "Adding local files:", message
    throw new Error "Unimplemented"

  removeLocalFiles: (message, callback) ->
    console.log "Removing local files:", message
    throw new Error "Unimplemented"

  changeLocalFiles: (message, callback) ->
    console.log "change local files:", message
    throw new Error "Unimplemented"

util.inherits MessageController, events.EventEmitter
exports.MessageController = MessageController
