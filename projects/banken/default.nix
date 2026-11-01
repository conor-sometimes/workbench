# banken (github conor-sometimes/banken): the host EDR, pure Go, one runtime dep. This env is the
# toolchain `just` drives -- the same gate that runs on the Mac, reproducible on any host. The
# contained account that runs it (claude on hokkaido) builds banken behind its own egress wall;
# `egress` below is exactly what that build needs and is what the host config feeds the wall.
#
#   banken-env -c 'just default'    # the whole gate (fmt vet lint gosec vulncheck test cover)
#   banken-env                      # interactive shell with the toolchain
#
# (benchstat, which `just bench`'s A/B compare wants, is not in nixpkgs; install it separately if
# you need it -- everything else `just` calls is here.)
{ pkgs, lib, tools }:

lib.mkDevEnv {
  name = "banken";
  packages = p: with p; [
    go_1_27
    gofumpt
    golangci-lint
    gosec
    govulncheck
    errcheck
    go-tools # ships the `staticcheck` binary
    delve # dlv
    cyclonedx-gomod # just sbom
    hyperfine # just bench
    just
    git
  ];
  egress = [
    "proxy.golang.org" # Go module proxy
    "sum.golang.org" # the checksum database
    "github.com" # dependencies fetched from source, and gh
    "githubusercontent.com" # raw + release assets
  ];
}
