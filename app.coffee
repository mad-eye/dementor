{Dementor} = require('./src/dementor')
{MessageController} = require('./src/messageController')
{HttpClient} = require('./src/httpClient')
{SocketClient} = require('madeye-common')
{Settings} = require('madeye-common')
util = require 'util'
clc = require 'cli-color'

dementor = null

run = ->
  program = require 'commander'

  #TODO should be able to grab last arugment and use it as filename/dir
  #TODO deal with broken connections on server and client
  #TODO gracefully handle ctrl-c
  #TODO turn this into class that takes argv and add some tests

  defaultServer = "#{Settings.httpHost}:#{Settings.httpPort}"

  program
    .version('0.1.0')
    .option('--server <server>', 'point to a non-standard server', String, defaultServer)
    .parse(process.argv)

  server = program.server

  httpClient = new HttpClient server
  socketClient = new SocketClient null, new MessageController
  
  dementor = new Dementor process.cwd(), httpClient, socketClient
  try
    util.puts "Enabling MadEye in " + clc.bold process.cwd()
    dementor.enable (err, flag) ->
      if err then handleError err; return
      util.puts "View your project at " + clc.bold makeUrl dementor.projectId if flag == 'ENABLED'
      console.log clc.blackBright "[Dementor received flag: #{flag}]" if process.env.MADEYE_DEBUG
  catch error
    handleError error

makeUrl = (projectId) ->
  "http://#{Settings.apogeeHost}:#{Settings.apogeePort}/edit/#{projectId}"

handleError = (err) ->
  console.error "Error received:", err
  shutdownGracefully()
  process.exit(err.code ? 1)

# Shutdown section
SHUTTING_DOWN = false

shutdownGracefully = ->
  return if SHUTTING_DOWN
  SHUTTING_DOWN = true
  console.log "Shutting down MadEye."
  dementor.disable ->
    console.log "Closed out connections."
    process.exit 0
 
  setTimeout ->
    console.error "Could not close connections in time, forcefully shutting down"
    process.exit(1)
  , 30*1000

process.on 'SIGINT', ->
  process.exit(1) if SHUTTING_DOWN
  console.log 'Received SIGINT.'
  shutdownGracefully()

process.on 'SIGTERM', ->
  process.exit(1) if SHUTTING_DOWN
  console.log "Received kill signal (SIGTERM)"
  shutdownGracefully()
  
  
exports.run = run
