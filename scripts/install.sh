#!/bin/sh
set -eu
BT_SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
exec "${BT_INSTALL_PYTHON:-python3}" "$BT_SCRIPT_DIR/install.py" "$@"
