exports.FILE_HARD_LIMIT = FILE_HARD_LIMIT = 8000
exports.FILE_SOFT_LIMIT = FILE_SOFT_LIMIT = 3000
exports.ERROR_TOO_MANY_FILES =
  type: 'TOO_MANY_FILES'
  message: "MadEye currently only supports projects with less than #{FILE_HARD_LIMIT} files"
exports.WARNING_MANY_FILES = "MadEye currently runs best with projects with less than #{FILE_SOFT_LIMIT} files.  Performance may be slow in a Hangout."

exports.TERMINAL_PORT = 8081 #TODO pick a more uncommon port
