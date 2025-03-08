{
  description = "play-music development environment";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

  outputs = { self, nixpkgs }:
    let
      inherit (nixpkgs.lib) genAttrs systems;

      forAllSystems = f:
        genAttrs systems.flakeExposed
        (system: f { pkgs = import nixpkgs { inherit system; }; });
    in {
      devShells = forAllSystems ({ pkgs }: {
        default = with pkgs; mkShell { packages = [ astyle ]; };
      });
    };
}
