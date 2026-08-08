#!/usr/bin/env bash
find . -name '*.odin' | entr -c sh -c '
  odinfmt . -w > /dev/null && echo "> Format successful" || { echo "--- odinfmt failed ---" >&2; exit 1; }
  odin check . -strict-style && echo "> Lint successful" || { echo "--- odin check failed ---" >&2; exit 1; }
  mkdir -p bin
  odin build . -o:none -debug -out:bin/ark && echo "> Build successful" || { echo "--- odin build failed ---" >&2; exit 1; }
'
