{ pkgs, tools }:

let
  mkDecompEnv = import ./mkDecompEnv.nix { inherit pkgs tools; };
  mkPlatform = import ./mkPlatform.nix { inherit mkDecompEnv; };
  mkToolbox = import ./mkToolbox.nix { inherit pkgs; };
  mkDevEnv = import ./mkDevEnv.nix { inherit pkgs; };
  toolsets = import ./toolsets.nix { inherit pkgs; };
in
{
  inherit mkDecompEnv mkToolbox mkDevEnv toolsets;
  platforms = {
    ps2 = import ./platforms/ps2.nix { inherit mkPlatform tools pkgs; };
    ps1 = import ./platforms/ps1.nix { inherit mkPlatform tools pkgs; };
    psp = import ./platforms/psp.nix { inherit mkPlatform tools pkgs; };
  };
}
