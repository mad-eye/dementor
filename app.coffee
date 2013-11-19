Dementor = require './src/dementor'
DdpClient = require './src/ddpClient'
TunnelManager = require './src/tunnelManager'
{Settings} = require './madeye-common/common'
Logger = require 'pince'
util = require 'util'
clc = require 'cli-color'
exec = require("child_process").exec
_s = require 'underscore.string'
Constants = require './constants'

dementor = null
debug = false
log = new Logger name:'app'

try
  tty = require 'tty.js'
catch e
  #No tty.js, so no terminal for you!

getMeteorPid = (meteorPort, callback)->
  cmd = """lsof -n -i4TCP:#{meteorPort} | grep LISTEN | awk '{print $2}'"""
  exec cmd, (err, stdout, stderr)->
    callback null, _s.trim(stdout)

run = ->
  program = require 'commander'

  #TODO should be able to grab last arugment and use it as filename/dir

  pkg = require './package.json'

  program
    .version(pkg.version)
    .option('-c --clean', 'Start a new project, instead of reusing an existing one.')
    .option('--madeyeUrl [url]', 'url to point to (instead of madeye.io)')
    .option('-d --debug', 'Show debug output (may be noisy)')
    .option('--trace', 'Show trace-level debug output (will be very noisy)')

#    .option('--tunnel [port]', "create a tunnel from a public MadEye server to this local port")
    .option('--ignorefile [file]', '.gitignore style file of patterns to not share with madeye (default .madeyeignore)')
    .on("--help", ->
      console.log "  Run madeye in a directory to push its files and subdirectories to madeye.io."
      console.log "  Give the returned url to your friends, and you can edit the project"
      console.log "  simultaneously.  Type ^C to close the session and disable the online project."
    )
  #For now, hide this option unless there is MADEYE_TERM
  if tty and process.env.MADEYE_TERM
    program.option('-t --terminal', 'Share your terminal output with MadEye (read-only)')
    if process.env.MADEYE_FULL_TERMINAL
      program.option('-f --fullTerminal', 'Share a read/write terminal within MadEye (premium feature)')

  program.parse(process.argv)
  execute
    directory:process.cwd()
    clean: program.clean
    ignorefile: program.ignorefile
    tunnel: program.tunnel
    debug: program.debug
    trace: program.trace
    terminal: program.terminal
    fullTerminal: program.fullTerminal
    madeyeUrl: program.madeyeUrl

