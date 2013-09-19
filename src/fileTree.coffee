_ = require 'underscore'
_path = require 'path'
uuid = require 'node-uuid'
{EventEmitter} = require 'events'
{standardizePath, localizePath} = require './projectFiles'

class FileTree extends EventEmitter
  constructor: (@ddpClient, @dementor) ->
    @filesById = {}
    @filesByPath = {}
    @dirsPending = []
    @setupDdpClient()

  getFiles: -> _.values @filesById

  findById: (id) -> @filesById[id]

  findByPath: (path) -> @filesByPath[path]

  #Add a file that comes via ddp
  addDdpFile: (file) ->
    return unless file
    @filesById[file._id] = file if file._id
    @filesByPath[file.path] = file
    @emit 'trace', "Added ddp file #{file.path}"
    #removed = removeItemFromArray file.path, @dirsPending
    #@emit 'trace', "Removed #{file.path} from pending dirs." if removed

  #Add a file that we find on the file system
  addFsFile: (file) ->
    #@emit 'trace', "Adding fs file:", file
    return unless file
    existingFile = @filesByPath[file.path]
    if existingFile
      @_updateFile existingFile, file
    else
      @ddpClient.addFile file
    #removed = removeItemFromArray file.path, @dirsPending
    #@emit 'trace', "Removed #{file.path} from pending dirs." if removed

  _updateFile: (existingFile, newFile) ->
    return unless newFile.mtime > existingFile.mtime
    @emit 'trace', "updating existing file:", existingFile
    fileId = existingFile._id
    unless existingFile.lastOpened
      @emit 'trace', "Updating file #{newFile.path} [#{fileId}]"
      @ddpClient.updateFile fileId, mtime: newFile.mtime
      return

    console.log "drc:", @dementor.retrieveContents
    @dementor.retrieveContents fileId, (err, {contents, checksum, warning}) =>
      console.log "retrieveContents:", err, contents, checksum, warning
      if err
        @emit 'error', "Error retrieving contents:", err
        return
      #TODO: Handle warning
      @emit 'trace', "Updating file #{newFile.path} [#{fileId}]"
      if existingFile.modified
        #Don't overwrite people's work
        @ddpClient.updateFile fileId,
          mtime: newFile.mtime
          fsChecksum: checksum
      else
        #Give the people the new content
        @ddpClient.updateFile fileId,
          mtime: newFile.mtime
          fsChecksum: checksum
          loadChecksum: checksum
        @ddpClient.updateFileContents fileId, contents

  addInitialFiles: (files) ->
    return unless files
    existingFilePaths = _.keys @filesByPath
    filePathsAdded = []
    for file in files
      @addFsFile file
      filePathsAdded.push file.path
    orphanedPaths = _.difference existingFilePaths, filePathsAdded
    @emit 'trace', "Found orphaned files", orphanedPaths
    for path in orphanedPaths
      orphan = @filesByPath[path]
      #TODO: Check for modifications/etc
      @ddpClient.removeFile orphan._id

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
      file = @filesById[fileId]
      @emit 'trace', "Updating fields for #{file.path}:", fields if fields
      _.extend file, fields if fields
      @emit 'trace', "Clearing fields for #{file.path}:", cleared if cleared
      delete file[field] for field in cleared if cleared
      @emit 'debug', "Updated file", file
    @ddpClient.on 'subscribed', (collectionName) =>
      @complete = true if collectionName == 'files'
      @emit 'trace', "Subscription has #{_.size @filesById} files"

#Helper functions

removeItemFromArray = (item, array) ->
  idx = array.indexOf item
  array.splice(idx,1) if idx != -1
  return idx != -1

module.exports = FileTree

###
MODIFIED FLAG/CHECKSUM FLOW
---------------------------

REQUEST FILE:
Return contents, set
  lastOpened: now
  loadChecksum
  fsChecksum

SAVE FILE:
Save contents, set
  loadChecksum
  fsChecksum

ADD INITIAL FILE:
  return unless newFile.mtime > existingFile.mtime
  update mtime
  return unless lastOpened
  unless modified
    update loadChecksum, fsChecksum, 
    send new contents to apogee to update bolide
  else
    update fsChecksum

CHANGE FS FILE:
  return unless lastOpened
  change fsChecksum
  send new Contents to apogee to update bolide

APOGEE:
  modified = editorChecksum != fsChecksum
  display modifiedOnClient warning if loadChecksum != fsChecksum

###
