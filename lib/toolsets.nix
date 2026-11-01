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
      go_1_26 # golangci-lint/gosec track the previous Go; banken rides this so the gate runs clean
      gofumpt
      golangci-lint
      gosec
      govulncheck
      errcheck
      go-tools # ships the `staticcheck` binary
      gotestsum # `just test` renders the suite through it
      delve # dlv
    ];
    egress = [
      "proxy.golang.org" # Go module proxy
      "sum.golang.org" # the checksum database
      "vuln.go.dev" # govulncheck's vulnerability database (`just vulncheck`)
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
}
