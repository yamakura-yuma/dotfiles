{
  description = "Declarative agent-environment tooling (starship, ...) shared across hosts";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = { self, nixpkgs, flake-utils }:
    flake-utils.lib.eachSystem [ "x86_64-linux" "aarch64-linux" ] (system:
      let pkgs = import nixpkgs { inherit system; };
      in {
        packages.starship = pkgs.starship;
        packages.default = pkgs.starship;
        devShells.default = pkgs.mkShell { packages = [ pkgs.starship ]; };
      });
}
