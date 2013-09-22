_ = require 'underscore'
_path = require 'path'
uuid = require 'node-uuid'
{EventEmitter} = require 'events'
{standardizePath, localizePath} = require './projectFiles'
{Logger} = require '../madeye-common/common'

class FileTree extends EventEmitter
  constructor: (@ddpClient, @projectFiles) ->
    Logger.listen @, 'fileTree'
    @filesById = {}
    @filesByPath = {}
    @filesPending = []
    @_listenToDdpClient()

  getFiles: -> _.values @filesById

  findById: (id) -> @filesById[id]

  findByPath: (path) -> @filesByPath[path]

  #Add a file that comes via ddp
  addDdpFile: (file) ->
    return unless file
    @filesById[file._id] = file if file._id
    @filesByPath[file.path] = file
    @emit 'trace', "Added ddp file #{file.path}"
    removed = removeItemFromArray file.path, @filesPending
    @emit 'trace', "Removed #{file.path} from pending dirs." if removed

  #Add a file that we find on the file system
  addFsFile: (file) ->
    @emit 'trace', "Adding fs file:", file
    return unless file
    existingFile = @filesByPath[file.path]
    @emit 'trace', "File #{file.path} already exists:", existingFile?
    if existingFile
      @_updateFile existingFile, file
    else
      @ddpClient.addFile file

  _updateFile: (existingFile, newFile) ->
    return unless newFile.mtime > existingFile.mtime
    @emit 'trace', "updating existing file:", existingFile
    fileId = existingFile._id
    unless existingFile.lastOpened
      @emit 'trace', "Updating file #{newFile.path} [#{fileId}]"
      @ddpClient.updateFile fileId, mtime: newFile.mtime
      return

    @projectFiles.retrieveContents newFile.path, (err, {contents, checksum, warning}) =>
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

  #Add missing parent dirs to files
  _addParentDirs: (file) ->
    path = file.path
    loop
      #Need to localize path seps for _path.dirname to work
      path = standardizePath _path.dirname localizePath path
      break if path == '.' or path == '/' or !path?
      #We assume if a dir is already handled, all of its parents are
      break if path in @filesPending
      break if path of @filesByPath
      @filesPending.push path
      @emit 'trace', "Adding #{path} to dirsPending."
      @projectFiles.makeFileData path, (err, filedata) =>
        if err
          @emit 'warn', "Error making fileData for #{path}:", err
          return
        return unless filedata
        @addFsFile filedata
 
  addInitialFiles: (files) ->
    return unless files
    existingFilePaths = _.keys @filesByPath
    filePathsAdded = []
    for file in files
      @addFsFile file
      filePathsAdded.push file.path
    orphanedPaths = _.difference existingFilePaths, filePathsAdded
    @removeFsFile path for path in orphanedPaths
    @emit 'added initial files'

  #we are assuming that the watcher does not notice dirs, so complete
  #missing parent dirs
  addWatchedFile: (file) ->
    return unless file
    @addFsFile file
    @_addParentDirs file

  removeDdpFile: (fileId) ->
    file = @filesById[fileId]
    return unless file
    delete @filesById[fileId]
    delete @filesByPath[file.path]
    @emit 'trace', "Removed ddp file #{file.path}"

  removeFsFile: (path) ->
    file = @filesByPath[path]
    unless file
      @emit 'debug', "Trying to remove file unknown to ddp:", path
      return
    unless file.modified
      @ddpClient.removeFile file._id
      @emit 'trace', "Removed file #{file.path}"
    else
      @ddpClient.updateFile file._id, {deletedInFs:true}
      @emit 'trace', "Marked file #{file.path} as deleted in filesystem"

  _changeDdpFile: (fileId, fields={}, cleared=[]) ->
    file = @filesById[fileId]
    @emit 'trace', "Updating fields for #{file.path}:", fields if fields
    _.extend file, fields if fields
    @emit 'trace', "Clearing fields for #{file.path}:", cleared if cleared
    delete file[field] for field in cleared if cleared
    @emit 'debug', "Updated file", file

  _listenToDdpClient: ->
    return unless @ddpClient
    @ddpClient.on 'added', (file) =>
      @addDdpFile file
    @ddpClient.on 'removed', (fileId) =>
      @removeDdpFile fileId
    @ddpClient.on 'changed', (fileId, fields, cleared) =>
      @_changeDdpFile fileId, fields, cleared
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

DELETE FS FILE:
  unless modified
    delete file
  else
    set deleteInFs=true

APOGEE:
  file deleted
    if file not in editor do nothing (it will disappear)
    if file in editor, navigate user to another file, display warning
  file with deleteInFs==true
    if in editor, display "Deleted on FS" warning
    if not in editor, do nothing (mark in file tree somehow?)

###
