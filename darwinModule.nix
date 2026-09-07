self:

{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.programs.alternative-linux-builder;
  inherit (self.packages.${pkgs.stdenv.hostPlatform.system}) alternative-linux-builder;
in

{
  options.programs.alternative-linux-builder = {
    enable = lib.mkEnableOption "a swift-based linux external builder";

    enableRosetta = lib.mkEnableOption "Rosetta 2 translation for building x86_64-linux packages" // {
      default = true;
    };

    cores = lib.mkOption {
      default = 1;
      description = ''
        Number of CPU cores allocated to the VM.
      '';
      type = lib.types.int;
    };

    kernel = lib.mkPackageOption pkgs.pkgsLinux "kernel" {
      default = "linux";
      pkgsText = "pkgs.pkgsLinux";
    };

    memory = lib.mkOption {
      default = null;
      description = ''
        Amount of memory allocated to the VM in mebibytes.

        Default amount is determined by the program dynamically (roughly one quarter the amount of
        total memory) when this option is left blank.
      '';
      type = with lib.types; nullOr int;
    };
  };

  config = lib.mkMerge [
    (lib.mkIf cfg.enable {
      nix.settings = {
        extra-experimental-features = [ "external-builders" ];
        external-builders = builtins.toJSON [
          {
            systems = [ "aarch64-linux" ] ++ lib.optional cfg.enableRosetta "x86_64-linux";
            program = lib.getExe alternative-linux-builder;
            args = [
              "-c"
              (toString cfg.cores)
            ]
            ++ lib.optionals (cfg.memory != null) [
              "-m"
              (toString cfg.memory)
            ]
            ++ lib.optional cfg.enableRosetta "--rosetta";
          }
        ];
      };
    })
  ];
}
