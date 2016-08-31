#!/bin/sh

## NOTE sh NOT bash. This script should be POSIX sh only, since we don't
## know what shell the user has. Debian uses 'dash' for 'sh', for
## example.

#TODO: Enable `madeye update`
# Is MadEye already installed (in /usr/local/bin)? If so, just run the updater
# instead of starting from scratch. 
#if [ -x /usr/local/bin/madeye ]; then
  #exec /usr/local/bin/madeye update
#fi

VERSION=0.5.3
PREFIX="/usr/local"

set -e
set -u

#XXX: Do we want this?
# Let's display everything on stderr.
#exec 1>&2

UNAME=$(uname)
if [ "$UNAME" != "Linux" -a "$UNAME" != "Darwin" ] ; then
  #TODO: Support SunOS type
  echo "Sorry, the MadEye installer doesn't support this OS yet."
  echo "Please install MadEye by installing Node.js (http://nodejs.org) and running 'sudo npm install -g madeye'."
  exit 1
fi


if [ "$UNAME" = "Darwin" ] ; then
  ### OSX ###
  if [ "i386" != "$(uname -p)" -o "1" != "$(sysctl -n hw.cpu64bit_capable 2>/dev/null || echo 0)" ] ; then
    # Can't just test uname -m = x86_64, because Snow Leopard can
    # return other values.
    echo "The MadEye installer only supports 64-bit Intel processors at this time."
    echo "Please install MadEye by installing Node.js (http://nodejs.org) and running 'sudo npm install -g madeye'."
    exit 1
  fi
  PLATFORM="darwin-x64"
elif [ "$UNAME" = "Linux" ] ; then
  ### Linux ###
  ARCH=$(uname -m)
  if [ "$ARCH" != "i686" -a "$ARCH" != "x86_64" ] ; then
    echo "The MadEye installer only supports i686 and x86_64 architectures for now."
    echo "Please install MadEye by installing Node.js (http://nodejs.org) and running 'sudo npm install -g madeye'."
    exit 1
  elif [ "$ARCH" = "i686" ]; then
    PLATFORM="linux-x86"
  else #ARCH=x86_64
    PLATFORM="linux-x64"
  fi
fi

trap "echo Installation failed." EXIT

TARBALL_URL="https://github.com/mad-eye/dementor/releases/download/${VERSION}/madeye_${VERSION}_${PLATFORM}.tgz"
echo "Using tarball url $TARBALL_URL"

INSTALL_TMPDIR="$HOME/.madeye-install-tmp"
rm -rf "$INSTALL_TMPDIR"
mkdir "$INSTALL_TMPDIR"
echo "Downloading MadEye distribution"
curl -L --progress-bar --fail "$TARBALL_URL" | tar -xzf - -C "$INSTALL_TMPDIR"
# bomb out if it didn't work, eg no net
test -x "${INSTALL_TMPDIR}/dist/madeye"

MADEYE_DIR="$HOME/.madeye"
DIST_DIR="$MADEYE_DIR/dist"
rm -rf "$DIST_DIR"
mkdir -p "$MADEYE_DIR"
mv "${INSTALL_TMPDIR}/dist" "$DIST_DIR"
rmdir "$INSTALL_TMPDIR"

MADEYE_CMD="$MADEYE_DIR/dist/madeye"
# just double-checking :)
test -x "$MADEYE_CMD"

echo
echo "MadEye has been installed in your home directory (~/.madeye)."

# If we find an npm-madeye, try to uninstall it.
if command npm -g list 2>/dev/null | grep -q "├─┬ madeye"; then
  echo "We've found another MadEye installed by npm that we need to remove."
  if npm uninstall -g madeye >/dev/null 2>&1; then
    echo "Successfully removed the extraneous copy of MadEye."
  elif type sudo >/dev/null 2>&1; then
    echo "This may prompt for your password."
    if sudo npm uninstall -g madeye >/dev/null 2>&1; then
      echo "Successfully removed the extraneous copy of MadEye."
    else
      echo "We were unable to remove the npm-installed MadEye.  Please run 'sudo npm uninstall -g madeye' and run this installer again."
      exit 1
    fi
  else # no sudo
    echo "We were unable to remove the npm-installed MadEye.  Please uninstall MadEye from npm and run this installer again."
    exit 1
  fi
fi

# Link binary to /usr/local/bin/madeye
if ln -f -s "$MADEYE_CMD" "$PREFIX/bin/madeye" >/dev/null 2>&1; then
  echo "Linking madeye to $PREFIX/bin/madeye for your convenience."
  cat <<"EOF"

To get started fast:

  $ cd path/to/my_cool_project
  $ madeye

Or read the options with

  $ madeye --help 

EOF
elif type sudo >/dev/null 2>&1; then
  echo "Linking madeye to $PREFIX/bin/madeye for your convenience."
  echo "This may prompt for your password."

  # New macs (10.9+) don't ship with /usr/local, however it is still in
  # the default PATH. We still install there, we just need to create the
  # directory first.
  if [ ! -d "$PREFIX/bin" ] ; then
      sudo mkdir -m 755 "$PREFIX" || true
      sudo mkdir -m 755 "$PREFIX/bin" || true
  fi

  if sudo ln -s -f "$MADEYE_CMD" "$PREFIX/bin/madeye"; then
    cat <<"EOF"

To get started fast:

  $ cd path/to/my_cool_project
  $ madeye

Or read the options with

  $ madeye --help 

EOF
  else
    cat <<"EOF"

Couldn't link madeye to $PREFIX/bin. Please either:

  (1) Run the following as root:
        ln -s -f "$MADEYE_CMD" "$PREFIX/bin/madeye"
  (2) Add ~/.madeye to your path, or
  (3) Rerun this command to try again.

Then to get started take a look at 'madeye --help'.
EOF
  fi
else
  cat <<"EOF"

Now you need to do one of the following:

  (1) Add ~/.madeye to your path, or
  (2) Run this command as root:
        ln -s -f "$MADEYE_CMD" "$PREFIX/bin/madeye"

Then to get started take a look at 'madeye --help'.
EOF
fi


trap - EXIT
