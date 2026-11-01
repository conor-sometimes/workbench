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
  toolsets = [ lib.toolsets.go ]; # the Go toolchain + its egress (dev tools are auto-included)
  # banken-specific extras on top of the Go core:
  packages = p: with p; [
    cyclonedx-gomod # just sbom
  ];
}
