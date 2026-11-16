# NixOS module: turn workbench envs on per host, by base and project.
#
#   imports = [ "${inputs.workbench}/module.nix" ];      # a flake = false input (or nixosModules.default)
#   workbench.projects.unity.thimble.enable = true;      # toolbox-thimble, plus its base toolbox-unity-<v>
#   workbench.projects.decomp.ps2.lombyte.enable = true; # lombyte-env, plus decomp-ps2-env and decomp-env
#   workbench.projects.rust.enable = true;               # a base alone: the bare toolchain (rust-env)
#   workbench.projects.unity.thimble.cpus = "4";         # container envs: default caps
#   workbench.user = "claude";                           # the account that owns per-project git remotes
#   workbench.projects.unity.thimble.gitRemote.enable = true;   # ~claude/repos/thimble.git (see below)
#
# The option tree comes from the registries (bases/default.nix, projects/*/default.nix): each base
# is a node under its parent base (its id's "<parent>-" prefix dropped: decomp-ps2 -> decomp.ps2)
# with `enable` and its builder's options (a toolbox's cpus/memory, the Unity base's
# version/modules); each project is a leaf under its base, with `enable` and its builder's options.
# Adding a base or project needs no edit here. Everything is off by default and a disabled env adds
# nothing. Enabling a base or project brings its whole chain of bases (at the version a project
# pins, if it pins one). A container env's image is a stream script in the closure: the host build
# realises its packages, and the first job only has to `podman load` it.
#
# Git remote (any project): `gitRemote.enable` gives the project a bare repo on this host at
# ~<workbench.user>/repos/<project>.git, pushed to over the account's existing ssh (no new keys, no
# third party): `git push <host>:repos/<project>.git HEAD:refs/lanes/<lane>`. A oneshot unit,
# running as that account, creates it with `git init --bare` only if it is missing (an existing repo
# is never touched beyond its hooks setting) and a checkout cache at ~/.cache/workbench-git/<project>.
# A container toolbox mounts the bare repo read-only and the cache read-write, both at their host
# paths (so a worktree made on either side resolves on the other), and exports WORKBENCH_GIT_REPO /
# WORKBENCH_GIT_CACHE. `gitRemote.pruneLanesAfterDays` (default 14, null = keep all) installs a
# post-receive hook that deletes refs/lanes/* whose tip commit is older than that, never a ref the
# same push just updated.
{ config, lib, pkgs, ... }:

