errorType =
  NO_FILE : 'NO_FILE'

errorMessage =
  NO_FILE : 'File not found'

errors =
  new : (type) ->
    err = new Error(errorMessage[type])
    err.type = errorType[type]
    return err

exports.errors = errors
exports.errorType = errorType
exports.errorMessage = errorMessage
