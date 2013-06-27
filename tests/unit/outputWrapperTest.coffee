{assert} = require 'chai'
_ = require 'underscore'
uuid = require 'node-uuid'
sinon = require 'sinon'
{hook_stdout, hook_stderr} = require '../../src/hookOutputs'
OutputWrapper = require '../../src/outputWrapper'

describe 'outputHooks', ->
  describe 'hook_stdout', ->
    unhook = null
    outputs = []
    before ->
      unhook = hook_stdout (chunk, encoding) ->
        outputs.push chunk
    after ->
      unhook()

    it 'should hook stdout', ->
      testChunk = 'asdfo1232139iafslkj'
      console.log testChunk
      assert.ok "#{testChunk}\n" in outputs

  describe 'hook_stderr', ->
    unhook = null
    outputs = []
    before ->
      unhook = hook_stderr (chunk, encoding) ->
        outputs.push chunk
    after ->
      unhook()

    it 'should hook stderr', ->
      testChunk = 'asdfiasdfk3'
      console.error testChunk
      assert.ok "#{testChunk}\n" in outputs


describe 'OutputWrapper', ->
  outputWrapper = null
  projectId = uuid.v4()
  ddpCalls = null
  before ->
    outputWrapper = new OutputWrapper projectId:projectId
    outputWrapper.ddpClient.call = ->
      ddpCalls.push _.toArray(arguments)

  beforeEach ->
    ddpCalls = []

  after ->
    outputWrapper.shutdown()

  it 'should call ddpClient on stdout output', ->
    outputWrapper.initialize()
    testStr = 'oosfgk23a'
    console.log testStr
    assert.deepEqual ddpCalls[0][0..1], ['output', [projectId, 'stdout', testStr + '\n']]

  it 'should call ddpClient on stderr output', ->
    outputWrapper.initialize()
    testStr = 'oosfgo1012312-- '
    console.error testStr
    assert.deepEqual ddpCalls[0][0..1], ['output', [projectId, 'stderr', testStr + '\n']]



