{Dementor} = require('./dementor.coffee')
{AzkabanConnection} = require('./azkabanConnection.coffee')
{HttpConnection} = require('./httpConnection.coffee')
{FileTree, File, SocketClient} = require('madeye-common')
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

  socketClient = new SocketClient
  azkaban = new AzkabanConnection new HttpConnection, socketClient
  dementor = new Dementor process.cwd()

  azkaban.enable dementor, (err) ->
    try
      throw new Error err if err
      dementor.watchFileTree (err) ->
        throw new Error err if err
    catch error
      handleError error

handleError = (err) ->
  console.error "Error received:", err
  process.exit(err.code ? 1)

exports.run = run
