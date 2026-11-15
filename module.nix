# NixOS module: turn workbench envs on per host, by base and project.
#
#   imports = [ "${inputs.workbench}/module.nix" ];      # a flake = false input (or nixosModules.default)
#   workbench.projects.unity.thimble.enable = true;      # toolbox-thimble, plus its base toolbox-unity-<v>
#   workbench.projects.decomp.ps2.lombyte.enable = true; # lombyte-env, plus decomp-ps2-env and decomp-env
#   workbench.projects.rust.enable = true;               # a base alone: the bare toolchain (rust-env)
#   workbench.projects.unity.thimble.cpus = "4";         # container envs: default caps
#
# The option tree comes from the registries (bases/default.nix, projects/*/default.nix): each base
# is a node under its parent base (its id's "<parent>-" prefix dropped: decomp-ps2 -> decomp.ps2)
# with `enable` and its builder's options (a toolbox's cpus/memory, the Unity base's
# version/modules); each project is a leaf under its base, with `enable` and its builder's options.
# Adding a base or project needs no edit here. Everything is off by default and a disabled env adds
# nothing. Enabling a base or project brings its whole chain of bases (at the version a project
# pins, if it pins one). A container env's image is a stream script in the closure: the host build
# realises its packages, and the first job only has to `podman load` it.
{ config, lib, pkgs, ... }:

let
  cfg = config.workbench.projects;

  # The registries, read for option declarations without pkgs (pkgs depends on config, so options
  # built from it would recurse): names, bases and builders' options must not force pkgs.
  meta = import ./default.nix {
    pkgs = throw "workbench module: a base or project forced pkgs at option-declaration time";
  };
  # ... and with real packages, for what gets installed.
  wb = import ./default.nix { pkgs = config.workbench.pkgs; };

  parentOf = b: meta.bases.${b}.base or null;
  # option path of a base: its parent's path, then its id without the "<parent>-" prefix
  pathOf = b:
    let p = parentOf b; in
    if p == null then [ b ] else pathOf p ++ [ (lib.removePrefix "${p}-" b) ];
  chainOf = b: (let p = parentOf b; in if p == null then [ ] else chainOf p) ++ [ b ];   # root first
  childBases = b: builtins.filter (c: parentOf c == b) (builtins.attrNames meta.bases);
  projectsOn = b: lib.filterAttrs (_: p: (p.base or null) == b) meta.projects;
  orphans = builtins.filter (n: !(meta.bases ? ${meta.projects.${n}.base or ""})) (builtins.attrNames meta.projects)
    ++ builtins.filter (b: parentOf b != null && !(meta.bases ? ${parentOf b})) (builtins.attrNames meta.bases);

  optsOf = e: (e.options or (_: { })) lib;
  at = b: lib.getAttrFromPath (pathOf b) cfg;
  # host settings of a base or project: its option values minus `enable` and its children
  settingsOf = b: removeAttrs (at b)
    ([ "enable" ] ++ map (c: lib.last (pathOf c)) (childBases b) ++ builtins.attrNames (projectsOn b));
  applied = e: s: if e ? override && s != { } then e.override s else e;

  node = b:
    let
      base = meta.bases.${b};
      kids = map (c: lib.last (pathOf c)) (childBases b) ++ builtins.attrNames (projectsOn b);
      taken = [ "enable" ] ++ builtins.attrNames (optsOf base);
      clash = builtins.filter (n: builtins.elem n taken) kids ++ lib.subtractLists (lib.unique kids) kids;
    in
    assert lib.assertMsg (clash == [ ]) "workbench: name(s) ${toString clash} clash under base ${b}";
    { enable = lib.mkEnableOption "the bare ${b} base env (${base.runtime}) and its parent bases, installed system-wide"; }
    // optsOf base
    // lib.listToAttrs (map (c: lib.nameValuePair (lib.last (pathOf c)) (node c)) (childBases b))
    // lib.mapAttrs (n: p: {
      enable = lib.mkEnableOption "the ${n} env (${p.runtime}), installed system-wide with its bases (${toString (chainOf b)})";
    } // optsOf p) (projectsOn b);

  # what gets installed
  enabledBases = builtins.filter (b: (at b).enable) (builtins.attrNames meta.bases);
  enabledProjects = builtins.filter (n: (at meta.projects.${n}.base).${n}.enable) (builtins.attrNames meta.projects);
  # a base env with the host's settings, plus what a project asks of it (only the direct base)
  baseEnv = b: args: applied wb.bases.${b} (settingsOf b // args);
  chainEnvs = b: args: map (c: baseEnv c (if c == b then args else { })) (chainOf b);
  envs =
    lib.concatMap (b: chainEnvs b { }) enabledBases
    ++ lib.concatMap (n:
      let p = wb.projects.${n}; b = meta.projects.${n}.base; in
      [ (applied p (removeAttrs (at b).${n} [ "enable" ])) ] ++ chainEnvs b (p.baseArgs or { }))
      enabledProjects;
in
{
  options.workbench = {
    pkgs = lib.mkOption {
      type = lib.types.pkgs;
      default = pkgs;
      defaultText = lib.literalExpression "pkgs";
      description = "nixpkgs the envs are built with (the host's by default; workbench's own pin is its flake.lock).";
    };
    projects = lib.listToAttrs (map (b: lib.nameValuePair b (node b))
      (builtins.filter (b: parentOf b == null) (builtins.attrNames meta.bases)));
  };

  config = {
    assertions = [{
      assertion = orphans == [ ];
      message = "workbench: ${toString orphans} name a base that is not in bases/default.nix";
    }];
    # the same env reached twice (a base enabled alone and under a project) is one path, once
    environment.systemPackages = lib.unique (map (e: e.run) (builtins.filter (e: e.run != null) envs));
    warnings = map (b: "workbench: ${b}: ${wb.bases.${b}.placeholder}")
      (builtins.filter (b: wb.bases.${b} ? placeholder) enabledBases);
  };
}
