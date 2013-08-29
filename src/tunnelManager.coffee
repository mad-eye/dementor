events = require 'events'
{spawn} = require 'child_process'

class TunnelManager extends events.EventEmitter
  constructor: ->
    #npm installs this with the wrong permissions.
    fs.chmodSync "#{__dirname}/../lib/id_rsa", "400"
    @tunnels = {}

  startTunnel: (options)->
    tunnel = name: options.name, local: options.local
    #TODO: Allow -v option on debug level logging?
    ssh_cmd = "ssh -tt -i #{__dirname}/../lib/id_rsa -N -R #{options.remote}:127.0.0.1:#{options.local} -o StrictHostKeyChecking=no ubuntu@#{shareServer}"
    #console.log ssh_cmd

    tunnel.process = proc = spawn ssh_cmd
    proc.stderr.on 'data', (data) ->
      console.log "[#{tunnel.name} stderr]", data
      
    proc.stdout.on 'data', (data) ->
      console.log "[#{tunnel.name} stdout]", data
      
    proc.on 'close', (code) ->
      console.log "ssh ended with code #{code}"
