# Thimble (private Unity 6 game, github conor-sometimes/thimble): all game rules are pure C# built and
# tested outside Unity by its dotnet/ solution. This toolbox runs the heavy, Unity-free half of its
# gates on a box with cores to spare, so the lanes' Macs stay responsive: `just test`, the scenario
# suites (`scenarios`, `scenarios-full`), the coverage ratchet, mutation testing (Stryker, `witch
# mutate`), the stress harness and soaks. Thimble's own `just remote <recipe>` (tools/remote_run.py)
# rsyncs a checkout to ~/thimble-ci/<checkout> and calls this through agent-job; run it by hand as:
#
#   cd ~/thimble-ci/main && nix run github:conor-sometimes/workbench#thimble -- -c 'just test'
#   nix run .#thimble -- --cpus 4 -- just scenarios-full --timings
#
# Caches: NuGet packages, the NuGet HTTP cache and dotnet's CLI home live in the toolbox cache
# (~/.cache/toolbox-thimble, mounted at /cache), and each checkout keeps its own obj/ and bin/ on the
# host (rsync excludes them), so a repeat run restores and builds incrementally.
# Restore needs nuget.org in the account's egress allow-list; without it, a cache pre-filled from a
# machine that has restored (rsync ~/.nuget/packages/ to ~/.cache/toolbox-thimble/nuget/) is enough.
#
# Unity itself (unity-check, unity-test, scenarios-mono: they need the Editor's compiler and its Mono)
# comes from the `unity` base this project sits under (bases/default.nix), at Thimble's pinned editor
# version: a placeholder until the Unity Linux Editor stage (stage 1) builds it. Host option:
# workbench.projects.unity.thimble.enable.
{ pkgs, lib, tools }:

let
  # Thimble's justfile needs just >= 1.5x (`[windows] set shell`, `[script]`); nixos-26.05 has 1.51, which
  # rejects it ("extraneous attribute"). Upstream's static musl release, pinned (the Macs run 1.59).
  just = pkgs.stdenvNoCC.mkDerivation rec {
    pname = "just"; version = "1.59.0";
    src = pkgs.fetchurl {
      url = "https://github.com/casey/just/releases/download/${version}/just-${version}-x86_64-unknown-linux-musl.tar.gz";
      sha256 = "0gm20dcjvy0ymb11pr2hnvw6z1ccijimrr9m21y521kggdhl9420";
    };
    sourceRoot = ".";
    installPhase = "install -Dm755 just $out/bin/just";
  };
in
lib.mkToolbox {
  name = "thimble";
  base = "unity";  # workbench.projects.unity.thimble
  baseArgs.version = "6000.6.9f1"; # the Editor Thimble is pinned to
  packages = p: [ just ] ++ (with p; [   # just: the recipes (pinned above); the .NET SDK comes from the unity base (lib/toolsets.nix dotnet)
    python3                        # tools/*.py
    gnugrep gnused gawk findutils diffutils gnutar gzip procps which rsync   # what recipes shell out to
  ]);
  # The whole of hokkaido, but a little headroom for the host and ssh (6 cores, 29 GB; the claude
  # account's slice caps 600% CPU and 18G high).
  resources = { cpus = "5.5"; memory = "12g"; };   # 12g + a background farm job's 5g stays under the 18G slice
  queue = "heavy";                 # one heavy job at a time on the box, whichever checkout asks
  env = {
    DOTNET_CLI_TELEMETRY_OPTOUT = "1";
    DOTNET_NOLOGO = "1";
    DOTNET_SKIP_FIRST_TIME_EXPERIENCE = "1";
    DOTNET_CLI_WORKLOAD_UPDATE_NOTIFY_DISABLE = "1";
    DOTNET_CLI_HOME = "/cache/dotnet-home";        # first-run sentinel, tool shims: kept between runs
    NUGET_PACKAGES = "/cache/nuget";               # the global packages folder: kept between runs
    NUGET_HTTP_CACHE_PATH = "/cache/nuget-http";
    NUGET_CERT_REVOCATION_MODE = "offline";        # CRL/OCSP hosts are plain http and not on the wall
    MSBUILDDISABLENODEREUSE = "1";                 # no build servers left behind in a throwaway container
    DOTNET_CLI_USE_MSBUILD_SERVER = "0";
    THIMBLE_HOST = "workbench";                    # lets Thimble's tools say where they ran
  };
}
