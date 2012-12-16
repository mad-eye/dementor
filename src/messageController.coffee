{messageAction, messageMaker} = require 'madeye-common'
{errors, errorType} = require 'madeye-common'

class MessageController
  constructor: (@dementor) ->

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

  requestLocalFile: (message, callback) ->
    unless message.fileId then callback errors.new 'MISSING_PARAM'; return
    @dementor.getFileContents message.fileId, (err, body) ->
      if err then console.warn "Found getFileContents error:", err
      if err then callback err; return
      replyMessage = messageMaker.replyMessage message,
        fileId: message.fileId
        body: body
      callback null, replyMessage

  saveLocalFile: (message, callback) ->
    unless message.data.fileId || message.data.contents
      callback errors.new 'MISSING_PARAM'; return
    @dementor.saveFileContents message.data.fileId, message.data.contents, (err) ->
      if err then console.warn "Found saveFileContents error:", err
      if err then callback err; return
      #Confirm success.
      replyMessage = messageMaker.replyMessage message
      callback null, replyMessage

  addLocalFiles: (message, callback) ->
    console.log "Adding local files:", message
    throw new Error "Unimplemented"

  removeLocalFiles: (message, callback) ->
    console.log "Removing local files:", message
    throw new Error "Unimplemented"

  changeLocalFiles: (message, callback) ->
    console.log "change local files:", message
    throw new Error "Unimplemented"

exports.MessageController = MessageController
