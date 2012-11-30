_path = require "path"
{DirectoryJanitor, fileEventType} = require './directoryJanitor'
{FileTree} = require 'madeye-common'

class Dementor
  constructor: (@directory) ->
    @directoryJanitor = new DirectoryJanitor(@directory)
    @projectId = @projects()[@directory]
    @fileTree = new FileTree

  disable: ->
    #cancel any file watching etc, flush config?

  handleError: (err) ->
    console.error "Error:", err

  homeDir: ->
    return process.env["MADEYE_HOME"] if process.env["MADEYE_HOME"]
    envVarName = if process.platform == "win32" then "USERPROFILE" else "HOME"
    return process.env[envVarName]

  projectsDbPath: ->
    _path.join @homeDir(), ".madeye_projects"

  projects: ->
    if (@directoryJanitor.exists @projectsDbPath(), true)
      projects = JSON.parse @directoryJanitor.readFile @projectsDbPath(), true
      #console.log "Found projects", projects
      return projects
    else
      #console.log "Found no projectfile."
      {}

  registerProject: (@projectId) ->
    projects = @projects()
    @projects()[@directory] = projectId
    @directoryJanitor.writeFile @projectsDbPath(), JSON.stringify(projects), true
    

  #callback: (err, body) -> ...
  getFileContents: (fileId, callback) ->
    file = @fileTree.findById fileId
    unless file then callback new Error "Can't find file"; return
    callback null, @directoryJanitor.readFile file.path

  #callback: (err) ->
  watchFileTree: (callback) ->
    console.log "Reading filetree"
    @directoryJanitor.readFileTree (err, results) =>
      if err? then callback? err; return
      @handleFileEvent {
        type: fileEventType.ADD
        data:
          files: results
      }, callback
    @directoryJanitor.watchFileTree (err, event) ->
      callback? err if err?
      @handleFileEvent event

  handleFileEvent: (event, callback) ->
    return unless event
    console.log "Calling handleFileEvent with event", event
    try
      @onFileEvent[event.type](event, callback)
    catch err
      callback err

    #addFileCallback = (err, result) ->
    #  if err then @handleError err; return
    #  @fileTree.setFiles result

    #deleteFileCallback = (err, result) ->
    #  if err then @handleError err; return
    #  @fileTree.deleteFiles result

    #editFileCallback = (err) ->
    #  if err then @handleError err; return
    #  #Filetree doesn't store contents, so nothing has to be changed.

    #moveFileCallback = (err, newFile) ->
    #  if err then @handleError err; return
    #  @fileTree.updateFile newFile

    #switch event.type
    #  when fileEventType.ADD then @azkaban.addFiles event.data.files, addFilesCallback
    #  when fileEventType.REMOVE then @azkaban.removeFiles event.data.files, removeFilesCallback
    #  when fileEventType.EDIT then @azkaban.editFile event.data, editFileCallback
    #  when fileEventType.MOVE then @azkaban.moveFile event.data, moveFileCallback

  #callback : (err) -> ...
  onFileEvent :
    add : (event, callback) =>
      console.log "Calling onFileEvent ADD"
      @azkaban.addFiles event.data.files, (err, result) =>
        if err then @handleError err; return
        @fileTree.setFiles result

exports.Dementor = Dementor
