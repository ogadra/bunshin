# Single source of the pinned nixpkgs revision. The prebuilt tools and the
# runtime flake registry both resolve through here, so they cannot drift apart
# and silently fall back to downloading instead of using the prebuilt outputs.
# Keep app/flake.lock on this same rev: the devShell then shares store paths
# with the prebuilt tools instead of doubling them. Update both together.
builtins.fetchTarball {
  url = "https://github.com/NixOS/nixpkgs/archive/cd3cab093d1d5b523e9c7efbb970f4f016cd35a9.tar.gz";
  sha256 = "sha256-RLuUREj5j5Y0nNJYYoFiH6JNV7FzXx6fOyd9Eq3gf8k=";
}
