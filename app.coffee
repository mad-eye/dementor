{Dementor} = require('./dementor.coffee')
{AzkabanConnection} = require('./azkabanConnection.coffee')
{HttpConnection} = require('./httpConnection.coffee')
{ChannelConnection} = require('./channelConnection.coffee')
{Settings} = require('./Settings')

run = ->
  program = require 'commander'

  #TODO should be able to grab last arugment and use it as filename/dir
  #TODO deal with broken connections on server and client
  #TODO gracefully handle ctrl-c
  #TODO turn this into class that takes argv and add some tests


  program
    .version('0.1.0')
    .option('--start', 'start the daemon')
    .option('--init', 'iniitialize the project')
    .option('--server', 'point to a non-standard server')
    .parse(process.argv)

  if program.server
    server = program.server
  else
    server = "#{Settings.httpHost}:#{Settings.httpPort}"

  azkaban = new AzkabanConnection new HttpConnection, new ChannelConnection
  dementor = new Dementor process.cwd()

  if program.init
    azkaban.enable dementor

  if program.start
    azkaban.enable dementor
    dementor.readFileTree (files) ->
      azkaban.addFiles files
    dementor.watchFileTree (operation, files) ->
      switch operation
        when "add" then azkaban.addFiles files
        when "delete" then azkaban.deleteFiles files
        when "edit" then azkaban.editFiles files

  #wrap this in a run function and export it for easier testing?

exports.run = run