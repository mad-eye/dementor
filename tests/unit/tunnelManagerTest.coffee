_ = require 'underscore'
assert = require('chai').assert
sinon = require 'sinon'
{EventEmitter} = require 'events'
TunnelManager = require '../../src/tunnelManager'

describe 'TunnelManager', ->
  createFakeTunnel = (data) ->
    fakeTunnel = new EventEmitter
    fakeTunnel._emitError = (message, options) ->
      err = new Error message
      _.extend err, options
      fakeTunnel.emit 'error', err
      return err
    _.extend fakeTunnel,
      open: sinon.spy()
      close: sinon.spy()
      shutdown: sinon.spy()
    _.extend fakeTunnel, data
    fakeTunnel.name ?= "fake"
    return fakeTunnel
    
  createHookSpies = ->
    close: sinon.spy()
    ready: sinon.spy()
    error: sinon.spy()

  createFakeHome = ->
    clearPublicKeyRegistered: sinon.spy()
    hasAlreadyRegisteredPublicKey: sinon.spy()
    markPublicKeyRegistered: sinon.spy()
    #TODO: This should be a stub that returns keys
    getKeys: sinon.spy()

  describe "startTunnel", ->
    #first error indicates a lack of key on the server
    describe 'on auth error', ->
      tunnelManager = hooks = home = fakeTunnel = null
      beforeEach ->
        home = createFakeHome()
        hooks = createHookSpies()
        fakeTunnel = createFakeTunnel()
        tunnelManager = new TunnelManager {home}
        tunnelManager._makeTunnel = -> fakeTunnel
        tunnelManager.startTunnel {}, hooks
        
      it 'should on the first error call home.clearPublicKeyRegistered && home.getKeys', ->
        fakeTunnel._emitError 'Auth problem!', level: 'authentication'
        assert.isTrue home.clearPublicKeyRegistered.called
        assert.isTrue home.getKeys.called
        
      it 'should on the first error send submit keys request!', ->
        home.hasAlreadyRegisteredPublicKey = sinon.stub()
        home.hasAlreadyRegisteredPublicKey.returns false
        home.getKeys = sinon.stub()
        home.getKeys.callsArgWith 0, null, {'public':'adsf'}
        
        stub = sinon.stub(tunnelManager, "submitPublicKey")
        #Call callback given to submitPublicKey
        stub.callsArg(1)
        fakeTunnel._emitError 'Auth problem!', level: 'authentication'
        assert.isTrue stub.called
        Logger.setLevel 'error'
      
      #two auth errors means something went wrong, bail
      it 'should on the second error call hooks.error with error', ->
        fakeTunnel._emitError 'Auth problem!', level: 'authentication'
        err = fakeTunnel._emitError 'Auth problem 2!', level: 'authentication'
        assert.isTrue hooks.error.called
        assert.deepEqual hooks.error.args[0], [err]

    describe 'on random error', ->
      tunnelManager = hooks = home = fakeTunnel = tunnelData = null
      startTunnelStub = null
      remotePort = 87322
      beforeEach ->
        home = createFakeHome()
        hooks = createHookSpies()
        tunnelData = name: 'fake', localPort: 12399
        tunnelManager = new TunnelManager {home}
        tunnelManager._makeTunnel = (data) ->
          fakeTunnel = createFakeTunnel data
          fakeTunnel.remotePort = remotePort
          return fakeTunnel
        tunnelManager.startTunnel tunnelData, hooks
        startTunnelStub = sinon.stub(tunnelManager, "startTunnel")
        fakeTunnel._emitError 'Unexpected problem!'
        
      it 'should shutdown erroring tunnel', ->
        assert.isTrue fakeTunnel.shutdown.called

      it 'should reconnect a new tunnel with the same data', ->
        assert.isTrue startTunnelStub.called
        calledArgs = startTunnelStub.getCall(0).args
        assert.deepEqual calledArgs[0], tunnelData

      it 'should reconnect a new tunnel with new remoteport', ->
        assert.isTrue startTunnelStub.called
        calledArgs = startTunnelStub.getCall(0).args
        assert.equal calledArgs[0].remotePort, remotePort

      it 'should reconnect a new tunnel with same hooks', ->
        assert.isTrue startTunnelStub.called
        calledArgs = startTunnelStub.getCall(0).args
        assert.equal calledArgs[1], hooks

    describe 'on tunnel close', ->
      tunnelManager = hooks = fakeTunnel = clock = null
      beforeEach ->
        home = createFakeHome()
        tunnelManager = new TunnelManager {home}
        fakeTunnel = createFakeTunnel()
        tunnelManager._makeTunnel = -> fakeTunnel
        hooks = createHookSpies()
        tunnelManager.startTunnel {}, hooks
        clock = null

      afterEach ->
        clock?.restore()

      it 'should set up reconnect if not preceded by an auth error', ->
        #It's called once in startTunnel
        assert.isTrue fakeTunnel.open.calledOnce
        clock = sinon.useFakeTimers()
        fakeTunnel.emit 'close'
        clock.tick 10 * 1000
        #tunnel.open is called once in startTunnel; check for more calls
        #The exact number of additional calls is an implementation detail.
        assert.isTrue fakeTunnel.open.callCount > 1, "Open was called #{fakeTunnel.open.callCount} times"

      it 'should not set reconnect if preceded by an auth error', ->
        #It's called once in startTunnel
        assert.isTrue fakeTunnel.open.calledOnce
        clock = sinon.useFakeTimers()
        fakeTunnel._emitError 'Auth problem!', level: 'authentication'
        fakeTunnel.emit 'close'
        clock.tick 10 * 1000
        #tunnel.open is called once in startTunnel; check for more calls
        #Without reconnect, there should be no additional calls
        assert.isTrue fakeTunnel.open.calledOnce, "Open was called #{fakeTunnel.open.callCount} times"

    describe 'on tunnel ready', ->
      tunnelManager = hooks = fakeTunnel = clock = null
      beforeEach ->
        tunnelManager = new TunnelManager {}
        fakeTunnel = createFakeTunnel()
        tunnelManager._makeTunnel = -> fakeTunnel
        hooks = createHookSpies()
        tunnelManager.startTunnel {}, hooks
        clock = null

      afterEach ->
        clock?.restore()

      it 'should call hooks.ready with remotePort when tunnel emits ready with remotePort', ->
        fakeTunnel.emit 'ready', 1234
        assert.isTrue hooks.ready.calledOnce
        assert.deepEqual hooks.ready.args[0], [1234]

      it 'should clear reconnect started by tunnel close', (done) ->
        clock = sinon.useFakeTimers()
        fakeTunnel.emit 'close' #this will cause the tunnel to start trying to reconnect
        hooks.ready = ->
          clock.tick 30 * 1000
          #tunnel.open is called on tunnelManager.startTunnel.
          #It should be not called again because the reconnect timeout is cleared
          assert.isTrue fakeTunnel.open.calledOnce
          done()
        fakeTunnel.emit 'ready'

  describe 'shutdown', ->
    it 'should call shutdown on all tunnels', (done) ->
      tunnelManager = new TunnelManager {}
      tunnel1 = shutdown: sinon.spy()
      tunnel2 = shutdown: sinon.spy()
      tunnelManager.tunnels['1'] = tunnel1
      tunnelManager.tunnels['2'] = tunnel2
      
      tunnelManager.shutdown ->
        assert.isTrue tunnel1.shutdown.called
        assert.isTrue tunnel2.shutdown.called
        done()
      
