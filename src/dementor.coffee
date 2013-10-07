async = require 'async'
{ProjectFiles, fileEventType} = require './projectFiles'
FileTree = require './fileTree'
{errors, errorType} = require '../madeye-common/common'
events = require 'events'
fs = require "fs"
clc = require 'cli-color'
_path = require 'path'
constants = require './constants'
async = require 'async'
{Logger} = require '../madeye-common/common'
{crc32} = require '../madeye-common/common'
exec = require("child_process").exec
#captureProcessOutput = require("./injector/inject").captureProcessOutput
DdpFiles = require "./ddpFiles"

class Dementor extends events.EventEmitter
  constructor: (options) ->
    Logger.listen @, 'dementor'
    @emit 'trace', "Constructing with directory #{options.directory}"
    @projectFiles = options.projectFiles ? new ProjectFiles(options.directory, options.ignorefile)
    @projectName = _path.basename options.directory
    @projectId = @projectFiles.getProjectId() unless options.clean

    @appPort = options.appPort
    captureViaDebugger = options.captureViaDebugger
    @tunnel = options.tunnel
    @terminal = options.term
    @tunnelManager = options.tunnelManager

    @ddpClient = options.ddpClient
    @setupDdpClient()
    @fileTree = new FileTree @ddpClient, @projectFiles, new DdpFiles
    @version = require('../package.json').version

  handleWarning: (msg) ->
    return unless msg?
    @emit 'message-warning', msg

  enable: ->
    if false and @captureViaDebugger
      console.log "fetch meteor pid"
      @getMeteorPid @appPort, (err, pid)->
        console.log "capturing"
        captureProcessOutput(pid)

    #connect callback gets called each time a (re)connection is established
    #to avoid calling cb multiple times, trigger once
    #error event will handle error case.
    @ddpClient.connect()
    @ddpClient.once 'connected', =>
      @registerProject (err) =>
        return @emit 'error', err if err
        #don't need to wait for this callback
        @ddpClient.subscribe 'commands', @projectId
        #don't need to wait for this callback
        if @terminal or @tunnel
          @setupTunnels()
        #need to be subscribed before adding fs files
        @ddpClient.subscribe 'files', @projectId, (err) =>
          return @emit 'error', err if err
          @emit 'trace', 'Initial enable done, now adding files'
          #don't need to wait for this callback
          @ddpClient.subscribe 'activeDirectories', @projectId
          @projectFiles.readdir '', (err, files) =>
            return @emit 'error', err if err
            @fileTree.loadDirectory null, files
            @watchProject()

  #callback: (err, files) ->
  readFileTree: (callback) ->
    @projectFiles.readFileTree (err, files) =>
      return callback err if err
      unless files?
        err = message: "No files found!"
        return callback err
      @emit 'debug', "Found #{files.length} files"
      if files.length > constants.FILE_HARD_LIMIT
        return callback constants.ERROR_TOO_MANY_FILES
      else if files.length > constants.FILE_SOFT_LIMIT
        @handleWarning constants.WARNING_MANY_FILES
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
      return @emit 'error', err if err
      if warning
        @emit 'message-warning', warning
      @projectId = projectId
      @projectFiles.saveProjectId projectId
      @emit 'enabled'
      callback()

  shutdown: (callback) ->
    @emit 'trace', "Shutting down."
    #XXX: Does TunnelManager.shutdown need a callback?
    @tunnelManager?.shutdown()
    @ddpClient.shutdown ->
      callback?()

  addMetric: (type, metric={}) ->
    #TODO: Remove this stub when we've integrated interview-term.
    @emit type
 
  setupTunnels: ->
    @emit 'trace', "Setting up terminal tunnel: @{terminal}"
    tasks = {}
    #TODO: enable web tunneling.
    #if @tunnel
      #tasks['app'] = (cb) =>
        #@emit 'trace', "Setting up tunnel on port #{@tunnel}"
        #tunnel =
          #name: "app"
          #localPort: @tunnel
        #@tunnelManager.startTunnel tunnel, cb
    if @terminal
      tasks['terminal'] = (cb) =>
        @emit 'trace', "Setting up tunnel on port #{constants.TERMINAL_PORT}"
        tunnel =
          name: "terminal"
          localPort: constants.TERMINAL_PORT
        @tunnelManager.startTunnel tunnel, cb

    async.parallel tasks, (err, tunnels) =>
      if err
        @emit 'debug', "Error setting up tunnels:", err
        @handleWarning "We could not set up the tunnels; continuing without tunnels."
        return
      @emit 'debug', 'Tunnels connected'
      @ddpClient.addTunnels tunnels, (err) =>
        if err
          @emit 'debug', "Error setting up tunnels:", err
          @handleWarning "We could not set up the tunnels; continuing without tunnels."
        else
          @emit 'debug', 'Tunnels established successfully.'
        


  #####
  # Events from ProjectFiles

  # XXX: When files are modified because of server messages, they will fire events.  We should ignore those.

  watchProject: ->
    @projectFiles.on 'file added', (file) =>
      file.projectId = @projectId
      @fileTree.addWatchedFile file

    @projectFiles.on 'file changed', (file) =>
      file.projectId = @projectId
      #Just add it, fileTree will notice it exists and handle it
      @fileTree.addWatchedFile file

    @projectFiles.on 'file removed', (path) =>
      @fileTree.removeFsFile path

    @projectFiles.watchFileTree()
    @emit 'trace', 'Watching file tree.'
    @emit 'watching filetree'

  ## DDP CLIENT SETUP
  setupDdpClient: ->
    errorCallback = (err, commandId) =>
      @ddpClient.commandReceived err, {commandId}

    @ddpClient.on 'command', (command, data) =>
      @emit 'trace', "Command received:", data
      switch command

        when 'request file'
          fileId = data.fileId
          unless fileId
            @emit 'warn', "Request file failed: missing fileId"
            return errorCallback errors.new('MissingParameter', parameter:'fileId'), data.commandId
          path = @fileTree.ddpFiles.findById(fileId)?.path
          unless path
            @emit 'warn', "Request file failed: missing file #{fileId}"
            return errorCallback errors.new('FileNotFound', path:path), data.commandId
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
            if !fileId
              missingParam = 'fileId'
            else
              missingParam = 'contents'
            return errorCallback errors.new('MissingParameter', parameter:missingParam), data.commandId
          path = @fileTree.ddpFiles.findById(fileId)?.path
          unless path
            @emit 'warn', "Save file failed: missing file #{fileId}"
            return errorCallback errors.new('FileNotFound', path:path), data.commandId
          @emit 'debug', "Saving file #{path} from remote contents."
          @projectFiles.writeFile path, contents, (err) =>
            if err
              @emit 'warn', "Error saving file #{path}:", err
              return errorCallback err, data.commandId
            checksum = crc32 contents
            @emit 'message-info', "Saving file " + clc.bold path
            @ddpClient.updateFile fileId,
              loadChecksum: checksum
              fsChecksum: checksum
            @ddpClient.commandReceived null, commandId:data.commandId

module.exports = Dementor
