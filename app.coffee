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
  azkaban = new AzkabanConnection new HttpConnection, new SocketClient
  dementor = new Dementor process.cwd()

  azkaban.enable dementor, ->
    #this logic should live in dementor.coffee..
    dementor.readFileTree (files) ->
      azkaban.addFiles files, (error, message)->
        fileTree = new FileTree message.data
        console.log fileTree.files
    dementor.watchFileTree (operation, files) ->
      switch operation
        when "add" then azkaban.addFiles files
        when "delete" then azkaban.deleteFiles files
        when "edit" then azkaban.editFiles files

exports.run = run
