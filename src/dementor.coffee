{ProjectFiles, fileEventType} = require './projectFiles'
FileTree = require './fileTree'
{messageMaker, messageAction} = require '../madeye-common/common'
{errors, errorType} = require '../madeye-common/common'
events = require 'events'
clc = require 'cli-color'
_path = require 'path'
{FILE_HARD_LIMIT, FILE_SOFT_LIMIT, ERROR_TOO_MANY_FILES, WARNING_MANY_FILES} = require './constants'
async = require 'async'
{Logger} = require '../madeye-common/common'
{crc32} = require '../madeye-common/common'

class Dementor extends events.EventEmitter
  constructor: (options) ->
    Logger.listen @, 'dementor'
    @emit 'trace', "Constructing with directory #{options.directory}"
    @projectFiles = new ProjectFiles(options.directory, options.ignorefile)
    @projectName = _path.basename options.directory
    @projectId = @projectFiles.getProjectId() unless options.clean

    @ddpClient = options.ddpClient
    @setupDdpClient()
    @fileTree = new FileTree @ddpClient, @projectFiles
    @version = require('../package.json').version
    @serverOps = {}

  handleError: (err, silent=false) ->
    return unless err
    message = err.message ? err
    metric =
      level : 'error'
      type: err.type
      message: message
      timestamp : new Date()
      projectId : @projectId
    @socket.emit messageAction.METRIC, metric
    @emit 'error', err unless silent

  handleWarning: (msg) ->
    return unless msg?
    @emit 'message-warning', msg

  enable: ->
    async.parallel {
      ddp: (cb) =>
        #connect callback gets called each time a (re)connection is established
        #to avoid calling cb multiple times, trigger once
        #error event will handle error case.
        @ddpClient.connect()
        @ddpClient.once 'connected', =>
          @registerProject (err) =>
            return cb err if err
            #need to be subscribed before adding fs files
            @ddpClient.subscribe 'files', @projectId, cb
            #don't need to wait for this callback
            @ddpClient.subscribe 'commands', @projectId
      files: (cb) =>
        @readFileTree (err, files) ->
          cb err, files
    }, (err, results) =>
      return @handleError err if err
      @emit 'trace', 'Initial enable done, now adding files'
      @fileTree.addInitialFiles results.files
      @watchProject()

  #callback: (err, files) ->
  readFileTree: (callback) ->
    @projectFiles.readFileTree (err, files) =>
      return callback err if err
      unless files?
        err = message: "No files found!"
        return callback err
      @emit 'debug', "Found #{files.length} files"
      if files.length > FILE_HARD_LIMIT
        return callback ERROR_TOO_MANY_FILES
      else if files.length > FILE_SOFT_LIMIT
        @handleWarning WARNING_MANY_FILES
      @emit 'trace', 'Read filetree'
      callback null, files

  #callback: (err) ->
  registerProject: (callback) ->
    params =
      projectId: @projectId
      projectName: @projectName
      version: @version
      nodeVersion: process.version
    @ddpClient.registerProject params, (err, projectId, warning) =>
      return callback err if err
      if warning
        @emit 'message-warning', warning
      @projectId = projectId
      @projectFiles.saveProjectId projectId
      @emit 'enabled'
      callback()


  shutdown: (callback) ->
    @emit 'trace', "Shutting down."
    @ddpClient.shutdown ->
      callback?()

  addMetric: (type, metric={}) ->
    #TODO: Remove this stub when we've integrated interview-term.
    @emit type
 
  #####
  # Events from ProjectFiles

  # XXX: When files are modified because of server messages, they will fire events.  We should ignore those.

  watchProject: ->
    @projectFiles.on 'file added', (file) =>
      file.projectId = @projectId
      #TODO: Do we need to add parent dirs, or will this happen automatically?
      #data.files = @fileTree.completeParentFiles data.files
      @fileTree.addFsFile file

    @projectFiles.on 'file changed', (file) =>
      file.projectId = @projectId
      #Just add it, fileTree will notice it exists and handle it
      @fileTree.addFsFile file

      ### Do we still need this?
      serverOp = @serverOps[data.file._id]
      if serverOp && serverOp.action == messageAction.SAVE_LOCAL_FILE
        delete @serverOps[data.file._id]
        now = (new Date()).valueOf()
        #Make sure it's not an old possibly stuck serverOp? 
        if serverOp.timestamp.valueOf() > now - 10*1000
          return
        else
          @addMetric "SERVER_OP_STUCK",
            level: 'info'
            fileId: data.file._id
            serverOp: serverOp
      ###

    @projectFiles.on 'file removed', (path) =>
      @fileTree.removeFsFile path

    @projectFiles.watchFileTree()
    @addMetric 'WATCHING_FILETREE'
    @emit 'trace', 'Watching file tree.'

  ## DDP CLIENT SETUP
  setupDdpClient: ->
    errorCallback = (err, commandId) ->
      @ddpClient.commandReceived err, {commandId}

    @ddpClient.on 'command', (command, data) =>
      @emit 'trace', "Command received:", data
      switch command

        when 'request file'
          fileId = data.fileId
          unless fileId
            @emit 'warn', "Request file failed: missing fileId"
            return errorCallback errors.new('MISSING_PARAM'), data.commandId
          path = @fileTree.findById(fileId)?.path
          unless path
            @emit 'warn', "Request file failed: missing file #{fileId}"
            return errorCallback errors.new('NO_FILE'), data.commandId
          @emit 'trace', "Remote request for #{path}"
          @projectFiles.retrieveContents path, (err, results) =>
            if err
              return errorCallback err, data.commandId
            
            @ddpClient.updateFile fileId,
              loadChecksum: results.checksum
              fsChecksum: results.checksum
              lastOpened: Date.now()

            @ddpClient.commandReceived null,
              commandId: data.commandId
              fileId: fileId
              contents: results.contents
              warning: results.warning

        when 'save file'
          fileId = data.fileId
          contents = data.contents
          unless fileId && contents?
            @emit 'warn', "Save file failed: missing fileId or contents"
            return errorCallback errors.new('MISSING_PARAM'), data.commandId
          path = @fileTree.findById(fileId)?.path
          unless path
            @emit 'warn', "Save file failed: missing file #{fileId}"
            return errorCallback errors.new('NO_FILE'), data.commandId
          @emit 'debug', "Saving file #{path} from remote contents."
          #TODO: Re-enable this to prevent duplicate events
          #XXX: But want this to update mtime -- maybe handle event smarter?
          #@serverOps[fileId] = action: messageAction.SAVE_LOCAL_FILE, timestamp: new Date
          @projectFiles.writeFile path, contents, (err) =>
            if err
              @emit 'warn', "Error saving file #{path}:", err
              #TODO: Wrap error into JSON object
              return errorCallback err, data.commandId
            checksum = crc32 contents
            @emit 'message-info', "Saving file " + clc.bold path
            @ddpClient.updateFile fileId,
              loadChecksum: checksum
              fsChecksum: checksum
            @ddpClient.commandReceived null, commandId:data.commandId


exports.Dementor = Dementor
