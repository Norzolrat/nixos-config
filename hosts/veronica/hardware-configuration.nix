{ config, lib, pkgs, modulesPath, ... }:

{
  fileSystems."/boot" = {
    device = "/dev/disk/by-uuid/38B5-024F";
    fsType = "vfat";
  };
}
