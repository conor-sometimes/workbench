# mkToolbox: a per-project, on-demand container toolbox. Nix builds a small OCI image (the durable,
# deduplicated artifact — it lives in the store, no container runs until a job does); `.run` spins a
# throwaway `podman run --rm` container with CPU/memory caps, the project bind-mounted at /work, runs
# one command, and tears the container down. Many toolboxes = many cheap images, zero idle containers.
#
# This is a different lifecycle from the always-on podman boxes (agent containment): those are
# long-lived and ssh-in; these exist only while a command runs. For a trusted project the container
# is for reproducibility + resource caps, not isolation.
#
#   tb = mkToolbox { name = "pktlib"; packages = p: [ p.uv p.python313 ]; };
#   nix run <repo>#pktlib -- just test                 # in the repo, on-demand container
#   nix run <repo>#pktlib -- --cpus 4 --memory 8g -- just soak 1
#
# Network: the container gets the host account's own egress, nothing more. On a contained host the
# account's proxy listens on the host's loopback (127.0.0.1:PORT), which a container's 127.0.0.1 is
# not; so the runner gives the container pasta networking with the host loopback mapped to
# 169.254.1.2 and points the proxy variables there. pasta's sockets belong to the account, so its
# wall and allow-list still apply. Never --network host: processes under a non-root container uid run
# as one of the account's subuids, which a uid-owner wall does not match. `--offline` = no network.
#
# Queue: `queue = "heavy"` (or `--queue NAME`) takes a per-account flock before the container starts,
# so two heavy jobs of any toolbox sharing that queue name run one after the other, not at once.
{ pkgs }:

spec@{
  name,
  packages ? (_: [ ]),          # project tools in the image (a function of nixpkgs)
  resources ? { },              # { cpus = 4; memory = "8g"; } defaults for the run
  env ? { },                    # extra container environment (NAME = "value")
  queue ? "",                   # default queue name ("" = none): one job per queue at a time
  tag ? null,                   # null = the image's own store hash (a rebuild never reuses a stale image)
}:

