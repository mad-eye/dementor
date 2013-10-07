_ = require 'underscore'
{standardizePath, localizePath, findParentPath} = require '../madeye-common/common'
{Logger} = require '../madeye-common/common'
EventEmitter = require("events").EventEmitter

class DdpFiles extends EventEmitter
  constructor: ->
    Logger.listen @, 'ddpFiles'
    @filesById = {}
    @filesByPath = {}
    #null is ok key; refers to root dir
    @filePathsByParent = {}

  getFiles: -> _.values @filesById

  findById: (id) -> @filesById[id]

  findByPath: (path) -> @filesByPath[path]

  #Add a file that comes via ddp
  addDdpFile: (file) ->
    return unless file
    @filesById[file._id] = file
    @filesByPath[file.path] = file
    parentPath = findParentPath file.path
    @filePathsByParent[parentPath] ?= []
    @filePathsByParent[parentPath].push file.path
    @emit "trace", "Added ddp file #{file.path}"
    
  removeDdpFile: (fileId) ->
    file = @filesById[fileId]
    return unless file
    delete @filesById[fileId]
    delete @filesByPath[file.path]
    @emit "trace", "Removed ddp file #{file.path}"

  changeDdpFile: (fileId, fields={}, cleared=[]) ->
    file = @filesById[fileId]
    @emit "trace", "Updating fields for #{file.path}:", fields if fields
    _.extend file, fields if fields
    @emit "trace", "Clearing fields for #{file.path}:", cleared if cleared
    delete file[field] for field in cleared if cleared
    @emit "debug", "Updated file", file.path

module.exports = DdpFiles
