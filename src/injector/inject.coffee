exec = require('child_process').exec
uuid = require 'node-uuid' 
fs = require 'fs'
_ = require 'underscore'
EventEmitter = require("events").EventEmitter

outputWatcher = new EventEmitter

connectDebugger = (port, callback)->
  #debugger is a reserved word
  theDebugger = require("./node-inspector-debugger/debugger.js").attachDebugger(5858)

  theDebugger.on "break", (event)->
    #if breakpoints are hit for whatever reason just continue
    theDebugger.request "continue"

  theDebugger.on "connect", ->
    outputWatcher.emit "connect"
    callback(theDebugger)
    wrapStdOut()
    setTimeout clearBuffer, 2500

  theDebugger.on "error", (error)->
    #TODO this looks broken..
    callback(outputWatcher)
    outputWatcher.emit "connect"

  theDebugger.on "end", ->
    console.log("Debugger disconnected")

  wrapStdOut = ->
    injectScript fs.readFileSync("#{__dirname}/captureOutputStreams.js", "utf-8"), (result)->
      # console.log "STDOUT result", result

  clearBuffer = ->
    # console.log "clearing out buffers"
    injectScript fs.readFileSync("#{__dirname}/flushOutputBuffer.js", "utf-8"), (result)->
      if result.body.text != ""
        #TODO add ddp stuff here
        # this line useful for debugging
        # fs.appendFile "/tmp/log.txt", result.body.text, ->
        clearBuffer()
      else
        #console.log "no new text"
        setTimeout ->
          clearBuffer()
        , 4000

  injectScript = (script, callback)->
#    console.log("INJECT SCRIPT", script);
    theDebugger.request "evaluate",
      arguments:
        expression: script
        global: true
        disable_break: true
      callback


#TODO leave hacky logic to find port somewhere else so this can be tested nicely
exports.captureProcessOutput = (pid)->
  # console.log "METEOR PID", pid
  #TODO better handle this error
  throw "UNKNOWN PID" unless pid
  process.kill pid, "SIGUSR1"
  connectDebugger 3000, (outputWatcher)->
    outputWatcher.on "connect", ->
      #TODO figure out why this isn't being called
      console.log "CONNECTED"
