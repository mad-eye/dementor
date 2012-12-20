
class MockHttpClient
  #router is a (options, params) ->; it provides the server response body
  constructor: (@router) ->

  #callback : (body) ->
  #errors are encoded as body={error:}
  get: (options, params, callback) =>
    if typeof params == 'function'
      callback = params
      params = {}
    options.method = 'GET'
    result = @router options, params
    callback result

  #callback : (body) ->
  #errors are encoded as body={error:}
  post: (options, params, callback) =>
    if typeof params == 'function'
      callback = params
      params = {}
    options.method = 'POST'
    result = @router options, params
    callback result

  #callback : (body) ->
  #errors are encoded as body={error:}
  put: (options, params, callback) =>
    if typeof params == 'function'
      callback = params
      params = {}
    options.method = 'PUT'
    result = @router options, params
    callback result


exports.MockHttpClient = MockHttpClient
