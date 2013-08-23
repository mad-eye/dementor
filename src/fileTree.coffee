_ = require 'underscore'
_path = require 'path'
uuid = require 'node-uuid'
{EventEmitter} = require 'events'
{standardizePath, localizePath} = require './projectFiles'

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
    @emit 'trace', "Added file #{file.path}"
    removed = removeItemFromArray file.path, @dirsPending
    @emit 'trace', "Removed #{file.path} from pending dirs." if removed

  addFiles: (files) ->
    return unless files
    @addFile file for file in files

  remove: (fileId) ->
    file = @filesById[fileId]
    delete @filesById[fileId]
    delete @filesByPath[file.path]
    @emit 'trace', "Removed file #{file.path}"
    removed = removeItemFromArray file.path, @dirsPending
    @emit 'trace', "Removed #{file.path} from pending dirs." if removed

  change: (fileId, fields={}, cleared=[]) ->
    file = @filesById[fileId]
    _.extend file, fields
    delete file[key] for key in cleared

  #Add missing parent dirs to files
  completeParentFiles: (files) ->
    newFileMap = {}
    newFileMap[file.path] = file for file in files

    for file in files
      #Need to localize path seps for _path.dirname to work
      path = localizePath file.path
      loop
        path = _path.dirname path
        break if path == '.' or path == '/' or !path?
        break if path of newFileMap
        continue if @filesByPath[path]
        unless path in @dirsPending
          newFileMap[path] = {path: path, isDir: true}
          @dirsPending.push standardizePath path
          @emit 'trace', "Adding #{path} to dirsPending."
        else
          @emit 'trace', "#{path} is in dirsPending, ignoring."

    return _.values(newFileMap)

#Helper functions

removeItemFromArray = (item, array) ->
  idx = array.indexOf item
  array.splice(idx,1) if idx != -1
  return idx != -1

module.exports = FileTree
