assert = require 'assert'
fs = require 'fs'
Dementor = require('../dementor.coffee').Dementor

describe "dementor", ->
  unless fs.existsSync ".test_projects"
    fs.mkdirSync ".test_projects"

  if fs.existsSync ".test_projects/polyjuice"


    fs.mkdirSync ".test_projects/polyjuice"

  describe "constructor", ->
    it "should populate the config object if a .madeye file exists", ->

    it "should return an empty config object if no .madeye file exists", ->

  describe "watchFileTree", ->
    it "should notice when i change a file", ->

    it "should notice when i delete a file", ->

    it "should notice when i add a file", ->
