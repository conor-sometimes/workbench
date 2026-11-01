# banken-sensor: the (future) eBPF telemetry sensor for banken, Rust + aya. A separate binary from
# banken-core -- banken stays pure-Go with no kernel component; the sensor owns the eBPF and feeds
# banken's Event schema (see the banken telemetry roadmap). This env is its toolchain; the contained
# `ebpflab` account runs it behind its own egress wall, and `egress` below is what that wall allows.
#
#   banken-sensor-env -c 'rustup toolchain install nightly --component rust-src && cargo build'
#   banken-sensor-env     # interactive
#
# Why rustup and not a nix-pinned toolchain: aya's eBPF side needs a NIGHTLY Rust with rust-src (to
# build `core` for the bpf target), which nixpkgs does not ship; rustup fetches it from
# static.rust-lang.org (in the allow-list). This is PoC-grade -- pin the toolchain with a fenix/
# oxalica overlay when the sensor becomes a real, released component (banken's "same bar as Go"
# standard: reproducible, fuzzed, tested, cargo-deny'd).
{ pkgs, lib, tools }:

lib.mkDevEnv {
  name = "banken-sensor";
  packages = p: with p; [
    rustup # nightly + rust-src + the bpfel target, fetched on first use
    bpf-linker # links the BPF bytecode (aya's kernel-side output)
    cargo-deny # supply-chain gate (few deps, audited -- security software)
    pkg-config
    just
    git
  ];
  egress = [
    "static.rust-lang.org" # the Rust toolchain components (nightly)
    "crates.io"
    "static.crates.io" # crate tarballs
    "index.crates.io" # the sparse registry index
    "github.com" # aya + any git deps
    "githubusercontent.com"
  ];
  # rustup/cargo write under the account's HOME by default (~/.rustup, ~/.cargo), which is writable.
  profile = ''
    echo "banken-sensor: first run -> rustup toolchain install nightly --component rust-src" >&2
  '';
}
