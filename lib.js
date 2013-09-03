//entry point when dementor is included as module
//in package.json "main": "lib.js"

require("coffee-script")
app = require("./app")

exports.execute = app.execute
