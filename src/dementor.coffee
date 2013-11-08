async = require 'async'
{ProjectFiles, fileEventType} = require './projectFiles'
FileTree = require './fileTree'
{errors, errorType} = require '../madeye-common/common'
events = require 'events'
fs = require "fs"
clc = require 'cli-color'
_path = require 'path'
async = require 'async'
Logger = require 'pince'
{crc32} = require '../madeye-common/common'
exec = require("child_process").exec
#captureProcessOutput = require("./injector/inject").captureProcessOutput
DdpFiles = require "./ddpFiles"

log = new Logger 'dementor'
class Dementor extends events.EventEmitter
  constructor: (options) ->
    Logger.listen @, 'dementor'
    log.trace "Constructing with directory #{options.directory}"
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
        return log.error err if err
        #don't need to wait for this callback
        @ddpClient.subscribe 'commands', @projectId
        #don't need to wait for this callback
        if @terminal or @tunnel
          @setupTunnels()
        #need to be subscribed before adding fs files
        @ddpClient.subscribe 'files', @projectId, (err) =>
          return log.error err if err
          log.trace 'Initial enable done, now adding files'
          #don't need to wait for this callback
          @ddpClient.subscribe 'activeDirectories', @projectId
          @projectFiles.readdir '', (err, files) =>
            return log.error err if err
            @fileTree.loadDirectory null, files
            @watchProject()

  #callback: (err) ->
  registerProject: (callback) ->
    params =
      projectId: @projectId
      projectName: @projectName
      version: @version
      nodeVersion: process.version
    @ddpClient.registerProject params, (err, projectId, warning) =>
      return log.error err if err
      if warning
        @emit 'message-warning', warning
      @projectId = projectId
      @projectFiles.saveProjectId projectId
      @emit 'enabled'
      callback()

  shutdown: (callback) ->
    log.trace "Shutting down."
    #XXX: Does TunnelManager.shutdown need a callback?
    @tunnelManager?.shutdown()
    @ddpClient.shutdown ->
      callback?()

  setupTunnels: ->
    log.trace "Setting up terminal tunnel: #{@terminal}"
    tasks = {}
    #TODO: enable web tunneling.
    #if @tunnel
      #tasks['app'] = (cb) =>
        #log.trace "Setting up tunnel on port #{@tunnel}"
        #tunnel =
          #name: "app"
          #localPort: @tunnel
        #@tunnelManager.startTunnel tunnel, cb
    if @terminal
      tasks['terminal'] = (cb) =>
        log.trace "Setting up tunnel on port 9798"
        tunnel =
          name: "terminal"
          localPort: 9798
        @tunnelManager.startTunnel tunnel, cb

    async.parallel tasks, (err, tunnels) =>
      if err
        log.debug "Error setting up tunnels:", tunnels, err
        @handleWarning "We could not set up the tunnels; continuing without tunnels."
        return
      log.debug 'Tunnels connected', tunnels
      @ddpClient.addTunnels tunnels, (err) =>
        if err
          log.debug "Error setting up tunnels:", err
          @handleWarning "We could not set up the tunnels; continuing without tunnels."
        else
          log.debug 'Tunnels established successfully.'
        


  #####
  # Events from ProjectFiles

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
    log.trace 'Watching file tree.'
    @emit 'watching filetree'

  ## DDP CLIENT SETUP
  setupDdpClient: ->
    errorCallback = (err, commandId) =>
      @ddpClient.commandReceived err, {commandId}

    @ddpClient.on 'command', (command, data) =>
      log.trace "Command received:", data
      switch command

        when 'request file'
          fileId = data.fileId
          unless fileId
            log.warn "Request file failed: missing fileId"
            return errorCallback errors.new('MissingParameter', parameter:'fileId'), data.commandId
          path = @fileTree.ddpFiles.findById(fileId)?.path
          unless path
            log.warn "Request file failed: missing file #{fileId}"
            return errorCallback errors.new('FileNotFound', path:path), data.commandId
          log.trace "Remote request for #{path}"
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
            log.warn "Save file failed: missing fileId or contents"
            if !fileId
              missingParam = 'fileId'
            else
              missingParam = 'contents'
            return errorCallback errors.new('MissingParameter', parameter:missingParam), data.commandId
          path = @fileTree.ddpFiles.findById(fileId)?.path
          unless path
            log.warn "Save file failed: missing file #{fileId}"
            return errorCallback errors.new('FileNotFound', path:path), data.commandId
          log.debug "Saving file #{path} from remote contents."
          @projectFiles.writeFile path, contents, (err) =>
            if err
              log.warn "Error saving file #{path}:", err
              return errorCallback err, data.commandId
            checksum = crc32 contents
            @emit 'message-info', "Saving file " + clc.bold path
            @ddpClient.updateFile fileId,
              loadChecksum: checksum
              fsChecksum: checksum
            @ddpClient.commandReceived null, commandId:data.commandId

module.exports = Dementor
