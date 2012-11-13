#!/usr/bin/env node

Dementor = require('./dementor.coffee').Dementor
Azkaban = require('./azkaban.coffee').Azkaban
program = require 'commander'

#TODO should be able to grab last arugment and use it as filename/dir
#TODO deal with broken connections on server and client
#TODO gracefully handle ctrl-c

program
  .version('0.1.0')
  .option('--start', 'start the deemon')
  .option('--init', 'iniitialize the project')
  .option('--server', 'point to a non-standard server')
  .parse(process.argv)

server = program.server if program.server else "localhost:4000"
azkaban = new Azkaban server
dementor = new Dementor process.cwd()

if program.init
  azkaban.enable dementor

if program.start
  project.watchFileTree (operation, file, body) ->
    switch operation
      when "add" then azkaban.addFiles [file]
      when "delete" then azkaban.deleteFiles [file]
      when "edit" then azkaban.editFiles {file: body}

#wrap this in a run function and export it for easier testing?
