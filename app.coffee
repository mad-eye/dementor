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
  
  dementor = new Dementor process.cwd(), httpClient, socket, program.clean
  util.puts "Enabling MadEye in " + clc.bold process.cwd()

  dementor.on 'error', (err) ->
    console.error 'ERROR:', err.message
    shutdown(err.code ? 1)

  dementor.on 'warning', (msg) ->
    console.error 'Warning:', msg

  dementor.once 'enabled', ->
    apogeeUrl = "#{Settings.apogeeUrl}/edit/#{dementor.projectId}"
    devHangoutUrl = "https://hangoutsapi.talkgadget.google.com/hangouts/_?gid=819106734002&gd=#{apogeeUrl}"
    hangoutUrl = "https://plus.google.com/hangouts/_?gid=819106734002&gd=#{apogeeUrl}"
    prodHangoutUrl = "https://plus.google.com/hangouts/_?gid=63701048231&gd=#{apogeeUrl}"

    util.puts "View your project at " + clc.bold apogeeUrl

    if process.env.MADEYE_HANGOUT_DEV
      util.puts "Test Google Hangout at " + clc.bold devHangoutUrl
      util.puts "Use Google Hangout at " + clc.bold hangoutUrl
    else
      util.puts "Use Google Hangout at " + clc.bold prodHangoutUrl
  dementor.enable()

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
  dementor.disable ->
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
