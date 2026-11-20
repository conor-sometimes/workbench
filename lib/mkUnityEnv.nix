# mkUnityEnv: the Unity base, one Unity environment keyed by editor version, usable by any Unity
# project. It carries the .NET SDK (a Unity project's pure-C# half, its tests and tools, builds with
# it) and, from stage 1, the Linux Unity Editor at `version` with `modules`. A container base: a
# project sits on it with `base = "unity"; baseArgs.version = "...";` and its image is layered on
# this one (lib/mkToolbox.nix), so two projects on one version share every layer of it.
#
#   lib.mkUnityEnv { version = "6000.6.9f1"; modules = [ "linux-il2cpp" ]; }   # -> toolbox-unity-6000.6.9f1
#
# It also carries Blender, headless, for the art half of a Unity project (model exports, checks, sheets).
#
# STAGE 1 (S1b): the Linux Editor at `version` is in the image, unpacked from Unity's tarball
# (lib/unityEditor.nix, pinned by sha256, fetched at build time, unfree, never redistributed) with the
# libraries it dlopens on a wrapper-local LD_LIBRARY_PATH. A rootless podman container cannot run
# bwrap (buildFHSEnv), so the image gets the glibc loader at /lib64 instead (`loader`, see mkToolbox).
# In the container: `Unity` (the Editor), `unity-fhs CMD...` (any glibc binary, e.g. the `unity` CLI
# or the Licensing Client, with the same libraries and CA bundle), THIMBLE_UNITY = the Editor wrapper.
# `modules` (build support) are not unpacked yet: S1 is -batchmode -nographics only.
{ pkgs, mkToolbox, toolsets }:

let
  unityEditor = import ./unityEditor.nix { inherit pkgs; };
  mk = spec@{
    version,                 # editor version, e.g. "6000.6.9f1"
    modules ? [ ],           # editor modules (build support), e.g. [ "linux-il2cpp" "webgl" ]
    resources ? { },         # default caps, as mkToolbox
  }:
  let
    editor = unityEditor { inherit version; };
    tb = mkToolbox {
      name = "unity-${version}";
      inherit resources;
      # The GPU (Vega 11 on hokkaido, any render node elsewhere): Blender's Eevee and, from stage 1, the
      # Unity Editor draw headless over EGL on Mesa. The account needs the render/video groups on the host.
      devices = [ "/dev/dri" ];
      gpuDriver = pkgs.buildEnv { name = "opengl-driver"; paths = [ pkgs.mesa ]; };
      # Blender (headless `blender -b`): art lanes run model exports, model checks and review-sheet
      # renders here instead of on a Mac. Rendering uses Eevee over EGL/Mesa where a GPU is passed in,
      # else Workbench or Cycles on the CPU. The Macs run Blender 5.3; keep this in step when bumping.
      packages = p: toolsets.dotnet.packages p ++ [ p.blender editor ]
        ++ (with p; [ cacert cpio p7zip xz gnutar ]);   # cpio/7z/xz: unpacking Editor modules
      loader = true;   # /lib64/ld-linux-x86-64.so.2, for the glibc-native Editor, Licensing Client and `unity` CLI
      env = {
        THIMBLE_UNITY = editor.binary;   # tools/paths.py unity_editor()
        DOTNET_CLI_TELEMETRY_OPTOUT = "1";
        DOTNET_NOLOGO = "1";
        UNITY_VERSION = version;
      };
    };
  in
  tb // {
    inherit version modules;
    devices = tb.devices; gpuDriver = tb.gpuDriver;
    # + Unity's hosts: the Editor tarball and modules, sign-in and the licence service
    egress = toolsets.dotnet.egress ++ [ "download.unity3d.com" "unity.com" "unity3d.com" ];
    inherit (tb) env loader;
    options = l: tb.options l // {
      version = l.mkOption {
        type = l.types.str; default = version;
        description = "Unity Editor version of the bare unity env.";
      };
      modules = l.mkOption {
        type = l.types.listOf l.types.str; default = modules;
        description = "Unity Editor modules of the bare unity env.";
      };
    };
    # s: any of { version; modules; cpus; memory; }
    override = s: mk {
      version = s.version or version;
      modules = s.modules or modules;
      resources = resources // removeAttrs s [ "version" "modules" ];
    };
  };
in
mk
