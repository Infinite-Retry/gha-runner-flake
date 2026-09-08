{
  description = "GitHub Actions self-hosted runner module for darwin and NixOS";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    nix-darwin = {
      url = "github:nix-darwin/nix-darwin";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs =
    { self, nixpkgs, nix-darwin, ... }:
    let
      systems = [
        "aarch64-darwin"
        "x86_64-darwin"
        "aarch64-linux"
        "x86_64-linux"
      ];
      forAllSystems = f: nixpkgs.lib.genAttrs systems (system: f nixpkgs.legacyPackages.${system});
    in
    {
      darwinModules.gha-runner = {
        imports = [
          ./module.nix
          ./module-darwin.nix
        ];
      };
      darwinModules.default = self.darwinModules.gha-runner;

      nixosModules.gha-runner = {
        imports = [
          ./module.nix
          ./module-linux.nix
        ];
      };
      nixosModules.default = self.nixosModules.gha-runner;

      packages = forAllSystems (pkgs: {
        update = pkgs.writeShellApplication {
          name = "update-android-repo";
          runtimeInputs = with pkgs; [
            curl
            git
            gnugrep
            gnused
            coreutils
          ];
          text = ''
            dest="$(git rev-parse --show-toplevel)/android-repo/repository2-3.xml"

            curl -fsS https://dl.google.com/android/repository/repository2-3.xml -o "$dest.new"
            if cmp -s "$dest.new" "$dest"; then
              rm "$dest.new"
              echo "Already up to date."
            else
              mv "$dest.new" "$dest"
              echo "Updated $dest -- commit it to pin the new manifest."
            fi

            echo
            echo "Newest stable SDK platforms now available to platformVersions:"
            grep -o 'path="platforms;android-[0-9][^"]*"' "$dest" \
              | sed 's/.*android-//; s/"$//' \
              | grep -v -- '-' \
              | sort -V \
              | tail -5 \
              | sed 's/^/  /'
          '';
        };
      });

      apps = forAllSystems (pkgs: rec {
        update = {
          type = "app";
          program = nixpkgs.lib.getExe self.packages.${pkgs.stdenv.hostPlatform.system}.update;
        };
        default = update;
      });
    };
}
