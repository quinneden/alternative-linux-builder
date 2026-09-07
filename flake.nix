{
  description = "(alter)native-linux-builder for nix-darwin with upstream nix";

  inputs.nixpkgs.url = "github:nixos/nixpkgs/nixpkgs-unstable";

  outputs =
    { nixpkgs, self, ... }:
    let
      pkgs = import nixpkgs { inherit system; };
      system = "aarch64-darwin";
    in
    {
      darwinModules = {
        default = self.darwinModules.alternative-linux-builder;
        alternative-linux-builder = import ./darwinModule.nix self;
      };

      packages.${system} = {
        default = self.packages.${system}.alternative-linux-builder;
        alternative-linux-builder = pkgs.callPackage ./alternativeLinuxBuilder { };
      };
    };
}
