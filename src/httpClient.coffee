_ = require 'underscore'
request = require 'request'
querystring = require 'querystring'
{errors, errorType} = require '../madeye-common/common'
events = require 'events'

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
    options.rejectUnauthorized = false
    @request options, params, callback

  put: (options, params, callback) ->
    options.method = 'PUT'
    options.rejectUnauthorized = false
    @request options, params, callback

  get: (options, params, callback) ->
    options.method = 'GET'
    options.rejectUnauthorized = false
    @request options, params, callback

  #callback : (body) ->
  #errors are encoded as body={error:}
  request: (options, params, callback) ->
    if typeof params == 'function'
      callback = params
      params = {}
    options.uri =  @targetUrl (options['action'] ? '')
    options.qs = querystring.stringify params if options.method == 'GET'
    delete options['action']
    @emit 'trace', "#{options.method} #{options.uri}"
    request options, (err, res, body) ->
      if err
        @emit 'debug', "#{options.method} #{options.uri} returned error"
        err = wrapError err
        body = {error:err}
      else
        @emit 'trace', "#{options.method} #{options.uri} returned #{res.statusCode}"
        body = JSON.parse(body) if typeof body == 'string'
      callback(body)

exports.HttpClient = HttpClient
