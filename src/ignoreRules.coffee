_ = require 'underscore'
_.str = require 'underscore.string'
{Minimatch} = require 'minimatch'
#{RelPathSpec, RelPathList} = require('pathspec')

MINIMATCH_OPTIONS = { matchBase: true, dot: true, flipNegate: true }

class TopLevelMatch
  constructor: (@pattern) ->
    @regexp = new RegExp "^" + pattern + "$"

  match: (path) ->
    @regexp.test path

class IgnoreRules
  constructor: (rulesStr) ->
    @rules = []
    @negations = []
    return unless rulesStr

    rawRules = (rule.trim() for rule in _.str.lines(rulesStr) when rule)
    rawRules = _.filter rawRules, (rule) ->
      rule && rule[0] != '#'

    #@rules = RelPathList.parse rawRules
    for rule in rawRules
      if rule.charAt(0) == '/'
        @rules.push new TopLevelMatch rule.substr 1
      else if rule.substr(0,2) == '!/'
        @negations.push new TopLevelMatch rule.substr 2
      #else if rule.charAt(-1) == '/'
      else
        minimatch = new Minimatch(rule, MINIMATCH_OPTIONS)
        unless minimatch.negate
          @rules.push minimatch
        else
          @negations.push minimatch

  shouldIgnore: (path) ->
    return true unless path?
    #return @rules.matches path
    #return true if (_.some BASE_IGNORE_RULES, (rule) -> rule.match path)
    if _.some(@rules, (rule) -> rule.match path)
      return true unless _.some @negations, (rule) -> rule.match path
    return false



module.exports = IgnoreRules
