{ config, lib, pkgs, ... }:
lib.mkMerge [
  {
    virtualisation.waydroid.enable = true;
    programs.adb.enable = true;
    services.geoclue2.enable = true;
  }
  {
    environment.systemPackages = with pkgs; [
      waydroid
      android-tools
      wl-clipboard
    ];
  }
]
