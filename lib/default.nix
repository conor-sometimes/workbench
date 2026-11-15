{ pkgs, tools }:

let
  self = {
    inherit mkDecompEnv mkToolbox mkDevEnv mkUnityEnv toolsets;
    platforms = {
      ps2 = import ./platforms/ps2.nix { inherit mkPlatform tools pkgs; };
      ps1 = import ./platforms/ps1.nix { inherit mkPlatform tools pkgs; };
      psp = import ./platforms/psp.nix { inherit mkPlatform tools pkgs; };
    };
    # the bases (generic toolchain envs) projects sit on: ../bases/default.nix
    bases = import ../bases { inherit pkgs tools; lib = self; };
  };
  mkDecompEnv = import ./mkDecompEnv.nix { inherit pkgs tools; };
  mkPlatform = import ./mkPlatform.nix { inherit mkDecompEnv; };
  # a toolbox on a container base reads that base's tiers (baseArgs: e.g. { version = "..."; })
  resolveBase = name: args:
    let b = self.bases.${name} or (throw "workbench: no base '${name}' in bases/default.nix");
    in if args == { } then b else b.override args;
  mkToolbox = import ./mkToolbox.nix { inherit pkgs resolveBase; };
  mkDevEnv = import ./mkDevEnv.nix { inherit pkgs; };
  mkUnityEnv = import ./mkUnityEnv.nix { inherit pkgs mkToolbox toolsets; };   # the Unity base
  toolsets = import ./toolsets.nix { inherit pkgs; };
in
self
