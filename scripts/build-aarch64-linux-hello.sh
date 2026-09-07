#! /usr/bin/env bash

external_builder=$(nix build --no-link --print-out-paths .#alternative-linux-builder)

nix build -L --keep-failed --rebuild --builders '' \
  --external-builders '[{"args":["-c", "1", "-m", "8192"],"program":"'"$external_builder/bin/alternativeLinuxBuilder"'","systems":["aarch64-linux"]}]' \
  nixpkgs#legacyPackages.aarch64-linux.hello
