#!/usr/bin/env bash
set -euo pipefail

prebuilt_tools_path_file="${1:?prebuilt tools path file is required}"
prebuilt_tools="$(<"$prebuilt_tools_path_file")"
flake_dir="/tmp/runner-nixpkgs-flake"

mkdir -p "$flake_dir"

cat > "$flake_dir/flake.nix" <<EOF
{
  outputs = { self }: {
    apps.x86_64-linux.fastfetch = { type = "app"; program = "$prebuilt_tools/bin/fastfetch"; };
    apps.x86_64-linux.cowsay = { type = "app"; program = "$prebuilt_tools/bin/cowsay"; };
    apps.x86_64-linux.pokemonsay = { type = "app"; program = "$prebuilt_tools/bin/pokemonsay"; };
    apps.x86_64-linux.lolcat = { type = "app"; program = "$prebuilt_tools/bin/lolcat"; };
    apps.x86_64-linux.figlet = { type = "app"; program = "$prebuilt_tools/bin/figlet"; };
  };
}
EOF

registry_flake="$(nix-store --add "$flake_dir")"
nix-store --add-root /nix/var/nix/gcroots/prebuilt-tools/runner-nixpkgs-flake --indirect -r "$registry_flake"

cat > /etc/nix/registry.json <<EOF
{
  "version": 2,
  "flakes": [
    {
      "from": { "type": "indirect", "id": "nixpkgs" },
      "to": { "type": "path", "path": "$registry_flake" }
    }
  ]
}
EOF
