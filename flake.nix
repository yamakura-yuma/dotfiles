{
  description = "Nix-packaged subset of the Claude Code agent-environment tools (jq, uv, node, starship)";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

  outputs = { self, nixpkgs }:
    let
      systems = [ "x86_64-linux" "aarch64-linux" "x86_64-darwin" "aarch64-darwin" ];
      forAllSystems = nixpkgs.lib.genAttrs systems;
    in {
      packages = forAllSystems (system:
        let
          pkgs = nixpkgs.legacyPackages.${system};
        in {
          agent-tools = pkgs.symlinkJoin {
            name = "agent-tools";
            paths = with pkgs; [ jq uv nodejs_24 starship ];
          };
          default = self.packages.${system}.agent-tools;
        });
    };
}