let
  cpus = toString (resources.cpus or 4);
  memory = resources.memory or "8g";

  # The image: a minimal userland (bash/coreutils/git + TLS roots, /usr/bin/env, /bin/sh, a passwd
  # for tools that look the user up, a writable /tmp) plus the project's tools.
  image = pkgs.dockerTools.buildLayeredImage {
    name = "toolbox-${name}";
    inherit tag;
    contents = (with pkgs; [ bashInteractive coreutils gitMinimal cacert ])
      ++ (with pkgs.dockerTools; [ usrBinEnv binSh fakeNss ])
      ++ packages pkgs;
    extraCommands = "mkdir -p -m 1777 tmp";
    config.WorkingDir = "/work";
  };

  # Extra `-e NAME=value` flags for podman, from `env`.
  envFlags = pkgs.lib.concatStringsSep " "
    (pkgs.lib.mapAttrsToList (k: v: "-e ${pkgs.lib.escapeShellArg "${k}=${v}"}") env);

  run = pkgs.writeShellApplication {
    name = "toolbox-${name}";
    runtimeInputs = [ pkgs.podman pkgs.util-linux ];
    text = ''
      img="toolbox-${name}:${image.imageTag}"
      cpus="${cpus}"; memory="${memory}"; repo="$PWD"; queue="${queue}"; offline=0; cname=""
      extra=()
      # options before `--`: --cpus N | --memory M | --repo DIR | --queue NAME | --no-queue
      #                      | --offline | --env NAME=VALUE (repeatable) | --name CONTAINER
      #                      | --podman-arg ARG (repeatable; e.g. --cpu-shares=64 for a background job)
      while [ $# -gt 0 ] && [ "$1" != "--" ]; do
        case "$1" in
          --cpus)     cpus="$2";   shift 2 ;;
          --memory)   memory="$2"; shift 2 ;;
          --repo)     repo="$2";   shift 2 ;;
          --queue)    queue="$2";  shift 2 ;;
          --no-queue) queue="";    shift ;;
          --offline)  offline=1;   shift ;;
          --env)      extra+=(-e "$2"); shift 2 ;;
          --name)     cname="$2";  shift 2 ;;
          --podman-arg) extra+=("$2"); shift 2 ;;
          *) break ;;
        esac
      done
      [ "''${1:-}" = "--" ] && shift
      [ "''${1:-}" = "-c" ] && shift   # accept the decomp envs' `-- -c 'cmd'` form too, so both read alike
      [ $# -gt 0 ] || { echo "usage: toolbox-${name} [--cpus N --memory M --repo DIR --queue Q --offline --env K=V --name C --podman-arg A] -- [-c] <cmd...>" >&2; exit 2; }

      # load the nix-built image into podman once per build (its tag is the image's store hash, so a
      # rebuilt image is a new tag), then drop this toolbox's older tags (in-use ones stay)
      if ! podman image exists "$img"; then
        podman load -q -i ${image} >/dev/null
        podman images --format '{{.Repository}}:{{.Tag}}' "localhost/toolbox-${name}" | grep -v ":${image.imageTag}$" \
          | xargs -r podman rmi >/dev/null 2>&1 || true
      fi

      # network: the account's proxy through pasta's host-loopback map (see the header), or none
      net=(--http-proxy=false)
      if [ "$offline" = 1 ]; then
        net+=(--network none)
      else
        p="''${https_proxy:-''${HTTPS_PROXY:-}}"
        case "$p" in
          *://127.0.0.1:*|*://localhost:*)
            port="''${p##*:}"; port="''${port%%/*}"; u="http://169.254.1.2:$port"
            net+=(--network "pasta:--map-host-loopback,169.254.1.2"
                  -e "http_proxy=$u" -e "https_proxy=$u" -e "HTTP_PROXY=$u" -e "HTTPS_PROXY=$u"
                  -e "no_proxy=localhost,127.0.0.1" -e "NO_PROXY=localhost,127.0.0.1") ;;
          "") ;;
          *) net+=(-e "http_proxy=$p" -e "https_proxy=$p" -e "HTTP_PROXY=$p" -e "HTTPS_PROXY=$p") ;;
        esac
      fi
      [ -n "$cname" ] && net+=(--name "$cname")

      # a persistent per-toolbox cache (package downloads survive between runs); /work is the project, rw
      cache="''${XDG_CACHE_HOME:-$HOME/.cache}/toolbox-${name}"; mkdir -p "$cache" "$repo/out"

      # the queue: one job per queue name at a time, across toolboxes and checkouts
      if [ -n "$queue" ]; then
        qdir="''${XDG_STATE_HOME:-$HOME/.local/state}/toolbox-queue"; mkdir -p "$qdir"
        exec 9>"$qdir/$queue.lock"
        if ! flock -n 9; then
          echo "toolbox-${name}: queued behind another '$queue' job; waiting..." >&2
          flock 9
          echo "toolbox-${name}: starting" >&2
        fi
      fi

      # shellcheck disable=SC2086
      exec podman run --rm \
        --cpus="$cpus" --memory="$memory" \
        -v "$repo":/work -v "$cache":/cache -w /work \
        -e HOME=/tmp -e XDG_CACHE_HOME=/cache -e UV_CACHE_DIR=/cache/uv \
        -e SSL_CERT_FILE=${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt \
        "''${net[@]}" ${envFlags} "''${extra[@]}" \
        "$img" bash -lc "$*"
    '';
  };
in
# the common project shape (same as a decomp env from mkDecompEnv): a runnable `run`, an optional
# interactive `shell`, an optional `image`, and the `runtime` tag. The flake treats every project
# alike by this shape — a decomp env and a container toolbox are just two runtimes.
{
  inherit name image run resources;
  runtime = "container";
  shell = null;   # `nix develop` into a container isn't offered; use the FHS envs for that
}
