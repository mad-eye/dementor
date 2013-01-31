{Dementor} = require('./src/dementor')
{HttpClient} = require('./src/httpClient')
{Settings} = require('madeye-common')
util = require 'util'
clc = require 'cli-color'
io = require 'socket.io-client'

dementor = null

run = ->
  program = require 'commander'

  #TODO should be able to grab last arugment and use it as filename/dir
  #TODO deal with broken connections on server and client
  #TODO gracefully handle ctrl-c
  #TODO turn this into class that takes argv and add some tests

  pkg = require './package.json'

  program
    .version(pkg.version)
    .parse(process.argv)

  server = program.server
  httpClient = new HttpClient Settings.azkabanHost
  socket = io.connect Settings.azkabanUrl,
    'resource': 'socket.io' #NB: This must match the server.  Server defaults to 'socket.io'
    'auto connect': false
  
  dementor = new Dementor process.cwd(), httpClient, socket
  try
    util.puts "Enabling MadEye in " + clc.bold process.cwd()
    dementor.enable (err, flag) ->
      if err then handleError err; return
      apogeeUrl = "#{Settings.apogeeUrl}/edit/#{dementor.projectId}"
      util.puts "View your project at " + clc.bold apogeeUrl if flag == 'ENABLED'
      console.log clc.blackBright "[Dementor received flag: #{flag}]" if process.env.MADEYE_DEBUG
  catch error
    handleError error

handleError = (err) ->
  console.error "Error received:", err
  shutdown(err.code ? 1)

# Shutdown section
SHUTTING_DOWN = false

shutdown = (returnVal=0) ->
  process.exit(returnVal || 1) if SHUTTING_DOWN # || not ?, because we don't want 0
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
  console.log clc.blackBright 'Received SIGINT.' if process.env.MADEYE_DEBUG
  shutdown()

process.on 'SIGTERM', ->
  console.log clc.blackBright "Received kill signal (SIGTERM)" if process.env.MADEYE_DEBUG
  shutdown()
  
  
exports.run = run
