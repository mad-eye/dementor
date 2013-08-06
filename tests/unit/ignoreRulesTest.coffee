{assert} = require 'chai'
IgnoreRules = require '../../src/ignoreRules'

describe 'ignoreRules', ->
  describe 'parsing', ->
    it 'should ignore empty lines', ->
      rulesStr = ['','','a',''].join '\n'
      ignoreRules = new IgnoreRules rulesStr
      assert.isTrue ignoreRules.shouldIgnore 'a'
      assert.isFalse ignoreRules.shouldIgnore 'b'
    it 'should skip comments', ->
      rulesStr = ['#b','a'].join '\n'
      ignoreRules = new IgnoreRules rulesStr
      assert.isTrue ignoreRules.shouldIgnore 'a'
      assert.isFalse ignoreRules.shouldIgnore 'b'
    it 'should accept a single line text', ->
      ignoreRules = new IgnoreRules 'a'
      assert.isTrue ignoreRules.shouldIgnore 'a'
      assert.isFalse ignoreRules.shouldIgnore 'b'
    it 'should match whole rule', ->
      ignoreRules = new IgnoreRules 'a'
      assert.isTrue ignoreRules.shouldIgnore 'a'
      assert.isFalse ignoreRules.shouldIgnore 'ab'
      assert.isFalse ignoreRules.shouldIgnore 'ba'

  describe 'glob patterns', ->
    it 'matches * correctly fweep', ->
      ignoreRules = new IgnoreRules '*.txt'
      assert.isTrue ignoreRules.shouldIgnore('a.txt')
      assert.isFalse ignoreRules.shouldIgnore('a.js'), 'Should not match a.js'
      assert.isFalse ignoreRules.shouldIgnore('a'), 'Should not match a'
      assert.isTrue ignoreRules.shouldIgnore('foo/a.txt')

    it 'matches ** correctly', ->
      ignoreRules = new IgnoreRules 'foo/**/*.txt'
      assert.isFalse ignoreRules.shouldIgnore('a.txt')
      assert.isTrue ignoreRules.shouldIgnore('foo/a.txt')
      assert.isTrue ignoreRules.shouldIgnore('foo/bar/a.txt')
      assert.isTrue ignoreRules.shouldIgnore('foo/bar/baz/a.txt')
      assert.isTrue ignoreRules.shouldIgnore('foo/bar/baz/biff/a.txt')
      assert.isFalse ignoreRules.shouldIgnore('bar/a.txt')

    it 'matches [ab] correctly', ->
      ignoreRules = new IgnoreRules '[ab]c.txt'
      assert.isTrue ignoreRules.shouldIgnore('ac.txt'), 'Should match ac.txt'
      assert.isTrue ignoreRules.shouldIgnore('bc.txt'), 'Should match bc.txt'
      assert.isFalse ignoreRules.shouldIgnore('ab.txt'), 'Should not match ab.txt'
      assert.isFalse ignoreRules.shouldIgnore('a.txt'), 'Should not match a.txt'
      assert.isFalse ignoreRules.shouldIgnore('c.txt'), 'Should not match c.txt'
      assert.isFalse ignoreRules.shouldIgnore('abc.txt'), 'Should not match abc.txt'
      assert.isFalse ignoreRules.shouldIgnore('dc.txt'), 'Should not match dc.txt'

    it 'matches [a-c] correctly', ->
      ignoreRules = new IgnoreRules '[a-c]d.txt'
      assert.isTrue ignoreRules.shouldIgnore('ad.txt'), 'Should match ad.txt'
      assert.isTrue ignoreRules.shouldIgnore('bd.txt'), 'Should match bd.txt'
      assert.isTrue ignoreRules.shouldIgnore('cd.txt'), 'Should match cd.txt'
      assert.isFalse ignoreRules.shouldIgnore('ed.txt'), 'Should not match ed.txt'
      assert.isFalse ignoreRules.shouldIgnore('ab.txt'), 'Should not match ab.txt'
      assert.isFalse ignoreRules.shouldIgnore('d.txt'), 'Should not match d.txt'
      assert.isFalse ignoreRules.shouldIgnore('c.txt'), 'Should not match c.txt'
      assert.isFalse ignoreRules.shouldIgnore('abd.txt'), 'Should not match abc.txt'

    it 'matches ? correctly', ->
      ignoreRules = new IgnoreRules '?d.txt'
      assert.isTrue ignoreRules.shouldIgnore('ad.txt'), 'Should match ad.txt'
      assert.isTrue ignoreRules.shouldIgnore('bd.txt'), 'Should match bd.txt'
      assert.isTrue ignoreRules.shouldIgnore('9d.txt'), 'Should match 9d.txt'
      assert.isFalse ignoreRules.shouldIgnore('ab.txt'), 'Should not match ab.txt'
      assert.isFalse ignoreRules.shouldIgnore('a.txt'), 'Should not match a.txt'
      assert.isFalse ignoreRules.shouldIgnore('c.txt'), 'Should not match c.txt'
      assert.isFalse ignoreRules.shouldIgnore('abd.txt'), 'Should not match abc.txt'

  describe 'dir slashes', ->
    it 'matches directories and contents on trailing /'
      #ignoreRules = new IgnoreRules 'foo/'
      #assert.isTrue ignoreRules.shouldIgnore('foo/a.txt'), 'Should ignore directory contents'
      #assert.isTrue ignoreRules.shouldIgnore 'foo/bar/b.txt'
      #assert.isTrue ignoreRules.shouldIgnore 'bar/foo/b.txt'
      #assert.isFalse ignoreRules.shouldIgnore 'a.txt'

    it 'matches only top-level files on leading /', ->
      ignoreRules = new IgnoreRules '/TODO'
      assert.isTrue ignoreRules.shouldIgnore('TODO'), 'Should ignore top-level TODO'
      assert.isFalse ignoreRules.shouldIgnore('foo/TODO'), 'Should not ignore deeper TODO'
      assert.isFalse ignoreRules.shouldIgnore 'NotTODO'
      

  describe 'negation', ->
    it 'negates a pattern starting with a !', ->
      ignoreRules = new IgnoreRules '*.txt\n!a.txt'
      assert.isFalse ignoreRules.shouldIgnore('a.txt'), 'Should match a.txt'
      assert.isTrue ignoreRules.shouldIgnore('c.txt'), 'Should not match c.txt'

    it 'negates a pattern starting with !/', ->
      ignoreRules = new IgnoreRules '**/*.txt\n!/a.txt'
      assert.isFalse ignoreRules.shouldIgnore('a.txt'), 'Should match a.txt'
      assert.isTrue ignoreRules.shouldIgnore('c.txt'), 'Should not match c.txt'
      assert.isTrue ignoreRules.shouldIgnore('foo/a.txt'), 'Should not match foo/a.txt'
      assert.isTrue ignoreRules.shouldIgnore('foo/c.txt'), 'Should not match foo/c.txt'




