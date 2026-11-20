# unityEditor: the Linux Unity Editor, unpacked from Unity's own tarball, plus the wrappers that let
# it run in a toolbox image (no /lib64 loader, no FHS /usr/lib there: the libraries it dlopens are
# found through LD_LIBRARY_PATH, set by the wrappers and nowhere else, so nix-built tools in the
# same image are unaffected). Unfree: the tarball is fetched from download.unity3d.com at build time,
# pinned by sha256, and never redistributed (no cache of it is published from here).
#
#   unityEditor { version = "6000.6.9f1"; }    # -> bin/Unity, bin/unity-fhs, Editor/ (the unpacked install)
#
# Bump: take the revision from the project's ProjectSettings/ProjectVersion.txt
# (m_EditorVersionWithRevision), add it to `editors` with the sha256 of the tarball
# (`nix-prefetch-url --type sha256 <url>`; the URL is below in `url`).
{ pkgs }:

let
  editors = {
    "6000.6.9f1" = {
      rev = "8c45277fb9c5";
      sha256 = "1shdvbvy3ca058crhksnqfkaaywc7lx5hs1j1hwnzpggslm9kpjv";
    };
  };

  libs = with pkgs; [
    stdenv.cc.cc.lib zlib openssl curl libxml2 util-linux.lib icu libpng freetype fontconfig
    gtk3 glib gdk-pixbuf cairo pango atk at-spi2-atk at-spi2-core dbus nss nspr alsa-lib libpulseaudio
    cups libcap libdrm libgbm libxkbcommon systemd expat libsecret krb5 gnutls
    libGL libglvnd mesa vulkan-loader
    xorg.libX11 xorg.libXcursor xorg.libXrandr xorg.libXi xorg.libXext xorg.libXfixes xorg.libXrender
    xorg.libXcomposite xorg.libXdamage xorg.libXinerama xorg.libXtst xorg.libxcb xorg.libXScrnSaver
  ];
in
{ version }:
let
  e = editors.${version} or (throw "unityEditor: no pin for ${version} in lib/unityEditor.nix");
  src = pkgs.fetchurl {
    url = "https://download.unity3d.com/download_unity/${e.rev}/LinuxEditorInstaller/Unity-${version}.tar.xz";
    inherit (e) sha256;
  };
  libPath = pkgs.lib.makeLibraryPath libs;
  editor = pkgs.stdenvNoCC.mkDerivation {
    pname = "unity-editor"; inherit version src;
    dontUnpack = true; dontFixup = true; dontStrip = true;
    nativeBuildInputs = [ pkgs.xz pkgs.gnutar ];
    installPhase = ''
      mkdir -p $out
      tar -xJf $src -C $out --no-same-owner --no-same-permissions
      chmod -R u+rwX,go+rX $out
      # the tarball holds ./Editor/Unity; ./Editor may sit at the root or under one directory
      if [ ! -e $out/Editor/Unity ]; then echo "unity-editor: no Editor/Unity in the tarball" >&2; ls $out >&2; exit 1; fi
    '';
  };
  # `unity-fhs CMD...`: run any glibc-native binary (the Editor, the Licensing Client, the `unity` CLI)
  # with the Editor's libraries on its library path, and the CA bundle for its TLS
  fhs = pkgs.writeShellScriptBin "unity-fhs" ''
    export LD_LIBRARY_PATH="${libPath}''${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
    export SSL_CERT_FILE="''${SSL_CERT_FILE:-${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt}"
    export VK_ICD_FILENAMES="''${VK_ICD_FILENAMES:-/run/opengl-driver/share/vulkan/icd.d/radeon_icd.x86_64.json}"
    exec "$@"
  '';
  unity = pkgs.writeShellScriptBin "Unity" ''
    exec ${fhs}/bin/unity-fhs ${editor}/Editor/Unity "$@"
  '';
in
pkgs.symlinkJoin {
  name = "unity-editor-env-${version}";
  paths = [ unity fhs ];
  passthru = { inherit editor libPath version; binary = "${unity}/bin/Unity"; };
}
