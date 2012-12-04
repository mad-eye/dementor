
class MockHttpClient
  #router is a (action, params) ->; it provides the server response body
  constructor: (@router) ->

  #callback : (body) ->
  #errors are encoded as body={error:}
  get: (options, params, callback) =>
    if typeof params == 'function'
      callback = params
      params = {}
    action = options['action']
    result = @router action, params
    callback result

  #callback : (body) ->
  #errors are encoded as body={error:}
  post: (options, params, callback) =>
    if typeof params == 'function'
      callback = params
      params = {}
    action = options['action']
    result = @router action, params
    callback result

exports.MockHttpClient = MockHttpClient
