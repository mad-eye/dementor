_ = require 'underscore'
_path = require 'path'
{EventEmitter} = require 'events'
{standardizePath, localizePath, findParentPath} = require '../madeye-common/common'
{Logger} = require '../madeye-common/common'

class FileTree extends EventEmitter
  constructor: (@ddpClient, @projectFiles, @ddpFiles) ->
    Logger.listen @, 'fileTree'
    @filesPending = []
    @activeDirs = {}
    @_listenToDdpClient()

  isActiveDir: (path) ->
    #handle the case where path is root (root is always active)
    return true if path == '.' or path == '/' or !path
    return @activeDirs[path]

  loadDirectory: (directory, files) ->
    existingFilePaths = @ddpFiles.filePathsByParent[directory]
    filePathsAdded = []
    for file in files
      @_addFsFile file
      filePathsAdded.push file.path
    orphanedPaths = _.difference existingFilePaths, filePathsAdded
    @removeFsFile path for path in orphanedPaths
    @ddpClient.markDirectoryLoaded directory if directory #don't mark root
    @emit 'debug', "Loaded directory", (directory || '.')
    @emit 'added initial files' unless directory #this is the first dir

  #we are assuming that the watcher does not notice dirs, so complete
  #missing parent dirs
  # When a filesystem event happens:
  # if the file's parent is in activeDirs, handle normally.
  # else if the file's grandparent is in activeDirs, add the parent.
  #   (this means getting the info for a directory)
  # else ignore the event.
  addWatchedFile: (file) ->
    return unless file
    parentPath = findParentPath file.path
    grandparentPath = findParentPath parentPath
    #TODO: Make hasActiveDir
    if @isActiveDir parentPath
      @_addFsFile file
    #XXX: Make sure we handle root dir correctly
    else if @isActiveDir grandparentPath
      @projectFiles.makeFileData parentPath, (err, data) =>
        return @emit 'warn', @projectFiles.wrapError err if err
        @_addParentDir data
    else
      #We aren't watching this file, move along
      0

  #Add a file that we find on the file system
  _addFsFile: (file) ->
    return unless file
    existingFile = @ddpFiles.findByPath file.path
    if existingFile
      @_updateFile existingFile, file
    else
      @ddpClient.addFile file

  _updateFile: (existingFile, newFile) ->
    return unless newFile.mtime > existingFile.mtime
    @emit 'trace', "Updating file #{newFile.path} [#{fileId}]"
    fileId = existingFile._id
    unless existingFile.lastOpened
      @ddpClient.updateFile fileId, mtime: newFile.mtime
      return

    @projectFiles.retrieveContents newFile.path, (err, {contents, checksum, warning}) =>
      if err
        @emit 'error', "Error retrieving contents:", err
        return
      #TODO: Handle warning
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
  _addParentDir: (dir) ->
    path = dir.path
    return if path == '.' or path == '/' or !path?
    return if path in @filesPending
    @filesPending.push path
    @emit 'trace', "Adding #{path} to dirsPending."
    @_addFsFile dir
 

  removeFsFile: (path) ->
    file = @ddpFiles.findByPath path
    unless file
      @emit 'debug', "Trying to remove file unknown to ddp:", path
      return
    return if file.scratch #dementor doesn't control these
    unless file.modified
      @ddpClient.removeFile file._id
      @emit 'trace', "Removed file #{file.path}"
    else
      @ddpClient.updateFile file._id, {deletedInFs:true}
      @emit 'trace', "Marked file #{file.path} as deleted in filesystem"

  _listenToDdpClient: ->
    return unless @ddpClient
    
    @ddpClient.on 'added', (file) =>
      @ddpFiles.addDdpFile file
      removed = removeItemFromArray file.path, @filesPending
      @emit 'trace', "Removed #{file.path} from pending dirs." if removed

    @ddpClient.on 'removed', (fileId) =>
      @ddpFiles.removeDdpFile fileId

    @ddpClient.on 'changed', (fileId, fields, cleared) =>
      @ddpFiles.changeDdpFile fileId, fields, cleared

    @ddpClient.on 'subscribed', (collectionName) =>
      @complete = true if collectionName == 'files'
      @emit 'trace', "Subscription has #{_.size @filesById} files"

    @ddpClient.on 'activeDir', (dir) =>
      @activeDirs[dir.path] = true
      @projectFiles.readdir dir.path, (err, files) =>
        @loadDirectory dir.path, files

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
