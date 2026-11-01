# mkDevEnv: a plain per-project development environment -- the project's tools on PATH, nothing
# more. Unlike mkDecompEnv (a heavy FHS namespace for prebuilt 32-bit compilers) or mkToolbox (an
# on-demand podman container), this is just a shell with the toolchain: the project is built by the
# account that runs it, using THAT account's network egress (the agent-containment proxy). So the
# env carries no isolation of its own -- it is the reproducible toolchain half; the sandbox half is
# the contained account that runs it.
#
#   mkDevEnv { name = "banken"; packages = p: [ p.go_1_27 p.gofumpt ]; egress = [ "proxy.golang.org" ]; }
#   -> a `banken-env` command: `banken-env` (interactive) or `banken-env -c 'just default'`
#
# `egress` is DECLARED here and consumed by the host config: the contained account for this project
# sets its proxy allow-list from projects.<name>.egress, so the tools and the domains they need live
# in one place and cannot drift apart.
{ pkgs }:

{
  name,
  toolsets ? [ ],         # reusable language bundles (lib/toolsets.nix): each { packages; egress }
  packages ? (_: [ ]),   # project-specific tools on top of the toolsets
  egress ? [ ],           # project-specific domains on top of the toolsets'
  env ? { },              # extra environment (NAME = "value")
  profile ? "",           # extra shell setup sourced on entry
}:

let
  # Compose the toolsets with the project's own extras: tools are unioned onto PATH, and the egress
  # domains are unioned into one list the host's containment config reads. "This project is Go" is
  # then one line (toolsets = [ ts.go ]) and the tools + the wall it needs arrive together.
  tools = pkgs.lib.concatMap (ts: ts.packages pkgs) toolsets ++ packages pkgs;
  egressDomains = pkgs.lib.unique (pkgs.lib.concatMap (ts: ts.egress) toolsets ++ egress);
  envLines = pkgs.lib.concatStringsSep "\n"
    (pkgs.lib.mapAttrsToList (k: v: "export ${k}=${pkgs.lib.escapeShellArg v}") env);

  run = pkgs.writeShellApplication {
    name = "${name}-env";
    runtimeInputs = tools;
    text = ''
      ${envLines}
      ${profile}
      # `-env -c 'cmd'` or `-env -- cmd` runs one command; bare `-env` is interactive. This matches
      # the decomp envs and toolboxes so every workbench env is driven the same way.
      [ "''${1:-}" = "--" ] && shift
      [ "''${1:-}" = "-c" ] && shift
      [ $# -gt 0 ] && exec bash -lc "$*"
      exec bash
    '';
  };

  shell = pkgs.mkShellNoCC {
    packages = tools;
    shellHook = envLines + "\n" + profile;
  };
in
# the common project shape (as mkDecompEnv / mkToolbox), plus the composed `egress` list for the
# host config to read.
{
  inherit name run shell;
  egress = egressDomains;
  image = null;
  runtime = "devenv";
}
