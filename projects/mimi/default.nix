# mimi (耳, "ears"): the eBPF telemetry sensor for banken, Rust + aya. It hears every event in the
# kernel (execs, file access, ...) and feeds banken's Event schema -- a separate binary from
# banken-core, which stays pure-Go with no kernel component. This env is mimi's toolchain; the
# contained ebpflab account runs it behind its own egress wall.
#
#   mimi-env -c 'cargo build'   # first run: rustup toolchain install nightly --component rust-src
#   mimi-env                    # interactive
#
# Why rustup and not a nix-pinned toolchain: aya's eBPF side needs a NIGHTLY Rust with rust-src, and
# bpf-linker must match that rustc's LLVM. PoC-grade -- pin the whole set (nightly + bpf-linker vs
# LLVM) when mimi becomes a real, released component (banken's "same bar as Go" standard).
{ pkgs, lib, tools }:

lib.mkDevEnv {
  name = "mimi";
  toolsets = [ lib.toolsets.rust ]; # the Rust/aya toolchain + its egress (dev tools auto-included)
  profile = ''
    echo "mimi: first run -> rustup toolchain install nightly --component rust-src" >&2
  '';
}
