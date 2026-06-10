#!/usr/bin/env bash
set -euo pipefail

before="/tmp/registry-store-before.txt"
after="/tmp/registry-store-after.txt"
added="/tmp/registry-store-added.txt"

find /nix/store -mindepth 1 -maxdepth 1 | sort > "$before"
nix flake metadata nixpkgs > /dev/null
find /nix/store -mindepth 1 -maxdepth 1 | sort > "$after"
comm -13 "$before" "$after" > "$added"

while IFS= read -r path; do
  nix-store --add-root "/nix/var/nix/gcroots/prebuilt-tools/$(basename "$path")" --indirect -r "$path"
done < "$added"
