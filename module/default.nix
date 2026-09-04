{ self }:
{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.nix.linux-external-builder;
  initrd = self.packages.${pkgs.stdenv.hostPlatform.system}.initrd.override { kernel = cfg.kernel; };
  inherit (self.packages.${pkgs.stdenv.hostPlatform.system}) linux-xb;
in

{
  options.nix.linux-external-builder = {
    enable = lib.mkEnableOption "a swift-based linux external builder";

    cores = lib.mkOption {
      default = 1;
      description = ''
        Number of CPU cores allocated to the VM.
      '';
      type = lib.types.int;
    };

    kernel = lib.mkPackageOption pkgs.pkgsLinux "linux" { };

    memory = lib.mkOption {
      default = 4092;
      description = ''
        Amount of memory allocated to the VM in mebibytes.
      '';
      type = lib.types.int;
    };
  };

  config = lib.mkMerge [
    (lib.mkIf cfg.enable {
      nix.settings = {
        extra-experimental-features = [ "external-builders" ];
        external-builders = builtins.toJSON [
          {
            systems = [ "aarch64-linux" ];
            program = lib.getExe linux-xb;
            args = [
              "-c"
              (toString cfg.cores)
              "-m"
              (toString cfg.memory)
              "${cfg.kernel}/Image"
              "${initrd}/initrd"
            ];
          }
        ];
      };
    })
  ];
}
