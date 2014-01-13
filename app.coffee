Dementor = require './src/dementor'
DdpClient = require './src/ddpClient'
TunnelManager = require './src/tunnelManager'
Home = require './src/home'
Logger = require 'pince'
util = require 'util'
clc = require 'cli-color'
exec = require("child_process").exec
_s = require 'underscore.string'
Constants = require './constants'

dementor = null
debug = false
log = new Logger name:'app'
Logger.onError (msgs) ->
  msgs.unshift clc.red('ERROR:')
  console.error.apply console, msgs
  shutdown(1)
  #Don't print standard error log output
  return false

try
  tty = require './ttyjs'
catch e
  log.debug "tty not loaded due to error:", e
  #No tty.js, so no terminal for you!

getMeteorPid = (meteorPort, callback)->
  cmd = """lsof -n -i4TCP:#{meteorPort} | grep LISTEN | awk '{print $2}'"""
  exec cmd, (err, stdout, stderr)->
    callback null, _s.trim(stdout)

run = (Settings) ->
  #Check to see if we are already in a madeye session -- don't cross the streams!
  if process.env.MADEYE_ACTIVE
    console.error "You are already in the terminal of a MadEye session!"
    console.error "Too far down that path lies Limbo..."
    console.error "Quit your existing MadEye session by pressing ^D."
    process.exit 1

  program = require 'commander'

  #TODO should be able to grab last arugment and use it as filename/dir

  pkg = require './package.json'

  program
    .version(pkg.version)
    .option('-c --clean', 'Start a new project, instead of reusing an existing one.')
    #.option('--madeyeUrl [url]', 'url to point to (instead of https://madeye.io)')
    .option('-d --debug', 'Show debug output (may be noisy)')
    .option('--trace', 'Show trace-level debug output (will be very noisy)')

    .option('--tunnel [port]', "create a tunnel from a public MadEye server to this local port")
    .option('--ignorefile [file]', '.gitignore style file of patterns to not share with madeye (default .madeyeignore)')
    .on("--help", ->
      console.log "  Run madeye in a directory to push its files and subdirectories to madeye.io."
      console.log "  Give the returned url to your friends, and you can edit the project"
      console.log "  simultaneously.  Type ^C to close the session and disable the online project."
    )
  #For now, hide this option unless there is MADEYE_TERM
  if tty
    program.option('-t --terminal', 'Share your terminal output with MadEye (read-only)')
    if process.env.MADEYE_FULL_TERMINAL
      program.option('-f --fullTerminal', 'Share a read/write terminal within MadEye (premium feature)')

  program.parse(process.argv)

  log.trace "Found args", program.args
  if program.args[0] == 'update'
    updateMadeye Settings
  else
    execute
      directory: process.cwd()
      clean: program.clean
      ignorefile: program.ignorefile
      tunnel: program.tunnel
      debug: program.debug
      trace: program.trace
      terminal: program.terminal
      fullTerminal: program.fullTerminal
      settings: Settings

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

  Settings = options.settings

  ddpClient = new DdpClient
    host: Settings.ddpHost
    port: Settings.ddpPort
  ddpClient.on 'message-warning', (msg) ->
    console.warn clc.bold('Warning:'), msg

  home = new Home options.directory
  home.init()

  tunnelManager = new TunnelManager {tunnelHost:Settings.tunnelHost, home, azkabanUrl:Settings.azkabanUrl}
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
    home: home


  dementor.once 'enabled', ->
    projectUrl = "#{Settings.apogeeUrl}/edit/#{dementor.projectId}"
    hangoutUrl = "#{Settings.azkabanUrl}/hangout/#{dementor.projectId}"

    util.puts "View your project with MadEye at " + clc.bold projectUrl
    util.puts "Use MadEye within a Google Hangout at " + clc.bold hangoutUrl

  dementor.once 'webTunnel enabled', (port) ->
    util.puts "You are sharing port " + clc.bold(options.tunnel) +
      " at " + clc.bold("#{Settings.tunnelHost}:#{port}")

  dementor.once 'terminal enabled', (port) ->
    #TODO: Clean this up.
    #Show tty output on debug or trace loglevel.
    ttyLog = options.debug || options.trace || false

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
        commands: ['export MADEYE_ACTIVE=1']

      ttyServer.on 'exit', ->
        console.log("Exiting MadEye. Restart your session with `madeye --terminal`")
        shutdown()

      ttyServer.listen Constants.LOCAL_TUNNEL_PORT, "localhost"

    if options.fullTerminal
      ttyServer = new tty.Server
        readonly: false
        cwd: process.cwd()
        log: ttyLog

      ttyServer.listen Constants.LOCAL_TUNNEL_PORT, "localhost"

  dementor.on 'message-warning', (msg) ->
    #TODO: Clean up this hackery
    return if logLevel == 'error'
    console.warn clc.bold('Warning:'), msg
  dementor.on 'message-info', (msg) ->
    #TODO: Clean up this hackery
    return if logLevel == 'error' or logLevel == 'warn'
    console.log msg

  dementor.on 'VersionOutOfDate', (err) ->
    console.warn clc.bold('Warning:'), "Your version of MadEye is out of date; we'll update it."
    updateMadeye Settings, (err) ->
      unless err
        console.log "Please rerun the new and improved MadEye!"
        shutdown()


  dementor.enable()

  if options.linkToMeteorProcess
    setInterval ->
      getMeteorPid options.appPort, (err, pid)->
        console.log "found meteor pid", pid
        #TODO if meteor process isn't found then exit this process
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
    log.debug "Closed out connections."
    console.log "Shutdown completed."
    process.exit returnVal

  setTimeout ->
    console.error "Could not close connections in time, shutting down harder."
    process.exit(returnVal || 1)
  , 20*1000

#callback: (err) ->
updateMadeye = (Settings, callback=->) ->
  log.debug "Updating MadEye"
  exec "curl '#{Settings.apogeeUrl}/install' | sh", {}, (err, stdout, stderr) ->
    log.debug stdout if stdout
    if err
      message = error.details ? error.message ? error
      log.error message
    else
      console.log "MadEye successfully updated."
    callback err

exports.run = run
exports.execute = execute
