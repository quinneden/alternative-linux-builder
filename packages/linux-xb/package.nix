{
  darwin,
  stdenv,
  swift,
}:

stdenv.mkDerivation {
  name = "linux-xb";

  src = ./.;

  nativeBuildInputs = [
    darwin.sigtool
    swift
  ];

  buildPhase = ''
    runHook preBuild
    swiftc ./main.swift
    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall
    install -Dm755 ./main $out/bin/linux-xb
    runHook postInstall
  '';

  postFixup = ''
    codesign -s - -f --entitlements ./linux-xb.entitlements $out/bin/linux-xb
  '';

  meta.mainProgram = "linux-xb";
}
