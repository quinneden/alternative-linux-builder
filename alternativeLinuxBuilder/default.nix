{
  callPackage,
  darwin,
  initrd ? callPackage ./initrd.nix { inherit kernel; },
  kernel ? pkgsLinux.linux,
  pkgsLinux,
  stdenv,
  swift,
}:

stdenv.mkDerivation {
  pname = "alternative-linux-builder";
  version = "0.1.0";

  src = ./.;

  nativeBuildInputs = [
    darwin.sigtool
    swift
  ];

  buildPhase = ''
    runHook preBuild
    swiftc ./alternativeLinuxBuilder.swift
    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall
    install -Dm755 -t $out/bin ./alternativeLinuxBuilder

    mkdir -p $out/share
    ln -s ${initrd} $out/share/initrd
    ln -s ${kernel} $out/share/kernel

    runHook postInstall
  '';

  postFixup = ''
    codesign -s - -f --entitlements ./alternativeLinuxBuilder.entitlements \
      $out/bin/alternativeLinuxBuilder
  '';

  passthru = { inherit initrd kernel; };
  meta.mainProgram = "alternativeLinuxBuilder";
}
