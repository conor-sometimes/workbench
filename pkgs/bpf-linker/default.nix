# bpf-linker 0.12 built against LLVM 23, so it matches the LLVM of the aya nightly rustc (nixpkgs'
# own bpf-linker lags at 0.9.15 on an older LLVM, so the BPF object would not link). This is the
# one piece that made mimi's toolchain a hand-assembly (`cargo install bpf-linker` + putting libLLVM
# on LD_LIBRARY_PATH); as a nix package it carries its own RPATH, so the dev env just works.
#
# Modelled on nixpkgs' pkgs/by-name/bp/bpf-linker/package.nix: the `llvm-<major>` feature selects the
# LLVM version, found via llvm-config from llvmPackages_23 on the build path.
{ pkgs }:

pkgs.rustPlatform.buildRustPackage rec {
  pname = "bpf-linker";
  version = "0.12.0";

  src = pkgs.fetchFromGitHub {
    owner = "aya-rs";
    repo = "bpf-linker";
    tag = "v${version}";
    hash = "sha256-y4jlEs9oF5jLlLkJHqXUMsHOeLUhTCDeqwnYzp8H9yI=";
  };

  cargoHash = "sha256-MSjwNgFa847R8joc8oreVpWDujsKR9duooycmlaiB0U=";

  buildNoDefaultFeatures = true;
  buildFeatures = [ "llvm-${pkgs.lib.versions.major pkgs.llvmPackages_23.llvm.version}" ];

  nativeBuildInputs = [ pkgs.llvmPackages_23.llvm.dev ]; # llvm-config for llvm-sys
  # libLLVM.so lives in the `lib` output (llvm-config only points at `dev`), so put it on the link
  # path explicitly or the final `-lLLVM` fails to resolve.
  buildInputs = [ pkgs.zlib pkgs.libxml2 pkgs.llvmPackages_23.llvm.lib ];

  # llvm-sys locates LLVM via llvm-config, which is not available when cross-compiling; and the test
  # suite wants btfdump. We only need the linker binary.
  doCheck = false;

  meta = {
    description = "BPF static linker (0.12, LLVM 23) matching aya's nightly rustc";
    mainProgram = "bpf-linker";
    platforms = [ "x86_64-linux" ];
  };
}
