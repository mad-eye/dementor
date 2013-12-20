_ = require 'underscore'
_path = require 'path'
{EventEmitter} = require 'events'
{standardizePath, localizePath, findParentPath} = require '../madeye-common/common'
Logger = require 'pince'

log = new Logger 'fileTree'
class FileTree extends EventEmitter
  constructor: (@ddpClient, @projectFiles, @ddpFiles) ->
    @filesPending = []
    @activeDirs = {}
    @_listenToDdpClient()

  isActiveDir: (path) ->
    #handle the case where path is root (root is always active)
    return true if path == '.' or path == '/' or !path
    return @activeDirs[path]

  loadDirectory: (directory, files) ->
    directory ||= '.'
    existingFilePaths = @ddpFiles.filePathsByParent[directory] ? []
    filePathsAdded = []
    for file in files
      @_addFsFile file
      filePathsAdded.push file.path
    orphanedPaths = _.difference existingFilePaths, filePathsAdded
    @removeFsFile path for path in orphanedPaths
    @ddpClient.markDirectoryLoaded directory unless directory == '.' #don't mark root
    log.debug "Loaded directory", directory
    @emit 'added initial files' if directory == '.' #this is the first dir

  # When a filesystem event happens:
  # if the file's parent is in activeDirs, handle normally.
  # else ignore the event.
  addWatchedFile: (file) ->
    return unless file
    parentPath = findParentPath file.path
    if @isActiveDir parentPath
      @_addFsFile file
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
    log.trace "Updating file #{newFile.path} [#{existingFile._id}]"
    fileId = existingFile._id
    unless existingFile.lastOpened
      @ddpClient.updateFile fileId, mtime: newFile.mtime
      return

    @projectFiles.retrieveContents newFile.path, (err, {contents, checksum, warning}) =>
      if err
        log.error "Error retrieving contents:", err
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

  removeFsFile: (path) ->
    file = @ddpFiles.findByPath path
    unless file
      log.debug "Trying to remove file unknown to ddp:", path
      return
    return if file.scratch #dementor doesn't control these
    unless file.modified
      @ddpClient.removeFile file._id
      log.trace "Removed file #{file.path}"
    else
      @ddpClient.updateFile file._id, {deletedInFs:true}
      log.trace "Marked file #{file.path} as deleted in filesystem"

  _listenToDdpClient: ->
    return unless @ddpClient
    
    @ddpClient.on 'added', (file) =>
      @ddpFiles.addDdpFile file
      removed = removeItemFromArray file.path, @filesPending
      log.trace "Removed #{file.path} from pending dirs." if removed

    @ddpClient.on 'removed', (fileId) =>
      @ddpFiles.removeDdpFile fileId

    @ddpClient.on 'changed', (fileId, fields, cleared) =>
      @ddpFiles.changeDdpFile fileId, fields, cleared

    @ddpClient.on 'subscribed', (collectionName) =>
      @complete = true if collectionName == 'files'

    @ddpClient.on 'activeDir', (dir) =>
      @activeDirs[dir.path] = true
      @projectFiles.readdir dir.path, (err, files) =>
        if err
          if err.reason == 'FileNotFound' and err.path == dir.path
            #the dir is gone, remove it from ddp
            @ddpClient.remove 'activeDirectories', dir._id
            file = @ddpFiles.findByPath dir.path
            @ddpClient.removeFile file._id if file
          else
            log.error "Error loading activeDir #{dir.path}:", err
        else
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
