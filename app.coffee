{Dementor} = require('./dementor.coffee')
{MessageController} = require('./src/messageController')
{HttpClient} = require('./src/httpClient')
{SocketClient} = require('madeye-common')
{Settings} = require('./Settings')

fileTree = undefined

run = ->
  program = require 'commander'

  #TODO should be able to grab last arugment and use it as filename/dir
  #TODO deal with broken connections on server and client
  #TODO gracefully handle ctrl-c
  #TODO turn this into class that takes argv and add some tests

  program
    .version('0.1.0')
    .option('--server', 'point to a non-standard server')
    .parse(process.argv)

  if program.server
    server = program.server
  else
    server = "#{Settings.httpHost}:#{Settings.httpPort}"

  httpClient = new HttpClient server
  socketClient = new SocketClient null, new MessageController
  
  dementor = new Dementor process.cwd(), httpClient, socketClient
  try
    dementor.enable (err, flag) ->
      if err
        throw new Error err
      else
        console.log "Dementor received flag: #{flag}"
  catch error
    handleError error


handleError = (err) ->
  console.error "Error received:", err
  process.exit(err.code ? 1)

exports.run = run
