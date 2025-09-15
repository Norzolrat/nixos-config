{ stdenvNoCC, copyPathToStore }:

stdenvNoCC.mkDerivation {
  pname = "sddm-theme-locked";
  version = "dev";

  # pin your local folder into the store
  src = copyPathToStore ./LockeD;

  dontBuild = true;

  installPhase = ''
    mkdir -p $out/share/sddm/themes
    cp -r "$src" "$out/share/sddm/themes/LockeD"
  '';
}
