{Dementor} = require('./src/dementor')
DdpClient = require './src/ddpClient'
{HttpClient} = require('./src/httpClient')
{Settings} = require './madeye-common/common'
util = require 'util'
clc = require 'cli-color'
io = require 'socket.io-client'
{errorType} = require './madeye-common/common'
{LogListener} = require './madeye-common/common'

dementor = null
debug = false

run = ->
  program = require 'commander'

  #TODO should be able to grab last arugment and use it as filename/dir

  pkg = require './package.json'

  program
    .version(pkg.version)
    .option('-c --clean', 'Start a new project, instead of reusing an existing one.')
    .option('-d --debug', 'Show debug output (may be noisy)')
    .option('--madeyeUrl [url]', 'url to point to (instead of madeye.io)')
    .option('--trace', 'Show trace-level debug output (will be very noisy)')
    .option('--ignorefile [file]', '.gitignore style file of patterns to not share with madeye (default .madeyeignore)')
    .on("--help", ->
      console.log "  Run madeye in a directory to push its files and subdirectories to madeye.io."
      console.log "  Give the returned url to your friends, and you can edit the project"
      console.log "  simultaneously.  Type ^C to close the session and disable the online project."
    )
  program.parse(process.argv)
  debug = program.debug
  logLevel = switch
    when program.trace then 'trace'
    when program.debug then 'debug'
    else 'info'
  listener = new LogListener
    logLevel: logLevel
    onError: (err) ->
      shutdown(err.code ? 1)

  if program.madeyeUrl
    apogeeUrl = program.madeyeUrl
    azkabanUrl = "#{program.madeyeUrl}/api"
    socketUrl = program.madeyeUrl
  else
    apogeeUrl = Settings.apogeeUrl
    azkabanUrl = Settings.azkabanUrl
    socketUrl = Settings.socketUrl

  listener.log 'debug', "Connecting to socketUrl #{socketUrl}"
  socket = io.connect socketUrl,
    'resource': 'socket.io' #NB: This must match the server.  Server defaults to 'socket.io'
    'auto connect': false
  
  #TODO: Handle custom url case.
  ddpClient = new DdpClient
    host: Settings.ddpHost
    port: Settings.ddpPort
  listener.listen ddpClient, 'ddpClient'
  ddpClient.on 'message-warning', (msg) ->
    console.warn clc.bold('Warning:'), msg

  dementor = new Dementor
    directory: process.cwd()
    ddpClient: ddpClient
    socket: socket
    clean: program.clean
    ignoreFile: program.ignorefile
  util.puts "Enabling MadEye in " + clc.bold process.cwd()

  listener.listen dementor, 'dementor'
  listener.listen dementor.projectFiles, 'projectFiles'
  listener.listen dementor.fileTree, 'fileTree'

  dementor.once 'enabled', ->
    apogeeUrl = "#{apogeeUrl}/edit/#{dementor.projectId}"
    hangoutUrl = "#{azkabanUrl}/hangout/#{dementor.projectId}"

    util.puts "View your project at " + clc.bold apogeeUrl
    util.puts "Use Google Hangout at " + clc.bold hangoutUrl

  dementor.on 'message-warning', (msg) ->
    console.warn clc.bold('Warning:'), msg

  dementor.enable()



  #hack for dealing with exceptions caused by broken links
  process.on 'uncaughtException', (err)->
    if err.code == "ENOENT"
      #Silence the error for now
      listener.debug "File does not exist #{err.path}"
      0
    else
      throw err

# Shutdown section
SHUTTING_DOWN = false

shutdown = (returnVal=0) ->
  process.exit(returnVal || 1) if SHUTTING_DOWN # || not ?, because we don't want 0
  process.nextTick ->
    shutdownGracefully(returnVal)

shutdownGracefully = (returnVal=0) ->
  return if SHUTTING_DOWN
  SHUTTING_DOWN = true
  console.log "Shutting down MadEye.  Press ^C to force shutdown."
  dementor.shutdown ->
    console.log "Closed out connections."
    process.exit returnVal
 
  setTimeout ->
    console.error "Could not close connections in time, shutting down harder."
    process.exit(returnVal || 1)
  , 20*1000

process.on 'SIGINT', ->
  #console.log clc.blackBright 'Received SIGINT.' if process.env.MADEYE_DEBUG
  shutdown()

process.on 'SIGTERM', ->
  #console.log clc.blackBright "Received kill signal (SIGTERM)" if process.env.MADEYE_DEBUG
  shutdown()

exports.run = run
