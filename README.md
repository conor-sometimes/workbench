# workbench

One declarative, reproducible **environment per project**, in Nix — decomp toolchains, Python, Rust,
whatever a project needs — as an FHS shell or an on-demand container, declared once and cached
instead of per-machine setup scripts, hand-built containers or distroboxes.

The demanding case is matching decomp: it needs an exact toolchain — decade-old console compilers (patched 1997 GCCs, Sony
EE-GCC, Psy-Q), Windows-only SDK assemblers run under Wine, and Ghidra with the right processor
module — normally a brittle per-machine install. Here it's one Nix closure: a fresh clone plus one
command is the exact environment a project needs, byte-for-byte. Three real decompilations build
identically from it today — Lombyte (Ratchet & Clank, PS2), Bokura no Kazoku (PS2) and Crash Bash
(PS1) — and because every environment is a Nix derivation, a change that leaves the derivation hash
unchanged is a **provable** no-op (the refactor receipt you can't get on an ordinary OS).

## Quick start

    nix develop github:conor-sometimes/workbench#crash-bash   # drop into the PS1 build environment
    nix run    github:conor-sometimes/workbench#ghidra-ps2     # or just grab one tool

## Projects

Every project environment — a decomp, a Python library, a Rust crate — lives under
[projects/](projects/), is declared the same way, and is run the same way:

    nix run .#<project> -- -c 'cmd'     # run a command in any project env
    nix develop .#<project>             # drop into it (fhs envs)

Each project picks a **runtime** (how the env is realised, not a different kind of thing):

- **fhs** ([lib/mkDecompEnv.nix](lib/mkDecompEnv.nix)) — a `buildFHSEnv` shell with the toolchain on
  the host, for prebuilt compilers that expect `/usr/lib`. The decomp envs.
- **container** ([lib/mkToolbox.nix](lib/mkToolbox.nix)) — an on-demand OCI image (nix-built, in the
  store; nothing runs until a job does) that `podman run --rm`s with CPU/memory caps and the project
  bind-mounted at `/work`, then tears down. For offloading slow suites, resource caps, keeping a
  runtime off the host. (A different lifecycle from the always-on agent-containment boxes — here the
  container is for reproducibility and caps, not isolation.)

| Project | Runtime | Nix file | What's here |
| --- | --- | --- | --- |
| [Lombyte](https://github.com/lombyte-project/Lombyte) (Ratchet & Clank, PS2) | fhs | [projects/lombyte/default.nix](projects/lombyte/default.nix) | `lombyte-env`: PS2 build env (Wine for the SN tools) |
| Bokura no Kazoku (PS2 decomp) | fhs | [projects/bokura-no-kazoku/default.nix](projects/bokura-no-kazoku/default.nix) | `bokura-env`: PS2 env, four per-unit toolchains (EE-GCC 2.96 ±`-Wa,-g`, ee-gcc 2.9-991111/-01 with 2.96's as) |
| Crash Bash (PS1 decomp) | fhs | [projects/crash-bash/default.nix](projects/crash-bash/default.nix) | `crash-bash-env`: PS1 env (Psy-Q GCC 2.8.1, maspsx, mipsel binutils, just, uv) |
| Fat Princess (PSP decomp) | fhs | [projects/fat-princess/default.nix](projects/fat-princess/default.nix) | `fat-princess-env`: PSP env (pspdecrypt, pspdev binutils+VFPU, SNC/mwccpsp/psp-gcc, ghidra-psp, Wine); `just build` rebuilds the PRX byte-for-byte |
| pktlib (Python) | container | [projects/pktlib/default.nix](projects/pktlib/default.nix) | uv + Python 3.11–3.14 + just, to offload pktlib's property-based / mutation / soak suites |
| Thimble (Unity game, its pure-C# core) | container | [projects/thimble/default.nix](projects/thimble/default.nix) | .NET 10 SDK + just + Python, to offload the Unity-free gates: tests, scenario suites, coverage ratchet, mutation, stress, soaks |

    nix run .#pktlib -- -c 'just test'            # a command in its on-demand container
    nix build .#pktlib-image && ./result | podman load   # the image is a stream script (no tarball in the store)
    nix run .#pktlib -- --cpus 4 -- just soak 1   # with explicit caps

    cd ~/thimble-ci/main                          # a checkout rsynced there (Thimble's `just remote`)
    nix run .#thimble -- -c 'just test'           # whole box less a little, queued behind other heavy jobs

Runner options (before `--`): `--cpus N`, `--memory M`, `--repo DIR`, `--queue NAME` / `--no-queue`,
`--offline`, `--env NAME=VALUE`, `--name CONTAINER`, `--podman-arg ARG` (e.g. `--cpu-shares=64` so a
background job yields the CPU to a foreground one). Each toolbox keeps a persistent cache at
`~/.cache/toolbox-<name>` (mounted at `/cache`: uv, NuGet, ...). A toolbox with `queue = "heavy"`
takes a per-account lock first, so heavy jobs from several checkouts run one at a time.

Network: a container gets exactly the running account's egress. On a contained host (the account's
proxy on the host's 127.0.0.1) the runner maps the host loopback into the container with pasta and
points the proxy variables at it, so the account's allow-list applies unchanged; a fetch works where
that allow-list has the domain (Thimble: `nuget.org`). Never `--network host` for these: a non-root
container user is one of the account's subuids, which a uid-owner wall doesn't match.

Add one: a dir under [projects/](projects/) (with its `base`) and a line in [default.nix](default.nix).

## Bases and projects

A **base** is a generic toolchain env: `decomp` (what every decomp shares), `decomp-ps2`,
`decomp-ps1`, `decomp-psp` (each on `decomp`), `go`, `rust`, `python`, `dotnet`, `unity`
([bases/default.nix](bases/default.nix)). A **project** is one repo's env and sits on one base
(`base = "decomp-ps2";` in its file): the same builder, the base's packages plus its own, so what
they share is one set of store paths. For containers the image is layered in the chain's tiers, so a
base's layers are byte-identical in every image on it and podman stores them once; a second project
on a base costs only its own layers. Bases can nest to any depth (`base = "decomp"` on decomp-ps2).

Unity: the `unity` base is one env per editor version (`lib.mkUnityEnv { version; modules; }`),
carrying the .NET SDK and, from Thimble's stage 1, the Linux Unity Editor (not in it yet: nothing of
Unity is downloaded today). Thimble sits on it at its pinned version (`base = "unity";
baseArgs.version = "6000.6.9f1";`), so another Unity project on the same version shares it.

## Enabling projects on a host

The flake exports a NixOS module (`nixosModules.default`; from a `flake = false` input, import
`"${inputs.workbench}/module.nix"`). Every base and project is an option, off by default; the tree
follows the bases, each under its parent (its "<parent>-" prefix dropped):

```nix
{ inputs, ... }: {
  imports = [ "${inputs.workbench}/module.nix" ];

  workbench.projects.unity.thimble.enable = true;        # toolbox-thimble + toolbox-unity-6000.6.9f1
  workbench.projects.unity.thimble.cpus = "4";           # container envs: default caps (cpus, memory)
  workbench.user = "claude";                             # the account that owns git remotes
  workbench.projects.unity.thimble.gitRemote.enable = true;   # ~claude/repos/thimble.git, see below
  workbench.projects.decomp.ps2.lombyte.enable = true;   # lombyte-env + decomp-ps2-env + decomp-env
  workbench.projects.rust.mimi.enable = true;            # mimi-env + rust-env
  workbench.projects.rust.enable = true;                 # a base alone: the bare toolchain
}
```

Enabling a project installs its launcher (`<name>-env`, or `toolbox-<name>` for containers) and
its whole chain of bases system-wide; a disabled one adds nothing. A container's image is a stream
script in the closure, so the host build realises its packages and the first job only runs
`podman load`. The module generates the options from the registries: adding a base or project
needs no module edit. `nix run .#<name>` and `nix develop .#<name>` work as before, for bases too.

A project's `gitRemote.enable` gives it a bare git repo on the host, so lanes push to the box over
the account's existing ssh instead of syncing through a third party:

```sh
git push <host>:repos/thimble.git HEAD:refs/lanes/<lane>
```

A oneshot unit (`workbench-git-<project>`, run as `workbench.user`) creates
`~/repos/<project>.git` with `git init --bare` only when it is missing, and a checkout cache at
`~/.cache/workbench-git/<project>`. The project's toolbox mounts the repo read-only and the cache
read-write, each at its host path (a worktree made on either side resolves on the other), and sets
`WORKBENCH_GIT_REPO` and `WORKBENCH_GIT_CACHE`. A post-receive hook deletes `refs/lanes/*` whose tip
commit is older than `gitRemote.pruneLanesAfterDays` (default 14; `null` = no hook), never a ref
the same push updated. Git LFS objects are not stored there: the repo holds plain git objects only.

## Tools

| Package | Command | What it is |
| --- | --- | --- |
| `ghidra.ps2` | `ghidra-ps2` | Ghidra 12.0.4 + [ghidra-emotionengine-reloaded](https://github.com/chaoticgd/ghidra-emotionengine-reloaded) (EE processor, STABS) |
| `ghidra.ps1` | `ghidra-ps1` | Ghidra 12.0.4 + [ghidra_psx_ldr](https://github.com/lab313ru/ghidra_psx_ldr) (PS-X EXE, GTE, Psy-Q signatures and types) |
| `ghidra.psp` | `ghidra-psp` | Ghidra 12.0.4 + [ghidra-allegrex](https://github.com/kotcrab/ghidra-allegrex) (Allegrex/VFPU, PSP ELF/PRX loader, NID names) |
| `objdiff` | `objdiff-cli` | per-function object diffs and progress reports; in every env |
| `binutils-mips-ps2` | `mips-ps2-decompals-*` | R5900-aware binutils (as, ld, objcopy, objdump, ...); in PS2 envs |
| (nixpkgs) | `spatch` | Coccinelle, type-aware renames across C; in every env |
| `rename-field` | `rename-field STRUCT OLD NEW [PATH...]` | IDA-style field rename: only where the type really is that struct (Coccinelle); prints what it couldn't reach (macro args, unparseable code) |
| `ccc` | `stdump`, `uncc`, `demangle` | PS2 symbol tables: STABS/ELF/SNDLL types and signatures, skeleton sources, GCC 2.x demangling; in PS2 envs |
| `decomp-guard` | `decomp-guard install` / `check` | pre-commit hook that refuses game data (extensions, boot-executable names, ELF/PS-X EXE/ISO/ROM bytes, generated paths, big binaries, text files over 5 MB, mostly-Japanese text such as extracted script dumps); plain bash, also runs without Nix; in every env |
| `lane-merge` | `lane-merge resolve` / `check [--fix]` / `fix-includes` / `alias-undefined LOG` | merging parallel lanes in a splat decomp: union-resolves symbol files and notes, takes the C side over a leftover INCLUDE_ASM, finds one address with two names, renames INCLUDE_ASMs another lane renamed, aliases old names callers still use; in every env |
| `decomp-where` | `decomp-where TARGET BUILT MAP` | when a build stops matching: the first symbols that moved (and the last one that didn't), or every function holding differing bytes; ELF, PS-X EXE or raw; in every env |
| `split-units` | `split-units ASM... --range LO HI --rom-delta D --rodata LO HI` | cuts code with no vtables into plausible translation units (splat yaml lines): only where no .rodata literal is shared across the cut; `--size-only` for libraries; in every env |
| `sjis-strings` | `sjis-strings FILE...` | Japanese (Shift-JIS) strings in an ELF's data sections or any file, as TSV with the space each has; in every env |
| `compiler-sweep` | `compiler-sweep SNIPPET --target ELF --addr A [--name F]` | compiles one function with every EE-GCC under `$DECOMP_COMPILERS`, as C and C++, with/without `-Wa,-g`, with each other build's assembler, and ranks the variants against the target: finds a unit's toolchain in a minute; in PS2 envs |
| (nixpkgs) | `vgmstream-cli` | game audio (Sony XWB/ADS/VAG, ...) to WAV; in PS2 envs |
| `perm-lines` | `perm-lines SRC --cc CMD --symbol NAME --target-elf ELF --addr A` | statement-order brute force for MIPS, C or C++ (decomp-permuter is C only): reorders the lines marked `//@p`, compiles in parallel, reads objects without objdump, hill-climbs on swaps past 5040 orders and prints the closest order; in every env |
| `old-gcc.*` | (folders) | old console GCCs from decompals/old-gcc, e.g. `old-gcc.gcc-2_8_1-psx` |
| `ee-gcc.*` | (folders) | Sony EE-GCC builds from decomp.me's mirror (2.96, 2.9-991111/-01/a, 2.9-990721, 3.2-040921), under `$DECOMP_COMPILERS` in PS2 envs |
| `maspsx` | `maspsx` | Psy-Q assembler behaviour for GNU as (PS1) |
| `asm-differ` | `asm-differ` | quick per-function terminal diffs (diff.py) |
| `binutils-mipsel` | `mipsel-linux-gnu-*` | little-endian MIPS binutils (PS1; PSP too: `as -march=allegrex`, `objdump -m mips:allegrex`) |
| `pspdecrypt` | `pspdecrypt` | decrypts retail PSP executables (`~PSP` EBOOT.BIN, PRX) to plain ELF; UMDs zero the plain BOOT.BIN; in PSP envs |
| `binutils-allegrex` | `psp-as`, `psp-ld`, `psp-objdump`, ... | [pspdev binutils](https://github.com/pspdev/binutils-gdb) 2.44 with the VFPU (mainline has the Allegrex, not its vector unit); in PSP envs |
| `psp-compilers.*` | (folders) | PSP compilers from decomp.me's mirror (SNC 1.2.7503.0, mwccpsp 3.0.1 builds 121-219, psp-gcc 1.3.1/1.7.1), under `$DECOMP_COMPILERS` in PSP envs |

`ghidra-<platform> analyze BINARY OUTDIR` runs headless: import, auto-analysis, then
`OUTDIR/functions.json` (every function), `OUTDIR/symbol_addrs.txt` (named ones, splat format)
and the Ghidra project. Defined in [pkgs/ghidra/default.nix](pkgs/ghidra/default.nix); more
platforms (N64, GameCube/Wii, NDS, GBA) once their extensions build for nixpkgs' Ghidra.

PS1 projects use [lib/platforms/ps1.nix](lib/platforms/ps1.nix) (`lib.platforms.ps1.mkEnv`): mipsel
binutils, maspsx, asm-differ, ghidra-ps1, just and uv, plus the old PS1 compilers as folders under
`$DECOMP_COMPILERS` (gcc-2.8.1-psx, ...; link a project's `tools/<name>` there).

PS2 projects use [lib/platforms/ps2.nix](lib/platforms/ps2.nix) (`lib.platforms.ps2.mkEnv`): the
shared base plus the same PS2 toolbox everywhere (binutils-mips-ps2, ccc, ghidra-ps2, compiler-sweep, vgmstream, and the EE-GCC builds under `$DECOMP_COMPILERS`). Its header has PS2 matching notes (mixed toolchains in one game, the GNU as 2.10 `lui` bug).

Every project builds on [lib/mkDecompEnv.nix](lib/mkDecompEnv.nix) (the shared base: gcc
multilib, the tools to build old compilers, ninja, Python with decomp-permuter's packages).

## Use (flake)

    nix run github:conor-sometimes/workbench#bokura-no-kazoku -- -c 'make'   # a command in an env
    nix develop github:conor-sometimes/workbench#crash-bash                  # an interactive shell in it
    nix build github:conor-sometimes/workbench#ghidra-ps2                    # any tool

`flake.lock` is the one nixpkgs pin (default.nix reads it too; bump with `nix flake update`). [flake.nix](flake.nix) re-exposes default.nix and lists nothing by hand: add a package or project to default.nix and it appears in the flake.

## Use (without flakes)

From a project clone:

    nix-shell -A projects.lombyte.shell /path/to/workbench   # or: nix-build -A projects.lombyte.run

On NixOS, add the package to `environment.systemPackages`:

    (import (fetchTarball "https://github.com/conor-sometimes/workbench/archive/<rev>.tar.gz")
      { inherit pkgs; }).projects.lombyte.run

## Rules

- No game data, no copyrighted binaries: only Nix expressions with upstream URLs and
  SHA-256 pins, the same downloads each project's own setup scripts make.
- Toolchain pins follow each project's own pins exactly; a pin-check flags drift.
- x86_64-linux (the PS1/PS2 toolchains are x86 Linux and Windows binaries).

## Layout

    default.nix         entry point (non-flake): [default.nix](default.nix)
    lib/mkDecompEnv.nix the common environment base every project builds on: [lib/](lib/)
    pkgs/               shared decomp tools (ghidra-<platform>, ...)
    projects/<name>/    one project's environment and toolchain

## Adding a project

    # projects/<name>/default.nix
    { pkgs, lib }:
    {
      env = lib.mkDecompEnv {
        name = "<name>";             # -> a <name>-env command
        wine = false;                # true if a compiler or assembler is a Windows .exe
        packages = p: [ ];           # anything else the build needs
      };
    }

then one line in default.nix: `<name> = import ./projects/<name> { inherit pkgs lib; };`

## Licence

Licensed under the GNU General Public License v3.0 or later (see [LICENSE](LICENSE)). The packages only fetch upstream tools and compilers from their own release pages; each keeps its own licence.
