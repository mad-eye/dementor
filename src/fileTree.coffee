_ = require 'underscore'
_path = require 'path'
uuid = require 'node-uuid'
{EventEmitter} = require 'events'
{normalizePath} = require '../madeye-common/common'

class FileTree extends EventEmitter
  constructor: ->
    @filesById = {}
    @filesByPath = {}
    @dirsPending = []

  getFiles: -> _.values @filesById

  findById: (id) -> @filesById[id]

  findByPath: (path) -> @filesByPath[path]

  addFile: (file) ->
    return unless file
    @filesById[file._id] = file
    @filesByPath[file.path] = file
    removeItemFromArray file.path, @dirsPending

  addFiles: (files) ->
    return unless files
    @addFile file for file in files

  remove: (fileId) ->
    file = @filesById[fileId]
    delete @filesById[fileId]
    delete @filesByPath[file.path]
    removeItemFromArray file.path, @dirsPending

  change: (fileId, fields={}, cleared=[]) ->
    file = @filesById[fileId]
    _.extend file, fields
    delete file[key] for key in cleared

  completeFiles: (files) ->
    @emit 'error', "No projectId specified in fileTree" unless @projectId
    files = @completeParentFiles files
    for file in files
      if file.path of @filesByPath
        @emit 'debug', "Added file already known: #{file.path}"
        continue
      file.projectId = @projectId
      file.orderingPath = normalizePath file.path
      file._id = uuid.v4()
    return files

  #Add missing parent dirs to files
  completeParentFiles: (files) ->
    newFileMap = {}
    newFileMap[file.path] = file for file in files

    for file in files
      path = file.path
      loop
        #FIXME: This won't work on windows, since _path separates by \ there.
        path = _path.dirname path
        break if path == '.' or path == '/' or !path?
        break if path of newFileMap
        continue if @filesByPath[path]
        unless path in @dirsPending
          newFileMap[path] = {path: path, isDir: true}
          @dirsPending.push path

    return _.values(newFileMap)

#Helper functions

removeItemFromArray = (item, array) ->
  idx = array.indexOf item
  array.splice(idx,1) if idx != -1

module.exports = FileTree
