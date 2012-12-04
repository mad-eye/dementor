_path = require "path"

class MockProjectFiles
  constructor: (@directory) ->
    @files = {} #Map path -> body, (body true for dirs)
  
  importFileMap: (fileMap, root) ->
    for key, value of fileMap
      if typeof value == "string"
        @files[_path.join(root, key)] = value
      else
        @files[_path.join(root, key)] = true
        @importFileMap(value, _path.join(root, key))
    console.log "Imported fileMap.  Files:", @files unless root?

  #Callback = (err, body) -> ...
  readFile: (filePath, absolute=false, callback) ->
    if typeof absolute == 'function'
      callback = absolute
      absolute = false
    filePath = _path.join @directory, filePath unless absolute
    unless @files[filePath]? then callback new Error "No file found"
    if @files[filePath] == true then callback new Error "File is directory, no body found."
    callback null, @files[filePath]



  #Callback = (err) -> ...
  writeFile: (filePath, contents, absolute=false, callback) ->
    if typeof absolute == 'function'
      callback = absolute
      absolute = false
    filePath = _path.join @directory, filePath unless absolute
    throw new Error "Not yet implemented"

  exists: (filePath, absolute=false) ->
    if typeof absolute == 'function'
      callback = absolute
      absolute = false
    filePath = _path.join @directory, filePath unless absolute
    throw new Error "Not yet implemented"

  #callback = (err, event) ->
  watchFileTree: (callback) ->
    throw new Error "Not yet implemented"

  readFileTree: (callback) ->
    throw new Error "Not yet implemented"

exports.MockProjectFiles = MockProjectFiles
