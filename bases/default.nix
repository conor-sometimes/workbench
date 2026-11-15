# Bases: the generic toolchain envs. A project sits on one (`base = "<id>";` in its
# projects/<name>/default.nix) and extends it: the same builder, the base's packages plus its own.
# A base can sit on a parent base the same way (`base = "decomp"` on decomp-ps2), to any depth.
#
# On a host (../module.nix) the bases form the option tree, each base under its parent, its id's
# "<parent>-" prefix dropped: decomp-ps2 is workbench.projects.decomp.ps2. `.enable` on a base is
# the bare toolchain; a project nests under its base, workbench.projects.decomp.ps2.lombyte.enable,
# and brings its whole chain of bases. Flake outputs keep the flat ids (nix run .#decomp-ps2).
#
# How a project extends its base, per runtime (each shares the base's store paths, nothing copied):
#   fhs (decomp*)    mkDecompEnv, through the platform's mkEnv: the decomp base is mkDecompEnv with
#                    no extras, a platform base that plus the platform's tools, a project that plus
#                    its own. Every shared package is one store path.
#   devenv (go/rust) mkDevEnv with the same toolset: the toolset's packages are shared paths.
#   container        mkToolbox with `base`: the image is layered in the chain's tiers, so a base's
#                    layers are byte-identical in every image on it (podman stores them once).
#
# Add a base: one line here. Add a project: projects/<name>/ with `base = "<id>";` and one line in
# ../default.nix. The NixOS module generates the options from these registries.
{ pkgs, lib, tools }:

{
  # decomp-env: what every decomp shares (objdiff, decomp-permuter, perm-lines, lane-merge, gcc
  # multilib, Python, ...; lib/mkDecompEnv.nix)
  decomp     = lib.mkDecompEnv { name = "decomp"; };
  decomp-ps2 = lib.platforms.ps2.mkEnv { name = "decomp-ps2"; base = "decomp"; wine = true; };  # + EE-GCCs, PS2 binutils, ccc, ghidra-ps2, Wine for SN
  decomp-ps1 = lib.platforms.ps1.mkEnv { name = "decomp-ps1"; base = "decomp"; };               # + Psy-Q GCCs, maspsx, mipsel binutils, ghidra-ps1
  decomp-psp = lib.platforms.psp.mkEnv { name = "decomp-psp"; base = "decomp"; wine = true; };  # + SNC/mwccpsp/psp-gcc, pspdev binutils, ghidra-psp
  go         = lib.mkDevEnv { name = "go";   toolsets = [ lib.toolsets.go ]; };     # go-env
  rust       = lib.mkDevEnv { name = "rust"; toolsets = [ lib.toolsets.rust ]; };   # rust-env
  python     = lib.mkToolbox { name = "python"; packages = lib.toolsets.python.packages; };   # toolbox-python (container)
  dotnet     = lib.mkToolbox { name = "dotnet"; packages = lib.toolsets.dotnet.packages; };   # toolbox-dotnet (container)
  # toolbox-unity-<version>: the .NET SDK + (stage 1) the Unity Editor; Thimble's version by default
  unity      = lib.mkUnityEnv { version = "6000.6.9f1"; };
}
