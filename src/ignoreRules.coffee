_ = require 'underscore'
_.str = require 'underscore.string'
{Minimatch} = require 'minimatch'

MINIMATCH_OPTIONS = { matchBase: true, dot: true, flipNegate: true }

base_excludes = '''
*~
#*#
.#*
%*%
._*
*.swp
*.swo
CVS
SCCS
.svn
.git
.bzr
.hg
_MTN
_darcs
.meteor
.build
node_modules
.DS_Store
.DS_Store?
._*
.Spotlight-V100
.Trashes
Icon?
ehthumbs.db
Thumbs.db
*.class
*.o
*.a
*.pyc
*.pyo'''.split(/\r?\n/)

BASE_IGNORE_RULES = (new Minimatch(rule, MINIMATCH_OPTIONS) for rule in base_excludes when rule)

class TopLevelMatch
  constructor: (@pattern) ->
    @regexp = new RegExp "^" + pattern + "$"

  match: (path) ->
    @regexp.test path

class IgnoreRules
  constructor: (rulesStr) ->
    #copy so that other instances of IgnoreRules don't alter BASE_IGNORE_RULES
    @rules = BASE_IGNORE_RULES[..]
    @negations = []
    return unless rulesStr

    rawRules = (rule.trim() for rule in _.str.lines(rulesStr) when rule)
    rawRules = _.filter rawRules, (rule) ->
      rule && rule[0] != '#'

    for rule in rawRules
      if _.str.endsWith rule, '/'
        #git ignores directories but not files.
        #Just ignore everything
        rule = rule.substr 0, rule.length - 1
      
      if rule.charAt(0) == '/'
        @rules.push new TopLevelMatch rule.substr 1
      else if rule.substr(0,2) == '!/'
        @negations.push new TopLevelMatch rule.substr 2
      else
        minimatch = new Minimatch(rule, MINIMATCH_OPTIONS)
        unless minimatch.negate
          @rules.push minimatch
        else
          @negations.push minimatch

  shouldIgnore: (path) ->
    return true unless path?
    if _.some(@rules, (rule) -> rule.match path)
      return true unless _.some @negations, (rule) -> rule.match path
    return false



module.exports = IgnoreRules
