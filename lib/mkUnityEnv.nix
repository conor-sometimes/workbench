# mkUnityEnv: the Unity base, one Unity environment keyed by editor version, usable by any Unity
# project. It carries the .NET SDK (a Unity project's pure-C# half, its tests and tools, builds with
# it) and, from stage 1, the Linux Unity Editor at `version` with `modules`. A container base: a
# project sits on it with `base = "unity"; baseArgs.version = "...";` and its image is layered on
# this one (lib/mkToolbox.nix), so two projects on one version share every layer of it.
#
#   lib.mkUnityEnv { version = "6000.6.9f1"; modules = [ "linux-il2cpp" ]; }   # -> toolbox-unity-6000.6.9f1
#
# STAGE 1 PENDING (Thimble stage 1): the Editor is not in it yet and nothing of Unity is downloaded;
# today the env is the .NET half only. `placeholder` says so (the NixOS module warns when the base is
# enabled on its own). Stage 1 adds the Editor (plus `modules`) to `packages` below (or a `.run` of
# its own if it must be an FHS env) and drops `placeholder`; version, modules and the bases wiring stay.
{ pkgs, mkToolbox, toolsets }:

let
  mk = spec@{
    version,                 # editor version, e.g. "6000.6.9f1"
    modules ? [ ],           # editor modules (build support), e.g. [ "linux-il2cpp" "webgl" ]
    resources ? { },         # default caps, as mkToolbox
  }:
  let
    tb = mkToolbox {
      name = "unity-${version}";
      inherit resources;
      packages = p: toolsets.dotnet.packages p;   # stage 1: + the Editor at `version` with `modules`
      env = {
        DOTNET_CLI_TELEMETRY_OPTOUT = "1";
        DOTNET_NOLOGO = "1";
        UNITY_VERSION = version;
      };
    };
  in
  tb // {
    inherit version modules;
    egress = toolsets.dotnet.egress;   # stage 1: + Unity's download hosts
    placeholder = "the Unity Editor itself is not in it yet (Thimble stage 1); this is its .NET half";
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
