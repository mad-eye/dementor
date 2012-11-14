fs = require 'fs'
{exec} = require 'child_process'

task "test", "Run all the tests", ->
  #TODO figure out a less hacky way to find all the tests to run
  exec """find test -name '*Test.coffee' |
  xargs node_modules/mocha/bin/mocha --compilers coffee:coffee-script""",
    (error, stdout, stderr) ->
      console.error error if error
      console.log "stdout #{stdout}" if stdout
      console.log "stderr #{stderr}" if stderr
