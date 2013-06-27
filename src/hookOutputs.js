/**
 * From https://gist.github.com/pguillory/729616
 * Each fn returns a handle that can unhook the callback.
 */

exports.hook_stdout = function (callback) {
    var old_write = process.stdout.write
 
    process.stdout.write = (function(write) {
        return function(string, encoding, fd) {
            write.apply(process.stdout, arguments)
            callback(string, encoding, fd)
        }
    })(process.stdout.write)
 
    return function() {
        process.stdout.write = old_write
    }
}

exports.hook_stderr = function (callback) {
    var old_write = process.stderr.write
 
    process.stderr.write = (function(write) {
        return function(string, encoding, fd) {
            write.apply(process.stderr, arguments)
            callback(string, encoding, fd)
        }
    })(process.stderr.write)
 
    return function() {
        process.stderr.write = old_write
    }
}
