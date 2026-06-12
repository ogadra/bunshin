# Single source of the pinned home-manager revision. nix-path resolves
# <home-manager> through here so it cannot drift against the pinned nixpkgs and
# break an offline `home-manager switch` by re-deriving from a moved release.
builtins.fetchTarball {
  url = "https://github.com/nix-community/home-manager/archive/3ee51fbdac8c8bdfe1e7e1fcaba6520a563f394f.tar.gz";
  sha256 = "sha256-QOD/CNm196nCJRheux/URi4/HE66fthdOMqCJoPP1Y0=";
}
