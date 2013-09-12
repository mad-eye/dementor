_ = require 'underscore'
_path = require 'path'
uuid = require 'node-uuid'
{EventEmitter} = require 'events'
{standardizePath, localizePath} = require './projectFiles'

class FileTree extends EventEmitter
  constructor: (@ddpClient) ->
    @filesById = {}
    @filesByPath = {}
    @dirsPending = []
    @setupDdpClient()

  getFiles: -> _.values @filesById

  findById: (id) -> @filesById[id]

  findByPath: (path) -> @filesByPath[path]

  addDdpFile: (file) ->
    return unless file
    @filesById[file._id] = file if file._id
    @filesByPath[file.path] = file
    @emit 'trace', "Added ddp file #{file.path}"
    #removed = removeItemFromArray file.path, @dirsPending
    #@emit 'trace', "Removed #{file.path} from pending dirs." if removed

  addFsFile: (file) ->
    @emit 'trace', "Adding fs file:", file
    return unless file
    existingFile = @filesByPath[file.path]
    if existingFile
      @updateFile existingFile, file
    else
      @ddpClient.addFile file
    #removed = removeItemFromArray file.path, @dirsPending
    #@emit 'trace', "Removed #{file.path} from pending dirs." if removed

  updateFile: (existingFile, newFile) ->
    @emit 'trace', "Updating file #{newFile.path}"
    #right now do nothing
    return

  addInitialFiles: (files) ->
    return unless files
    for file in files
      @addFsFile file
    #TODO: Remove ddp files that aren't in initial files

  #addFiles: (files) ->
    #return unless files
    #@addFile file for file in files

  remove: (fileId) ->
    file = @filesById[fileId]
    delete @filesById[fileId]
    delete @filesByPath[file.path]
    @emit 'trace', "Removed file #{file.path}"
    #removed = removeItemFromArray file.path, @dirsPending
    #@emit 'trace', "Removed #{file.path} from pending dirs." if removed

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

  setupDdpClient: ->
    return unless @ddpClient
    @ddpClient.on 'added', (file) =>
      @addDdpFile file
    @ddpClient.on 'removed', (fileId) =>
      @emit 'info', "Would remove file #{fileId}"
    @ddpClient.on 'changed', (fileId, fields, cleared) =>
      @emit 'info', "Would change file #{fileId}:", fields, cleared
    @ddpClient.on 'subscribed', (collectionName) =>
      @complete = true if collectionName == 'files'
      @emit 'trace', "Subscription has #{_.size @filesById} files"

#Helper functions

removeItemFromArray = (item, array) ->
  idx = array.indexOf item
  array.splice(idx,1) if idx != -1
  return idx != -1

module.exports = FileTree
