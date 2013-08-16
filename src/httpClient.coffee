_ = require 'underscore'
request = require 'request'
querystring = require 'querystring'
{errors, errorType} = require '../madeye-common/common'

wrapError = (err) ->
  return err if err.madeye
  errors.new errorType.NETWORK_ERROR, cause:err

#callback: (body) ->; takes an obj (parsed from JSON) body
#errors are passed as an {error:} object
class HttpClient
  constructor: (@url) ->

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
    request options, (err, res, body) ->
      if err
        err = wrapError err
        body = {error:err}
      else
        #if res.statusCode != 200
          #console.warn "Unexpected status code:" + res.statusCode
        body = JSON.parse(body) if typeof body == 'string'
      callback(body)

exports.HttpClient = HttpClient
