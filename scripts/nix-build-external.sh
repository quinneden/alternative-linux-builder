#! /usr/bin/env bash

external_builder=$(nix build --no-link --print-out-paths .#linux-xb)
kernel=$(nix build --no-link --print-out-paths nixpkgs#pkgsLinux.linux)
initrd=$(nix build --no-link --print-out-paths .#initrd)

nix build -L --rebuild --builders '' \
  --external-builders '[{"args":["'"$kernel/Image"'"','"'"$initrd/initrd"'"],"program":"'"$external_builder/bin/linux-xb"'","systems":["aarch64-linux"]}]' \
  nixpkgs#legacyPackages.aarch64-linux.hello
