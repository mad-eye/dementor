_ = require 'underscore'
{standardizePath, localizePath, findParentPath} = require '../madeye-common/common'
Logger = require 'pince'
EventEmitter = require("events").EventEmitter

log = new Logger 'ddpFiles'
class DdpFiles extends EventEmitter
  constructor: ->
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
    parentPath ||= '.'
    @filePathsByParent[parentPath] ?= []
    @filePathsByParent[parentPath].push file.path
    log.trace "Added ddp file #{file.path}"
    
  removeDdpFile: (fileId) ->
    file = @filesById[fileId]
    return unless file
    delete @filesById[fileId]
    delete @filesByPath[file.path]
    log.trace "Removed ddp file #{file.path}"

  changeDdpFile: (fileId, fields={}, cleared=[]) ->
    file = @filesById[fileId]
    log.trace "Updating fields for #{file.path}:", fields if fields
    _.extend file, fields if fields
    log.trace "Clearing fields for #{file.path}:", cleared if cleared
    delete file[field] for field in cleared if cleared
    log.debug "Updated file", file.path

module.exports = DdpFiles
