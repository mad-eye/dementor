#! /bin/bash
#This assumes we have extracted the node tarball into dementor/node
#Thus the node binary is dementor/node/bin/node

# Find the script dir, following one level of symlink. Note that symlink
# can be relative or absolute. Too bad 'readlink -f' is not portable.
ORIG_DIR=$(pwd)
cd "$(dirname "$0")"
if [ -L "$(basename "$0")" ] ; then
    cd "$(dirname $(readlink $(basename "$0") ) )"
fi
SCRIPT_DIR=$(pwd -P)
cd "$ORIG_DIR"

NODE=$SCRIPT_DIR/../node/bin/node
  
export MADEYE_BASE_URL="https://madeye.io"
$NODE $SCRIPT_DIR/madeye.js
