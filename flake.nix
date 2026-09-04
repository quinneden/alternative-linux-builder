{
  description = "external builder for linux packages on darwin";

  inputs.nixpkgs.url = "github:nixos/nixpkgs/nixpkgs-unstable";

  outputs =
    { nixpkgs, self, ... }:
    let
      pkgs = import nixpkgs { inherit system; };
      system = "aarch64-darwin";
    in
    {
      darwinModules = {
        default = self.darwinModules.linux-external-builder;
        linux-external-builder = import ./module { inherit self; };
      };

      packages.${system} = nixpkgs.lib.packagesFromDirectoryRecursive {
        directory = ./packages;
        inherit (pkgs) callPackage;
      };
    };
}
