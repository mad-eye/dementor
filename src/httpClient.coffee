{Settings} = require 'madeye-common'
_ = require 'underscore'
request = require 'request'
querystring = require 'querystring'


#callback: (body) ->; takes an obj (parsed from JSON) body
#errors are passed as an {error:} object
class HttpClient
  constructor: (@host) ->

  targetUrl: (action) ->
    "http://#{@host}/#{action}"

  #callback : (body) ->
  #errors are encoded as body={error:}
  post: (options, params, callback) ->
    if typeof params == 'function'
      callback = params
      params = {}
    options.uri =  @targetUrl (options['action'] ? '')
    delete options['action']
    request.post options, (err, res, body) ->
      if err
        body = {error:err.message}
      else
        if res.statusCode != 200
          console.warn "Unexpected status code:" + res.statusCode
        body = JSON.parse(body)
      callback(body)

  #callback : (body) ->
  #errors are encoded as body={error:}
  get: (options, params, callback) ->
    if typeof params == 'function'
      callback = params
      params = {}
    options.uri =  @targetUrl (options['action'] ? '')
    delete options['action']
    options.qs = querystring.stringify params
    request.get options, (err, res, body) ->
      if err
        body = {error:err.message}
      else
        if res.statusCode != 200
          console.warn "Unexpected status code:" + res.statusCode
        body = JSON.parse(body)
      callback(body)

exports.HttpClient = HttpClient
