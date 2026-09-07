#! /usr/bin/env bash

externalBuilder=$(nix build --no-link --print-out-paths .#alternative-linux-builder)

while [[ $# -gt 0 ]]; do
  case $1 in
  -c | --cores)
    shift
    cores=$1
    shift
    ;;
  -m | --memory)
    shift
    memory=$1
    shift
    ;;
  *)
    break
    ;;
  esac
done

: "${cores:=1}"
: "${memory:=8192}"

externalBuildersJSON="[{\"args\":[\"-c\", \"$cores\", \"-m\", \"$memory\"],\"program\":\"$externalBuilder/bin/alternativeLinuxBuilder\",\"systems\":[\"aarch64-linux\"]}]"

command time -hp nix build --builders "" --external-builders "$externalBuildersJSON" "$@"
