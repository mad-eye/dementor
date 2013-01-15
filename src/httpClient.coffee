{Settings} = require 'madeye-common'
_ = require 'underscore'
request = require 'request'
querystring = require 'querystring'

#TODO: Wrap http errors in MadEye errors

#callback: (body) ->; takes an obj (parsed from JSON) body
#errors are passed as an {error:} object
class HttpClient
  constructor: (@host) ->

  targetUrl: (action) ->
    "http://#{@host}/#{action}"

  post: (options, params, callback) ->
    options.method = 'POST'
    @request options, params, callback

  put: (options, params, callback) ->
    options.method = 'PUT'
    @request options, params, callback

  get: (options, params, callback) ->
    options.method = 'GET'
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
        body = {error:err.message}
      else
        if res.statusCode != 200
          console.warn "Unexpected status code:" + res.statusCode
        body = JSON.parse(body) if typeof body == 'string'
      callback(body)

exports.HttpClient = HttpClient
