#!/bin/bash
set -e
DEST="$1"
BIN=$(cabal -v0 list-bin haskell-backend)
cp "$BIN" "$DEST"
