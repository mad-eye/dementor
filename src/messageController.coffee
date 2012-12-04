{messageAction, messageMaker} = require 'madeye-common'

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
      when 'change' then @changeLocalFiles message, callback
      when 'add' then @addLocalFiles message, callback
      when 'remove' then @removeLocalFiles message, callback
      when messageAction.REPLY then "Callback should have handled it"
      else callback? new Error("Unknown action: " + message.action)

  requestLocalFile: (message, callback) ->
    console.log "Request local file:", message
    unless message.fileId then callback new Error "Message does not contain fileId"; return
    @dementor.getFileContents message.fileId, (err, body) ->
      if err then callback err; return
      replyMessage = messageMaker.replyMessage message,
        fileId: message.fileId
        body: body
      callback null, replyMessage

  addLocalFiles: (message, callback) ->
    console.log "Adding local files:", message
    thow new Error "Unimplemented"

  removeLocalFiles: (message, callback) ->
    console.log "Removing local files:", message
    thow new Error "Unimplemented"

  changeLocalFiles: (message, callback) ->
    console.log "change local files:", message
    thow new Error "Unimplemented"

exports.MessageController = MessageController
