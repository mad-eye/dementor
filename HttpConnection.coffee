{Settings} = require './Settings'
_ = require 'underscore'
request = require 'request'

#TODO use this? http://nodejs.org/api/querystring.html
makeQueryString = (params) ->
  return "" unless params? and _.size(params)
  str = ""
  for k, v of params
    str += "&" if str
    str += k
    str += "=#{v}" if v?
  return "?" + str


#callback: (body) ->; takes an obj (parsed from JSON) body
class HttpConnection
  constructor: ->
    @hostname = Settings.httpHost
    @port = Settings.httpPort

  targetUrl: (action) ->
    "http://#{@hostname}:#{@port}/#{action}"

  post: (options, callback) ->
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

  get: (options, params, callback) ->
    options.uri =  @targetUrl (options['action'] ? '')
    delete options['action']
    options.qs = makeQueryString params
    request.get options, (err, res, body) ->
      if err
        body = {error:err.message}
      else
        if res.statusCode != 200
          console.warn "Unexpected status code:" + res.statusCode
        body = JSON.parse(body)
      callback(body)

exports.HttpConnection = HttpConnection
