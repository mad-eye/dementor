{ProjectFiles, fileEventType} = require './projectFiles'
FileTree = require './fileTree'
{HttpClient} = require './httpClient'
{messageMaker, messageAction} = require '../madeye-common/common'
{errors, errorType} = require '../madeye-common/common'
{crc32, cleanupLineEndings, findLineEndingType} = require '../madeye-common/common'
events = require 'events'
clc = require 'cli-color'
_path = require 'path'
{FILE_HARD_LIMIT, FILE_SOFT_LIMIT, ERROR_TOO_MANY_FILES, WARNING_MANY_FILES} = require './constants'
async = require 'async'

class Dementor extends events.EventEmitter
  constructor: (options) ->
    @emit 'trace', "Constructing with directory #{options.directory}"
    @projectFiles = new ProjectFiles(options.directory, options.ignorefile)
    @projectName = _path.basename options.directory
    @projectId = @projectFiles.projectIds()[options.directory] unless options.clean

    @httpClient = options.httpClient
    @ddpClient = options.ddpClient
    @setupDdpClient()
    @fileTree = new FileTree @ddpClient
    @attach options.socket
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
      @fileTree.addInitialFiles results.files
      #@watchProject()

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
    @projectFiles.on messageAction.LOCAL_FILES_ADDED, (data) =>
      data.projectId = @projectId
      data.files = @fileTree.completeParentFiles data.files
      @socket.emit messageAction.LOCAL_FILES_ADDED, data, (err, files) =>
        return @handleError err if err
        @fileTree.addFiles files

    @projectFiles.on messageAction.LOCAL_FILE_SAVED, (data) =>
      data.projectId = @projectId
      data.file = @fileTree.findByPath(data.path)
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

      @socket.emit messageAction.LOCAL_FILE_SAVED, data, (err, response) =>
        return @handleError err if err
        if response?.action == messageAction.WARNING
          @handleWarning response.message

    @projectFiles.on messageAction.LOCAL_FILES_REMOVED, (data) =>
      data.projectId = @projectId
      data.files = []
      for path in data.paths
        file = @fileTree.findByPath(path)
        #FIXME: This was happening in production.  Write tests for it.
        unless file?
          @handleWarning "#{errorType.MISSING_PARAM}: filePath #{data.paths[0]} not found in fileTree", true
          continue
        data.files.push file
      return unless data.files.length > 0
      @socket.emit messageAction.LOCAL_FILES_REMOVED, data, (err, response) =>
        return @handleError err if err
        if response?.action == messageAction.WARNING
          @handleWarning response.message
          #XXX: Going to cause problems if a file is not deleted due to warning.
          #But need to not delete it from the tree in order to resave it.
          #Need to rethink the separation of fs files and mongo files.
        else
          @fileTree.remove file._id for file in data.files

    @projectFiles.watchFileTree()
    @addMetric 'WATCHING_FILETREE'
    @emit 'trace', 'Watching file tree.'

  ## DDP CLIENT SETUP
  setupDdpClient: ->
    @ddpClient.on 'command', (command, data) =>
      @emit 'trace', "Command received:", data
      switch command
        when 'request file'
          fileId = data.fileId
          #TODO: Send this to and handle this on apogee
          #unless fileId then callback errors.new 'MISSING_PARAM'; return
          path = @fileTree.findById(fileId)?.path
          @emit 'trace', "Remote request for #{path}"
          @projectFiles.readFile path, (err, contents) =>
            cleanContents = cleanupLineEndings contents
            checksum = crc32 contents
            warning = null
            unless cleanContents == contents
              lineEndingType = findLineEndingType contents
              warning =
                title: "Inconsistent line endings"
                message: "We've converted them all into #{lineEndingType}."
            
            @ddpClient.sendFileContents err,
              commandId: data.commandId
              fileId: fileId
              contents: contents
              checksum: checksum
              warning: warning






  #####
  # Incoming message methods
  # errors from events from messageActions should *NOT* be
  # sent to @handleError, they
  # should be returned to be encoded as a message to
  # Azkaban.
      
  attach: (@socket) ->
    return unless socket?

    socket.on 'connect', =>
      @addMetric "CONNECTED"
      clearInterval @reconnectInterval
      @reconnectInterval = null
      @socket.emit messageAction.HANDSHAKE, @projectId, (err) =>
        @addMetric 'HANDSHAKE_RECEIVED'

    socket.on 'reconnect', =>
      @addMetric "RECONNECTED"

    socket.on 'connect_failed', (reason) =>
      @handleWarning "Connection failed: " + reason
      @addMetric "CONNECTION_FAILED"

    socket.on 'disconnect', =>
      @addMetric "DISCONNECT"
      @reconnectInterval = setInterval (->
        socket.socket.connect()
      ), 10*1000

    socket.on 'error', (reason) =>
      @handleError reason

    #callback: (err, body) =>, errors are encoded as {error:}
    socket.on messageAction.REQUEST_FILE, (data, callback) =>
      fileId = data.fileId
      unless fileId then callback errors.new 'MISSING_PARAM'; return
      path = @fileTree.findById(fileId)?.path
      @emit 'trace', "Remote request for #{path}"
      @projectFiles.readFile path, callback

    #callback: (err) =>, errors are encoded as {error:}
    socket.on messageAction.SAVE_LOCAL_FILE, (data, callback) =>
      fileId = data.fileId
      contents = data.contents
      unless fileId && contents?
        callback errors.new 'MISSING_PARAM'; return
      @serverOps[fileId] = action: messageAction.SAVE_LOCAL_FILE, timestamp: new Date
      path = @fileTree.findById(fileId)?.path
      @emit 'trace', "Remote save for #{path}"
      @projectFiles.writeFile path, contents, (err) ->
        console.log "Saving file " + clc.bold path unless err
        callback err

exports.Dementor = Dementor
