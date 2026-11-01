# Toolsets: reusable language/runtime bundles, each pairing the TOOLS with the egress DOMAINS those
# tools need to fetch dependencies. A project's dev env (mkDevEnv) imports the toolsets it needs and
# gets both automatically -- the packages land on PATH, and the domains flow into the project's
# `egress`, which the host's containment config turns into that account's proxy allow-list on deploy.
# So "this project is Go" means one line (toolsets = [ ts.go ]) and the right wall follows, in sync.
#
# Keep a toolset to the language's COMMON core; project-specific extras go on the project itself
# (mkDevEnv's `packages` / `egress`).
{ pkgs }:

{
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
      just
      git
    ];
    egress = [
      "proxy.golang.org" # Go module proxy
      "sum.golang.org" # the checksum database
      "github.com" # source-fetched deps, and gh
      "githubusercontent.com"
    ];
  };

  rust = {
    packages = p: with p; [
      rustup # nightly + rust-src + the bpf target, fetched on first use
      bpf-linker # links aya's BPF bytecode
      cargo-deny # supply-chain gate (security software)
      pkg-config
      just
      git
    ];
    egress = [
      "static.rust-lang.org" # the Rust toolchain (nightly)
      "crates.io"
      "static.crates.io" # crate tarballs
      "index.crates.io" # the sparse registry index
      "github.com" # aya + any git deps
      "githubusercontent.com"
    ];
  };
}
