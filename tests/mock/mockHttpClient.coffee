
class MockHttpClient
  #router is a (options, params) ->; it provides the server response body
  constructor: (@router) ->

  #callback : (body) ->
  #errors are encoded as body={error:}
  get: (options, params, callback) =>
    options.method = 'GET'
    @request options, params, callback

  #callback : (body) ->
  #errors are encoded as body={error:}
  post: (options, params, callback) =>
    options.method = 'POST'
    @request options, params, callback

  #callback : (body) ->
  #errors are encoded as body={error:}
  put: (options, params, callback) =>
    options.method = 'PUT'
    @request options, params, callback

  request: (options, params, callback) =>
    if typeof params == 'function'
      callback = params
      params = {}
    @router options, params, callback


exports.MockHttpClient = MockHttpClient
