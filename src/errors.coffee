errorType =
  NO_FILE : 'NO_FILE'
  NOT_NORMAL_FILE : 'NOT_NORMAL_FILE'

errorMessage =
  NO_FILE : 'File not found'
  NOT_NORMAL_FILE : 'Filepath does not lead to a normal file.'

errors =
  new : (type) ->
    err = new Error(errorMessage[type])
    err.type = errorType[type]
    return err

exports.errors = errors
exports.errorType = errorType
exports.errorMessage = errorMessage
