async = require 'async'
{ProjectFiles, fileEventType} = require './projectFiles'
FileTree = require './fileTree'
{HttpClient} = require './httpClient'
{messageMaker, messageAction} = require '../madeye-common/common'
{errors, errorType} = require '../madeye-common/common'
events = require 'events'
fs = require "fs"
clc = require 'cli-color'
_path = require 'path'
exec = require("child_process").exec
#captureProcessOutput = require("./injector/inject").captureProcessOutput
{TERMINAL_PORT, FILE_HARD_LIMIT, FILE_SOFT_LIMIT, ERROR_TOO_MANY_FILES, WARNING_MANY_FILES} = require './constants'

class Dementor extends events.EventEmitter
  #TODO turn this into object of options
  constructor: (options)->
    @directory = options.directory
    @projectName = _path.basename @directory
    @emit 'debug', "Constructing project #{@projectName} with directory #{@directory}"

    @appPort = options.appPort
    captureViaDebugger = options.captureViaDebugger
    @tunnel = options.tunnel
    @terminal = options.term

    @httpClient = options.httpClient
    @tunnelManager = options.tunnelManager
    socket = options.socket
    @attach socket

    @projectFiles = new ProjectFiles(@directory, options.ignorefile)
    @projectId = @projectFiles.getProjectId() unless options.clean
    @fileTree = new FileTree
    @version = require('../package.json').version
    @serverOps = {}

  handleError: (err, silent=false) ->
    return unless err
    @emit 'trace', 'Found error:', err
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
    metric =
      level : 'warn'
      message : msg
      timestamp : new Date()
      projectId : @projectId
    @socket.emit messageAction.METRIC, metric
    @emit 'message-warning', msg

  enable: ->
    if false and @captureViaDebugger
      console.log "fetch meteor pid"
      @getMeteorPid @appPort, (err, pid)->
        console.log "capturing"
        captureProcessOutput(pid)

    @_readFileTree (err, files) =>
      return @handleError err if err
      @emit 'read filetree'

      #TODO: Run this in parallel
      @_setupTunnels (err, tunnels) =>
        return @handleError err if err
        @emit 'trace', "Established tunnels:", tunnels

        #Http request to register project
        action = method = null
        if @projectId
          action = "project/#{@projectId}"
          method = 'PUT'
        else
          action = "project"
          method = 'POST'
        json =
          projectName: @projectName
          files: files
          version: @version
          nodeVersion: process.version
          tunnels: tunnels

        @httpClient.request {method: method, action:action, json: json}, (err, result) =>
          return @handleError err if err
          @handleWarning result.warning
          @projectId = result.project._id
          @fileTree.projectId = @projectId
          @projectFiles.saveProjectId @projectId
          @fileTree.addFiles result.files
          @emit 'enabled'
          #Hack.  The "socket" is actually a SocketNamespace.  Thus we need to access the namespace's socket
          @socket.socket.connect =>
            @watchProject()

  shutdown: (callback) ->
    @emit 'trace', "Shutting down."
    #XXX: Does TunnelManager.shutdown need a callback?
    @tunnelManager?.shutdown()
    if @socket? and @socket.connected
      @.on 'disconnect', callback if callback
      @socket.disconnect()
    else
      callback?()

  addMetric: (type, metric={}) ->
    #TODO: Remove this stub when we've integrated interview-term.
    @emit type
 
  #####
  # Helper functions for enable

  #callback: (err, files) ->
  _readFileTree: (callback) ->
    @projectFiles.readFileTree (err, files) =>
      return callback err if err
      unless files?
        error = message: "No files found!"
        return callback error
      @emit 'debug', "Found #{files.length} files"
      if files.length > FILE_HARD_LIMIT
        return callback ERROR_TOO_MANY_FILES
      else if files.length > FILE_SOFT_LIMIT
        @handleWarning WARNING_MANY_FILES
      callback null, files

  #callback: (err, tunnels) ->
  _setupTunnels: (callback) ->
    tasks = {}
    #TODO: enable web tunneling.
    #if @tunnel
      #tasks['app'] = (cb) =>
        #tunnel =
          #name: "app"
          #local: @tunnel
        #@tunnelManager.startTunnel tunnel, cb
    if @terminal
      tasks['terminal'] = (cb) =>
        tunnel =
          name: "terminal"
          local: TERMINAL_PORT
        @tunnelManager.startTunnel tunnel, cb

    async.parallel tasks, callback


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
    @emit 'trace', 'Watching file tree.'
    @emit 'watching filetree'


  #####
  # Incoming message methods
  # errors from events from messageActions should *NOT* be
  # sent to @handleError, they
  # should be returned to be encoded as a message to
  # Azkaban.
      
  attach: (@socket) ->
    return unless socket?

    socket.on 'connect', =>
      @emit 'trace', "Socket connected"
      @emit 'connect'
      clearInterval @reconnectInterval
      @reconnectInterval = null
      @socket.emit messageAction.HANDSHAKE, @projectId, (err) =>
        @emit 'trace', 'Handshake received'

    socket.on 'reconnect', =>
      @emit 'trace', "Socket reconnected"

    socket.on 'connect_failed', (reason) =>
      @handleWarning "Connection failed: " + reason

    socket.on 'disconnect', =>
      @emit 'trace', "Socket disconnected"
      @emit 'disconnect'
      @reconnectInterval = setInterval (->
        socket.socket.connect()
      ), 10*1000

    socket.on 'error', (reason) =>
      @emit 'debug', "Error in socket, with reason:", reason
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