###
#options:
# directory: path
# clean: bool
# ignorefile: path
# tunnel: integer
# debug: bool
# trace: bool
# term: bool
# madeyeUrl: string
###
execute = (options) ->
  logLevel = switch
    when options.trace then 'trace'
    when options.debug then 'debug'
    when options.term then 'warn'
    else 'info'

  Logger.setLevel logLevel
  Logger.onError (msgs...) ->
    msgs.unshift clc.red('ERROR:')
    console.error.apply console, msgs
    shutdown(1)
    #Don't print standard error log output
    return false

  log.trace "Checking madeyeUrl: #{options.madeyeUrl}"
  if options.madeyeUrl
    apogeeUrl = options.madeyeUrl
    azkabanUrl = "#{options.madeyeUrl}/api"
    parsedUrl = require('url').parse options.madeyeUrl

  log.trace "Checking madeyeUrl switch: #{options.madeyeUrl}"
  log.trace "Checking MADEYE_URL: #{process.env.MADEYE_URL}"
  log.trace "Checking MADEYE_BASE_URL: #{process.env.MADEYE_BASE_URL}"
  madeyeUrl = options.madeyeUrl ?
    process.env.MADEYE_URL ?
    process.env.MADEYE_BASE_URL
  log.debug "Using madeyeUrl", madeyeUrl

  if madeyeUrl
    apogeeUrl = madeyeUrl
    azkabanUrl = "#{madeyeUrl}/api"
    parsedUrl = require('url').parse madeyeUrl
    ddpPort = switch
      when parsedUrl.port then parsedUrl.port
      when parsedUrl.protocol == 'http:' then 80
      when parsedUrl.protocol == 'https:' then 443
      else log.error "Can't figure out port for url #{madeyeUrl}"
    ddpHost = parsedUrl.hostname
  else
    apogeeUrl = Settings.apogeeUrl
    azkabanUrl = Settings.azkabanUrl
    ddpHost = Settings.ddpHost
    ddpPort = Settings.ddpPort

  #FIXME: Need to handle custom case differently?
  tunnelHost = Settings.tunnelHost

  #Show tty output on debug or trace loglevel.
  ttyLog = options.debug || options.trace || false
  if options.fullTerminal
    ttyServer = new tty.Server
      readonly: false
      cwd: process.cwd()
      log: ttyLog

    ttyServer.listen Constants.LOCAL_TUNNEL_PORT, "localhost"

  ddpClient = new DdpClient
    host: ddpHost
    port: ddpPort
  ddpClient.on 'message-warning', (msg) ->
    console.warn clc.bold('Warning:'), msg


  tunnelManager = new TunnelManager tunnelHost
  Logger.listen tunnelManager, 'tunnelManager'


  if options.fullTerminal
    term = "readWrite"
  else if options.terminal
    term = "readOnly"
  else
    term = null
  dementor = new Dementor
    directory: options.directory
    ddpClient: ddpClient
    tunnelManager: tunnelManager
    clean: options.clean
    ignorefile: options.ignorefile
    tunnel: options.tunnel
    appPort: options.appPort
    captureViaDebugger: options.captureViaDebugger
    term: term


  dementor.once 'enabled', ->
    apogeeUrl = "#{apogeeUrl}/edit/#{dementor.projectId}"
    hangoutUrl = "#{azkabanUrl}/hangout/#{dementor.projectId}"

    util.puts "View your project with MadEye at " + clc.bold apogeeUrl
    util.puts "Use MadEye within a Google Hangout at " + clc.bold hangoutUrl

  dementor.once 'terminalEnabled', ->
    #read only terminal has to wait until madeye/hangout links have been displayed
    if options.terminal
      util.puts ""
      util.puts "################################################################################"
      util.puts "## MadEye Terminal    ##########################################################"
      util.puts "################################################################################"
      util.puts ""
      util.puts "Anything output from this terminal will be shared within in your MadEye session."
      util.puts "The shared terminal is read-only. Only you can type commands at this shell"
      util.puts "To exit this shell and end your MadEye session type exit"
      util.puts ""
      util.puts "Setting prompt to reflect that you are in a MadEye session"

      ttyServer = new tty.Server
        readonly: true
        cwd: process.cwd()
        log: ttyLog
        prompt: "$PS1(madeye) "

      ttyServer.on 'exit', ->
        console.log "the tty server has exited"
        shutdown()

      ttyServer.listen Constants.LOCAL_TUNNEL_PORT, "localhost"

  dementor.on 'message-warning', (msg) ->
    #TODO: Clean up this hackery
    return if logLevel == 'error'
    console.warn clc.bold('Warning:'), msg
  dementor.on 'message-info', (msg) ->
    #TODO: Clean up this hackery
    return if logLevel == 'error' or logLevel == 'warn'
    console.log msg

  dementor.enable()

  if options.linkToMeteorProcess
    setInterval ->
      getMeteorPid options.appPort, (err, pid)->
        console.log "found meteor pid", pid
        #TODO if metoer process isn't found then exit this process
        #how to best handle a rapid restart...
    , 2000

  process.on 'SIGINT', ->
    log.debug 'Received SIGINT.'
    shutdown()

  process.on 'SIGTERM', ->
    unless options.linkToMeteorProcess
      log.debug "Received kill signal (SIGTERM)"
      shutdown()

SHUTTING_DOWN = false

shutdown = (returnVal=0) ->
  log.trace "Shutdown called with exit value #{returnVal}"
  process.exit(returnVal || 1) if SHUTTING_DOWN # || not ?, because we don't want 0
  process.nextTick ->
    shutdownGracefully(returnVal)

shutdownGracefully = (returnVal=0) ->
  return if SHUTTING_DOWN
  SHUTTING_DOWN = true
  console.log "Shutting down MadEye.  Press ^C to force shutdown."
  dementor.shutdown ->
    console.log "Closed out connections."
    process.exit returnVal

  setTimeout ->
    console.error "Could not close connections in time, shutting down harder."
    process.exit(returnVal || 1)
  , 20*1000

process.on 'SIGINT', ->
  log.debug 'Received SIGINT.'
  shutdown()

process.on 'SIGTERM', ->
  log.debug "Received kill signal (SIGTERM)"
  shutdown()

exports.run = run
exports.execute = execute
