{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
  };

  outputs = { nixpkgs, ... }:
    let
      system = "x86_64-linux";
      pkgs = import nixpkgs {
        inherit system;
        config.allowUnfreePredicate = pkg:
          builtins.elem (nixpkgs.lib.getName pkg) [ "terraform" ];
        config.permittedInsecurePackages = [ "python3.13-ecdsa-0.19.2" ];
      };
    in
    {
      devShells.${system}.default = pkgs.mkShell {
        packages = with pkgs; [
          awscli2
          checkov
          gitleaks
          just
          go_1_26
          k6
          lefthook
          nodejs_24
          pnpm
          terraform
          tflint
          trivy
          graphviz
          uv
        ];
        env = {
          # Playwright 同梱ブラウザは NixOS で実行できないため nix 提供のものを使う。
          # front/package.json の @playwright/test は playwright-driver と同一バージョンに固定すること
          PLAYWRIGHT_BROWSERS_PATH = "${pkgs.playwright-driver.browsers.override {
            withFirefox = false;
            withWebkit = false;
          }}";
          PLAYWRIGHT_SKIP_VALIDATE_HOST_REQUIREMENTS = "true";
        };
      };
    };
}
