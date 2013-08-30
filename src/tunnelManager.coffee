events = require 'events'
{spawn, exec} = require 'child_process'
fs = require 'fs'
_path = require 'path'

ID_FILE_PATH = _path.normalize "#{__dirname}/../lib/id_rsa"
assignedPortRegex = /Allocated port (\d+) for remote forward/

class TunnelManager extends events.EventEmitter
  constructor: ->
    @emit 'trace', 'Constructing TunnelManager'
    #npm installs this with the wrong permissions.
    fs.chmodSync ID_FILE_PATH, "400"
    @tunnels = {}
    @processes = {}
    @shuttingDown = false
    @shareServer = process.env.MADEYE_SHARE_SERVER or "share.madeye.io"

  #callback: (err, tunnel) ->
  startTunnel: (options, callback)->
    @emit 'debug', "Starting tunnel #{options.name} for local port #{options.local}"
    options.remote ?= 0
    name = options.name
    tunnel = name: name, local: options.local

    ssh_args = [
      #"-v", #TODO: Allow -v option on debug level logging?
      "-tt",
      "-i",
      ID_FILE_PATH,
      "-N",
      "-R #{options.remote}:127.0.0.1:#{options.local}",
      "-o StrictHostKeyChecking=no",
      "ubuntu@#{@shareServer}"
    ]
    @emit 'trace', "ssh " + ssh_args.join(" ")

    @processes[name] = proc = spawn "ssh", ssh_args

    proc.stderr.on 'data', (data) =>
      data = '' + data
      console.log "[#{name} stderr] " + data
      if match = assignedPortRegex.exec data
        @emit 'trace', "Found match", match
        port = parseInt(match[1], 10)
        @emit 'debug', "Found port #{port} for #{name}"
        tunnel.remote = port
        callback null, tunnel


    proc.stdout.on 'data', (data) ->
      console.log "[#{name} stdout] " + data
      #TODO: Get the assigned port number, add it to tunnel, do callback

    proc.on 'close', (code) =>
      @emit 'debug', "ssh for tunnel #{name} ended with code #{code}"
      if @shuttingDown
        delete @tunnels[name]
      else
        @emit 'error', "Tunnel #{name} closed with code #{code}"
        #TODO: reconnect


  shutdown: ->
    @emit 'trace', 'Shutting down TunnelManager'
    @shuttingDown = true
    for name, proc in @processes
      @emit 'trace', "Killing tunnel #{name}"
      proc.process.kill()

module.exports = TunnelManager
