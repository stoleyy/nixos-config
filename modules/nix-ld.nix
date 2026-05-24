# Foreign ELF ABI shim — lets pre-compiled Linux binaries run on NixOS via nix-ld.
{ pkgs, ... }:

{
  # Foreign (non-Nix) ELF binaries run via nix-ld. Defining `libraries`
  # REPLACES the upstream module default, so its default set is re-listed
  # below and then the Chromium/CEF runtime closure is added: prebuilt
  # Electron/CEF apps (e.g. openhuman) otherwise FATAL on a runtime dlopen
  # of libsoftokn3.so because nss/nspr aren't on the default nix-ld path.
  programs.nix-ld = {
    enable = true;
    libraries = with pkgs; [
      # --- nix-ld upstream defaults (re-listed: definition replaces default) ---
      zlib
      zstd
      stdenv.cc.cc
      curl
      openssl
      attr
      libssh
      bzip2
      libxml2
      acl
      libsodium
      util-linux
      xz
      systemd
      # --- NSS / NSPR: the fatal libsoftokn3.so dlopen ---
      nss
      nspr
      # --- glib / GTK stack ---
      glib
      gtk3
      gdk-pixbuf
      pango
      cairo
      atk
      at-spi2-atk
      at-spi2-core
      # --- IPC / printing ---
      dbus
      cups
      # --- graphics ---
      libdrm
      libgbm
      mesa
      libGL
      vulkan-loader
      expat
      libxkbcommon
      fontconfig
      freetype
      # --- audio ---
      alsa-lib
      libpulseaudio
      # --- X11 ---
      xorg.libX11
      xorg.libXcomposite
      xorg.libXdamage
      xorg.libXext
      xorg.libXfixes
      xorg.libXrandr
      xorg.libXrender
      xorg.libXtst
      xorg.libXi
      xorg.libXcursor
      xorg.libXScrnSaver
      xorg.libxcb
      xorg.libXau
      xorg.libXdmcp
      libxshmfence
    ];
  };
}
