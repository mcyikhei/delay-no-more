#!/bin/zsh
# Copies dist/Delay No More.app to ~/Applications. Hooks point at this stable
# path, so rebuilding and reinstalling never requires reinstalling hooks.
set -eu
root="${0:A:h:h}"
source_app="$root/dist/Delay No More.app"
target="$HOME/Applications/Delay No More.app"
[[ -d "$source_app" ]] || { print -u2 "Run scripts/package.sh first."; exit 1; }
mkdir -p "$HOME/Applications"
# Replace the executable as a new file so a running copy is not disturbed.
rm -f "$target/Contents/MacOS/DelayNoMore"
ditto "$source_app" "$target"
codesign --verify --strict "$target"
print "Installed: $target"
print "If it is running, quit it from the menu bar and open it again to load the new build."
