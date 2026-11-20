# Toolsets: reusable bundles, each pairing the TOOLS with the egress DOMAINS those tools need to
# fetch dependencies. A project's dev env (mkDevEnv) imports the language toolsets it needs and gets
# both -- packages on PATH, domains flowed into the project's `egress`, which the host's containment
# config turns into that account's proxy allow-list on deploy. "This project is Go" is one line
# (toolsets = [ ts.go ]) and the right wall follows, in sync.
#
# `dev` is the common baseline: mkDevEnv includes it in EVERY env automatically, so git/gh/just/etc
# need never be re-listed. Language toolsets hold only what is language-specific. Project-specific
# extras go on the project itself (mkDevEnv's `packages` / `egress`).
{ pkgs }:

{
  # Included in every dev env by mkDevEnv -- the tools you want everywhere.
  dev = {
    packages = p: with p; [
      git
      gh # the GitHub CLI
      just # command runner
      hyperfine # benchmarking
      jq
      ripgrep
      fd
    ];
    egress = [
      "github.com" # git over https, releases
      "api.github.com" # gh
      "githubusercontent.com" # raw + release assets
    ];
  };

  go = {
    packages = p: with p; [
      go_1_27
      gofumpt
      golangci-lint
      gosec
      govulncheck
      errcheck
      go-tools # ships the `staticcheck` binary
      delve # dlv
    ];
    egress = [
      "proxy.golang.org" # Go module proxy
      "sum.golang.org" # the checksum database
    ];
  };

  rust = {
    packages = p: with p; [
      rustup # nightly + rust-src + the bpf target, fetched on first use
      (import ../pkgs/bpf-linker { inherit pkgs; }) # bpf-linker 0.12 vs LLVM 23 (nixpkgs' lags at 0.9.15); nix-built, RPATH set
      cargo-deny # supply-chain gate (security software)
      gcc # the userspace linker (rustc drives `cc` to link; the BPF side uses bpf-linker)
      pkg-config
    ];
    egress = [
      "static.rust-lang.org" # the Rust toolchain (nightly)
      "crates.io"
      "static.crates.io" # crate tarballs
      "index.crates.io" # the sparse registry index
    ];
  };

  python = {
    packages = p: with p; [
      uv # venvs and locks
      python3
    ];
    egress = [
      "pypi.org" # the package index
      "files.pythonhosted.org" # wheels and sdists
    ];
  };

  dotnet = {
    # .NET SDK 11.0.100 (Thimble pins it exactly in global.json, rollForward disable, 2026-11-20).
    # nixos-26.05 only has 11.0.100-rc.3 so far, so the SDK alone comes from a pinned nixpkgs master
    # commit. When 26.05 ships 11.0.100, go back to `p.dotnet-sdk_11` (one pin, flake.lock).
    # One SDK only: a second SDK earlier on PATH would win `dotnet` and miss the global.json pin.
    packages = p: [
      (import (fetchTarball {
        url = "https://github.com/NixOS/nixpkgs/archive/56cb4aa734e07e622c02d5c6fc0c3746fa79761a.tar.gz";
        sha256 = "031lf4qhza6psgqqy4iiclfllvgcl83w38c23vcl6xbzs39knj7p";
      }) { system = p.stdenv.hostPlatform.system; }).dotnetCorePackages.sdk_11_0
    ];
    egress = [
      "nuget.org" # api.nuget.org + globalcdn.nuget.org (restore)
    ];
  };
}
