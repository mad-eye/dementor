{Dementor} = require('./src/dementor')
{HttpClient} = require('./src/httpClient')
{Settings} = require './madeye-common/common'
util = require 'util'
clc = require 'cli-color'
io = require 'socket.io-client'
{errorType} = require './madeye-common/common'

dementor = null

run = ->
  program = require 'commander'

  #TODO should be able to grab last arugment and use it as filename/dir
  #TODO turn this into class that takes argv and add some tests

  pkg = require './package.json'

  program
    .version(pkg.version)
    .option('-c --clean', 'Start a new project, instead of reusing an existing one.')
    .option('--ignorefile [file]', '.gitignore style file of patterns to not share with madeye (default .madeyeignore)')
    .on("--help", ->
      console.log "  Run madeye in a directory to push its files and subdirectories to madeye.io."
      console.log "  Give the returned url to your friends, and you can edit the project"
      console.log "  simultaneously.  Type ^C to close the session and disable the online project."
    )
  program.parse(process.argv)

  httpClient = new HttpClient Settings.azkabanHost
  socket = io.connect Settings.azkabanUrl,
    'resource': 'socket.io' #NB: This must match the server.  Server defaults to 'socket.io'
    'auto connect': false
  
  dementor = new Dementor process.cwd(), httpClient, socket, program.clean, program.ignorefile
  util.puts "Enabling MadEye in " + clc.bold process.cwd()

  logEvents dementor
  logEvents dementor.projectFiles

  dementor.once 'enabled', ->
    apogeeUrl = "#{Settings.apogeeUrl}/edit/#{dementor.projectId}"
    devHangoutUrl = "https://hangoutsapi.talkgadget.google.com/hangouts/_?gid=819106734002&gd=#{apogeeUrl}"
    prodHangoutUrl = "https://plus.google.com/hangouts/_?gid=63701048231&gd=#{apogeeUrl}"

    util.puts "View your project at " + clc.bold apogeeUrl

    if process.env.MADEYE_HANGOUT_DEV
      util.puts "Test Google Hangout at " + clc.bold devHangoutUrl
    else
      util.puts "Use Google Hangout at " + clc.bold prodHangoutUrl
  dementor.enable()



  #hack for dealing with exceptions caused by broken links
  process.on 'uncaughtException', (err)->
    if err.code == "ENOENT"
      #Silence the error for now
      #console.log "File does not exist #{err.path}"
      0
    else
      throw err

  #FIXME: Need to listen to projectFiles error, warn, info, and debug events

logEvents = (emitter) ->
  if emitter
    emitter.on 'error', (err) ->
      console.error clc.red('ERROR:'), err.message
      shutdown(err.code ? 1)

    emitter.on 'warn', (message) ->
      console.error clc.bold('Warning:'), message

    emitter.on 'info', (message) ->
      console.log message

    emitter.on 'debug', (message) ->
      console.log clc.blackBright message if process.env.MADEYE_DEBUG

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
