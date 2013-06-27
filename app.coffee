{Dementor} = require('./src/dementor')
{HttpClient} = require('./src/httpClient')
OutputWrapper = require './src/outputWrapper'
{Settings} = require './madeye-common/common'
util = require 'util'
clc = require 'cli-color'
io = require 'socket.io-client'
{errorType} = require './madeye-common/common'

dementor = null

run = ->
  program = require 'commander'

  #TODO should be able to grab last arugment and use it as filename/dir

  pkg = require './package.json'

  program
    .version(pkg.version)
    .option('-c --clean', 'Start a new project, instead of reusing an existing one.')
    .option('--ignorefile [file]', '.gitignore style file of patterns to not share with madeye (default .madeyeignore)')
    .on("--help", ->
      console.log "  Run madeye in a directory to push its files and subdirectories to madeye.io."
      console.log "  Give the returned url to your friends, and you can edit the project"
      console.log "  simultaneously.  Type ^C to close the session and disable the online project."
    )
  program.parse(process.argv)
  execute
    directory:process.cwd()
    clean: program.clean
    ignorefile: program.ignorefile
    tunnel: program.tunnel


###
#options:
# directory: path
# clean: bool
# ignorefile: path
# tunnel: bool
# shareOutput: bool
###
execute = (options) ->
  httpClient = new HttpClient Settings.azkabanHost
  socket = io.connect Settings.azkabanUrl,
    'resource': 'socket.io' #NB: This must match the server.  Server defaults to 'socket.io'
    'auto connect': false
  
  #TODO: Refactor dementor to take options
  dementor = new Dementor options.directory, httpClient, socket, options.clean, options.ignorefile, options.tunnel, options.appPort
  util.puts "Enabling MadEye in " + clc.bold process.cwd()

  logEvents dementor
  logEvents dementor.projectFiles


  dementor.once 'enabled', ->
    apogeeUrl = "#{Settings.apogeeUrl}/edit/#{dementor.projectId}"
    hangoutUrl = "#{Settings.azkabanUrl}/hangout/#{dementor.projectId}"

    util.puts "View your project with MadEye at " + clc.bold apogeeUrl
    util.puts "Use MadEye within a Google Hangout at " + clc.bold hangoutUrl

    if options.shareOutput
      outputWrapper = new OutputWrapper projectId: dementor.projectId, host: Settings.apogeeDDPHost, port: Settings.apogeePort
      logEvents outputWrapper
      outputWrapper.on 'error', ->
        outputWrapper.shutdown()
      outputWrapper.connect (err) ->
        console.error clc.red('ERROR:'), "Failed to connect to share output: #{err.message}"
        
  dementor.enable()



  #hack for dealing with exceptions caused by broken links
  process.on 'uncaughtException', (err)->
    if err.code == "ENOENT"
      #Silence the error for now
      #console.log "File does not exist #{err.path}"
      0
    else
      throw err

  #FIXME: Need to listen to projectFiles error, warn, info, and debug events

logEvents = (emitter) ->
  if emitter
    emitter.on 'error', (err) ->
      console.error err
      console.error clc.red('ERROR:'), err.message
      shutdown(err.code ? 1)

    emitter.on 'warn', (message) ->
      console.error clc.bold('Warning:'), message

    emitter.on 'info', (message) ->
      console.log message

    emitter.on 'debug', (message) ->
      console.log clc.blackBright message if process.env.MADEYE_DEBUG

# Shutdown section
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

process.on 'SIGINT', ->
  #console.log clc.blackBright 'Received SIGINT.' if process.env.MADEYE_DEBUG
  shutdown()

process.on 'SIGTERM', ->
  #console.log clc.blackBright "Received kill signal (SIGTERM)" if process.env.MADEYE_DEBUG
  shutdown()

exports.run = run
exports.execute = execute
