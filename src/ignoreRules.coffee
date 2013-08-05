_ = require 'underscore'
_.str = require 'underscore.string'
{Minimatch} = require 'minimatch'
{RelPathSpec, RelPathList} = require('pathspec')

MINIMATCH_OPTIONS = { matchBase: true, dot: true, flipNegate: true }

class IgnoreRules
  constructor: (rulesStr) ->
    return unless rulesStr
    rawRules = (rule.trim() for rule in _.str.lines(rulesStr) when rule)
    rawRules = _.filter rawRules, (rule) ->
      rule && rule[0] != '#'

    #@rules = RelPathList.parse rawRules

    @rules = (new Minimatch(rule, MINIMATCH_OPTIONS) for rule in rawRules)
    #@rules = (rule for rule in rules when !rule.empty and !rule.comment)
    #for rule in @rules
      #console.log rule.set

  shouldIgnore: (path) ->
    return true unless path?
    #return @rules.matches path
    #return true if (_.some BASE_IGNORE_RULES, (rule) -> rule.match path)
    return true if (_.some @rules, (rule) -> rule.match path)
    return false



module.exports = IgnoreRules
