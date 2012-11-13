# based on https://gist.github.com/807712
fs = require 'fs'

# rmDir = (dirPath) ->
#   files = fs.readdirSync(dirPath)
#   if files.size > 0
#   for file in files
#     filePath = dirPath + "/" file


# rmDir = function(dirPath) {
#       try { var files = fs.readdirSync(dirPath); }
#       catch(e) { return; }
#       if (files.length > 0)
#         for (var i = 0; i < files.length; i++) {
#           var filePath = dirPath + '/' + files[i];
#           if (fs.statSync(filePath).isFile())
#             fs.unlinkSync(filePath);
#           else
#             rmDir(filePath);
#         }
#       fs.rmdirSync(dirPath);
#     };