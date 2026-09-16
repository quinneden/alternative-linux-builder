# (alter)native-linux-builder

A swift-based binary that can be used as an external builder for nix (via `external-builders` experimental feature) to build linux packages on darwin without having to setup a full remote build VM. This project aims to reproduce the functionality of Determinate Nix's [native-linux-builder](https://docs.determinate.systems/determinate-nix/linux-builder) for upstream Nix installs. It also provides a Nix-darwin module to configure the external builder.

## Setup

If you manage your system with Nix-darwin, import the module exposed by the flake into your configuration and enable the option:

```nix
{ inputs, ... }:

imports = [ inputs.alternative-linux-builder.darwinModules.default ];

programs.alternative-linux-builder = {
  enable = true;
};
```

If you don't use Nix-darwin, you can install the package via profiles:

```sh
nix profile add github:quinneden/alternative-linux-builder
```

and configure it directly in `/etc/nix/nix.conf`:

```conf
extra-experimental-features = external-builders

# external-builders takes a list of JSON objects as it's value. Required fields
# are:
#   - program: path to the executable
#   - args: CLI arguments passed to the executable
#   - systems: list of systems this builder can build for
external-builders = [{"program": "/Users/<user>/.nix-profile/bin/alternativeLinuxBuilder", "args": [], "systems": ["aarch64-linux", "x86_64-linux"]}]

# Optionally, you can configure the number of CPU cores and amount of memory in
# the 'args' field via the '-c,--cores' and '-m,--memory' flags, respectively.
# E.g.:
#   external-builders = [{"program": "...", "args": ["-c" "8", "-m", "8192"], ...}]
```

then restart the nix-daemon:

```sh
sudo launchctl kickstart -k system/org.nixos.nix-daemon
```

## Module options

| Option   | Type          | Default      | Description                                        |
| -------- | ------------- | ------------ | -------------------------------------------------- |
| `cores`  | _int_         | `1`          | Number of CPU cores allocated to the VM.           |
| `kernel` | _package_     | `pkgs.linux` | The kernel package to use.                         |
| `memory` | _null or int_ | `null`       | Amount of memory allocated to the VM in mebibytes. |
