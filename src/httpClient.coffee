_ = require 'underscore'
request = require 'request'
querystring = require 'querystring'
{errors, errorType} = require '../madeye-common/common'
events = require 'events'

require('https').globalAgent.options.rejectUnauthorized = false

wrapError = (err) ->
  return err if err.madeye
  errors.new errorType.NETWORK_ERROR, cause:err

#callback: (body) ->; takes an obj (parsed from JSON) body
#errors are passed as an {error:} object
class HttpClient extends events.EventEmitter
  constructor: (@url) ->
    @emit 'debug', "Constructed with url #{@url}"

  targetUrl: (action) ->
    "#{@url}/#{action}"

  post: (options, params, callback) ->
    options.method = 'POST'
    @request options, params, callback

  put: (options, params, callback) ->
    options.method = 'PUT'
    @request options, params, callback

  get: (options, params, callback) ->
    options.method = 'GET'
    @request options, params, callback

  #callback : (err, body) ->
  request: (options, params, callback) ->
#    options.rejectUnauthorized = false
    if typeof params == 'function'
      callback = params
      params = {}
    options.uri =  @targetUrl (options['action'] ? '')
    options.qs = querystring.stringify params if options.method == 'GET'
    delete options['action']
    @emit 'debug', "#{options.method} #{options.uri}"
    @emit 'trace', options
    request options, (err, res, body) ->
      if err
        @emit 'debug', "#{options.method} #{options.uri} returned error"
        return callback wrapError err
      else
        @emit 'trace', "#{options.method} #{options.uri} returned #{res.statusCode}"
        body = JSON.parse(body) if typeof body == 'string'
        if body.error
          @emit 'debug', "#{options.method} #{options.uri} returned error in body:", body.error
          return callback body.error
        else
          callback null, body

exports.HttpClient = HttpClient
