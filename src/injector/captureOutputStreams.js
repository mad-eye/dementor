//console.log("CAPTURING OUTPUT STREAMS");

if (typeof(__madeyeOutput__) == 'undefined') 
//  console.log("MADEYE OUTPUT SET TO EMPTY STRING");
  __madeyeOutput__ = ""

process.stdout.write = (function(write) {
  return function(string, encoding, fd) {
    write.apply(process.stdout, arguments)
    __madeyeOutput__ += string;    
  }
})(process.stdout.write);

process.stderr.write = (function(write) {
  return function(string, encoding, fd) {
    write.apply(process.stderr, arguments)
    __madeyeOutput__ += string;    
  }
})(process.stderr.write);

"SUCCESS";
