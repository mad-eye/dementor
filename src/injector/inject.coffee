exec = require('child_process').exec
uuid = require 'node-uuid' 
fs = require 'fs'
_ = require 'underscore'
EventEmitter = require("events").EventEmitter

outputWatcher = new EventEmitter

getMeteorPid = (meteorPort, callback)->
  #make sure to test w/ and w/o explicit port

  # console.log "fetching meteor pid"
  cmd = """ps ax | grep "tools/meteor.js" | grep -v "grep" | awk '{ print $1 }' """
  # console.log "COMMAND", cmd
  exec cmd, (err, stdout, stderr)->
    callback null, stdout.split("\n")[0]

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
        # console.log "GOT TEXT", result.body.text
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
  getMeteorPid 3000, (error, pid)->
    # console.log "METEOR PID", pid
    #TODO better handle this error
    throw "UNKNOWN PID" unless pid
    process.kill pid, "SIGUSR1"
    connectDebugger 3000, (outputWatcher)->
      outputWatcher.on "connect", ->
        #TODO figure out why this isn't being called
        console.log "CONNECTED"
    #callback with attached debugger?

exports.captureProcessOutput()