let
  cfg = config.workbench.projects;
  user = config.workbench.user;

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
      gitRemote = gitRemoteOptions n;
    } // optsOf p) (projectsOn b);

  gitRemoteOptions = n: {
    enable = lib.mkEnableOption "a bare git repo for ${n} on this host (~<workbench.user>/repos/${n}.git) and its checkout cache, mounted into its toolbox";
    pruneLanesAfterDays = lib.mkOption {
      type = lib.types.nullOr lib.types.ints.positive;
      default = 14;
      description = "A post-receive hook deletes refs/lanes/* whose tip commit is older than this many days (never a ref the same push updated); null = no hook.";
    };
  };

  # what gets installed
  projectCfg = n: (at meta.projects.${n}.base).${n};
  enabledBases = builtins.filter (b: (at b).enable) (builtins.attrNames meta.bases);
  enabledProjects = builtins.filter (n: (projectCfg n).enable) (builtins.attrNames meta.projects);
  # a base env with the host's settings, plus what a project asks of it (only the direct base)
  baseEnv = b: args: applied wb.bases.${b} (settingsOf b // args);
  chainEnvs = b: args: map (c: baseEnv c (if c == b then args else { })) (chainOf b);
  envs =
    lib.concatMap (b: chainEnvs b { }) enabledBases
    ++ lib.concatMap (n:
      let p = wb.projects.${n}; b = meta.projects.${n}.base; in
      [ (applied p (removeAttrs (projectCfg n) [ "enable" "gitRemote" ]
        // lib.optionalAttrs ((projectCfg n).gitRemote.enable && p.runtime == "container") { gitRemote = gitPaths n; })) ]
      ++ chainEnvs b (p.baseArgs or { }))
      enabledProjects;

  # per-project git remotes (see the header)
  remoteProjects = builtins.filter (n: (projectCfg n).gitRemote.enable) (builtins.attrNames meta.projects);
  hasUser = user != null && config.users.users ? ${user};
  home = if hasUser then config.users.users.${user}.home else "/nonexistent";
  gitPaths = n: { repo = "${home}/repos/${n}.git"; cache = "${home}/.cache/workbench-git/${n}"; };
  git = config.workbench.pkgs.gitMinimal;
  pruneHook = n: config.workbench.pkgs.writeShellApplication {
    name = "post-receive";
    runtimeInputs = [ git config.workbench.pkgs.coreutils config.workbench.pkgs.gnugrep ];
    text = ''
      # workbench: prune refs/lanes/* whose tip commit is older than ${toString (projectCfg n).gitRemote.pruneLanesAfterDays} days
      days=${toString (projectCfg n).gitRemote.pruneLanesAfterDays}
      cutoff=$(( $(date +%s) - days * 86400 ))
      pushed=$(cut -d' ' -f3)   # stdin: "<old> <new> <ref>" per updated ref
      git for-each-ref --format='%(committerdate:unix) %(refname)' refs/lanes/ |
        while read -r when ref; do
          [ "$when" -lt "$cutoff" ] || continue
          if printf '%s\n' "$pushed" | grep -qxF "$ref"; then continue; fi
          echo "workbench: pruning $ref (tip older than $days days)"
          git update-ref -d "$ref"
        done
    '';
  };
  setupScript = n:
    let g = gitPaths n; prune = (projectCfg n).gitRemote.pruneLanesAfterDays; in
    config.workbench.pkgs.writeShellApplication {
      name = "workbench-git-${n}";
      runtimeInputs = [ git config.workbench.pkgs.coreutils ];
      text = ''
        repo=${lib.escapeShellArg g.repo}; cache=${lib.escapeShellArg g.cache}
        mkdir -p "$repo" "$cache"
        if [ ! -f "$repo/HEAD" ]; then
          git init --bare -q -b main "$repo"
          echo "workbench: created $repo"
        fi
        # lanes fetch exact commits from it
        git -C "$repo" config uploadpack.allowReachableSHA1InWant true
      '' + (if prune == null then ''
        git -C "$repo" config --unset core.hooksPath || true
      '' else ''
        git -C "$repo" config core.hooksPath /etc/workbench/git-hooks/${n}
      '');
    };
in
{
  options.workbench = {
    user = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      example = "claude";
      description = "The account that owns the per-project git remotes (gitRemote) and pushes to them over ssh.";
    };
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
    } {
      assertion = remoteProjects == [ ] || hasUser;
      message = "workbench: gitRemote is on for ${toString remoteProjects}: set workbench.user to an existing account";
    }];
    # the same env reached twice (a base enabled alone and under a project) is one path, once
    environment.systemPackages = lib.unique (map (e: e.run) (builtins.filter (e: e.run != null) envs));
    # each git remote: a oneshot as the owning account (re-run on every switch that changes it)
    systemd.services = lib.listToAttrs (map (n: lib.nameValuePair "workbench-git-${n}" {
      description = "workbench: bare git repo and checkout cache for ${n}";
      wantedBy = [ "multi-user.target" ];
      after = [ "local-fs.target" ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        User = user;
        ExecStart = lib.getExe (setupScript n);
      };
    }) remoteProjects);
    environment.etc = lib.listToAttrs (map (n: lib.nameValuePair "workbench/git-hooks/${n}/post-receive" {
      source = lib.getExe (pruneHook n);
    }) (builtins.filter (n: (projectCfg n).gitRemote.pruneLanesAfterDays != null) remoteProjects));
    warnings = map (b: "workbench: ${b}: ${wb.bases.${b}.placeholder}")
      (builtins.filter (b: wb.bases.${b} ? placeholder) enabledBases);
  };
}
