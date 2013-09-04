{Dementor} = require('./src/dementor')
{HttpClient} = require('./src/httpClient')
{Settings} = require './madeye-common/common'
TunnelManager = require './src/tunnelManager'
util = require 'util'
clc = require 'cli-color'
io = require 'socket.io-client'
{errorType} = require './madeye-common/common'
exec = require("child_process").exec
_s = require 'underscore.string'
{LogListener} = require './madeye-common/common'
constants = require './src/constants'

dementor = null
debug = false
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

  #TODO add tunnel as option
  program
    .version(pkg.version)
    .option('-c --clean', 'Start a new project, instead of reusing an existing one.')
    .option('-d --debug', 'Show debug output (may be noisy)')


    .option('--trace', 'Show trace-level debug output (will be very noisy)')

    .option('--tunnel [port]', "create a tunnel from a public MadEye server to this local port")
    .option('--ignorefile [file]', '.gitignore style file of patterns to not share with madeye (default .madeyeignore)')
    .on("--help", ->
      console.log "  Run madeye in a directory to push its files and subdirectories to madeye.io."
      console.log "  Give the returned url to your friends, and you can edit the project"
      console.log "  simultaneously.  Type ^C to close the session and disable the online project."
    )
  if tty
    program.option('-t --term', 'Share terminal in MadEye session (premium feature)')

  program.parse(process.argv)
  execute
    directory:process.cwd()
    clean: program.clean
    ignorefile: program.ignorefile
    tunnel: program.tunnel
    debug: program.debug
    trace: program.trace
    term: program.term

###
#options:
# directory: path
# clean: bool
# ignorefile: path
# tunnel: integer
# shareOutput: bool
###
execute = (options) ->
  httpClient = new HttpClient Settings.azkabanHost
  socket = io.connect Settings.azkabanUrl
  tunnelManager = new TunnelManager

  debug = options.debug
  logLevel = switch
    when options.trace then 'trace'
    when options.debug then 'debug'
    else 'info'
  listener = new LogListener
    logLevel: logLevel
    onError: (err) ->
      shutdown(err.code ? 1)

  if options.term
    ttyServer = new tty.Server
      cwd: process.cwd()
    ttyServer.listen constants.TERMINAL_PORT, "localhost"

  httpClient = new HttpClient Settings.azkabanUrl
  listener.log 'debug', "Connecting to socketUrl #{Settings.socketUrl}"
  socket = io.connect Settings.socketUrl,
    'resource': 'socket.io' #NB: This must match the server.  Server defaults to 'socket.io'
    'auto connect': false

  #TODO: Refactor dementor to take options
  dementor = new Dementor
    directory: options.directory
    httpClient: httpClient
    socket: socket
    tunnelManager: tunnelManager
    clean: options.clean
    ignorefile: options.ignorefile
    tunnel: options.tunnel
    appPort: options.appPort
    captureViaDebugger: options.captureViaDebugger
    term: options.term

  util.puts "Enabling MadEye in " + clc.bold process.cwd()

  listener.listen dementor, 'dementor'
  listener.listen dementor.projectFiles, 'projectFiles'
  listener.listen dementor.fileTree, 'fileTree'
  listener.listen httpClient, 'httpClient'
  listener.listen tunnelManager, 'tunnelManager'

  dementor.once 'enabled', ->
    apogeeUrl = "#{Settings.apogeeUrl}/edit/#{dementor.projectId}"
    hangoutUrl = "#{Settings.azkabanUrl}/hangout/#{dementor.projectId}"

    util.puts "View your project with MadEye at " + clc.bold apogeeUrl
    util.puts "Use MadEye within a Google Hangout at " + clc.bold hangoutUrl

  dementor.on 'message-warning', (msg) ->
    console.warn clc.bold('Warning:'), msg

  dementor.enable()

  if options.linkToMeteorProcess
    setInterval ->
      getMeteorPid options.appPort, (err, pid)->
        console.log "found meteor pid", pid
        #TODO if metoer process isn't found then exit this process
        #how to best handle a rapid restart...
    , 2000

  process.on 'SIGINT', ->
    console.log clc.blackBright 'Received SIGINT.' if process.env.MADEYE_DEBUG
    shutdown()

  process.on 'SIGTERM', ->
    unless options.linkToMeteorProcess
      console.log clc.blackBright "Received kill signal (SIGTERM)" if process.env.MADEYE_DEBUG
      shutdown()

SHUTTING_DOWN = false

shutdown = (returnVal=0) ->
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


exports.run = run
exports.execute = execute
