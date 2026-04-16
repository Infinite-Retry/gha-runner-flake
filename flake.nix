{
  description = "GitHub Actions self-hosted runner module for darwin and NixOS";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    nix-darwin = {
      url = "github:nix-darwin/nix-darwin";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = { self, nixpkgs, nix-darwin, ... }: {
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
  };
}
