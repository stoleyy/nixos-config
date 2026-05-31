# Qubes-style browser compartmentalization.
# Each trust domain is a fully isolated Brave instance with its own data dir,
# cookies, history, extensions, and credentials. Color-coded window frames
# make the active domain visible at a glance — like Qubes window borders.
#
# Domains:
#   vault      (GREEN)  — banking, finance, sensitive accounts. LAN-blocked.
#   personal   (BLUE)   — daily browsing, YouTube, social media. Standard.
#   untrusted  (RED)    — random links, sketchy sites. LAN-blocked + Tor egress.
#   disposable (ORANGE) — one-shot session, wiped on exit. LAN-blocked + Tor.
#
# Two boundaries per domain:
#   1. Filesystem — every domain runs inside a bubblewrap jail with a fresh
#      tmpfs $HOME, binding back ONLY its own profile dir. ~/.ssh, ~/.gnupg, the
#      OTHER Brave profiles, and the KeePassXC .kdbx are masked, so a browser RCE
#      can't read across domains or steal keys (closes weakpoint W2 for the
#      browser — see docs/security-hardening-stance.md). Same UID, no UX cost.
#   2. Network — vault launches via `sg vault` (LAN dropped, no Tor); untrusted
#      and disposable via `sg untrusted` (LAN dropped + Tor SOCKS, Tor-over-VPN).
#      Both GIDs are dropped from the LAN in modules/compartments.nix; stoleyy
#      must be in both groups (modules/base.nix) or `sg` refuses to switch.
{
  pkgs,
  lib,
  theme,
  ...
}:

let
  inherit (theme) hexToRgb colors;

  # ── Trust domain definitions ──
  # isolated = true → runs under "untrusted" GID (LAN blocked via nftables)
  domains = {
    vault = {
      color = "#1B5E20"; # intentional: trust-zone green, not theme color
      frame = "#2E7D32"; # intentional: trust-zone green, not theme color
      label = "Vault";
      description = "Banking, finance, sensitive accounts";
      dataDir = "Brave-Vault";
      lanBlocked = true; # LAN dropped via `sg vault` (no Tor — banking)
    };
    personal = {
      color = colors.bg1; # Sanctuary indigo — flows from lib/theme.nix
      frame = colors.bg2;
      label = "Personal";
      description = "Daily browsing, YouTube, social media";
      dataDir = "Brave-Browser"; # default Brave profile
    };
    untrusted = {
      color = "#B71C1C"; # Dark red
      frame = "#C62828";
      label = "Untrusted";
      description = "Random links, unknown sites";
      dataDir = "Brave-Untrusted";
      isolated = true; # LAN blocked
    };
    disposable = {
      color = "#E65100"; # Dark orange
      frame = "#F57C00";
      label = "Disposable";
      description = "One-shot session, wiped on exit";
      dataDir = "Brave-Disposable";
      ephemeral = true;
      isolated = true; # LAN blocked
    };
  };

  # ── bubblewrap FS-jail (closes weakpoint W2: same-UID blast radius) ──
  # Every domain runs in a bwrap sandbox with a fresh tmpfs $HOME, binding back
  # ONLY its own profile dir + the sockets the browser needs. This masks ~/.ssh,
  # ~/.gnupg, ~/.config/sops, the OTHER Brave profiles, and the KeePassXC .kdbx
  # from a browser RCE — same UID, no separate-$HOME UX cost. We use bwrap
  # (non-setuid) rather than firejail (setuid) for the browser jail, leave
  # Chromium's own user-namespace sandbox intact (no --unshare-user), and keep
  # the net namespace shared so the Tor SOCKS proxy still resolves. The
  # `sg <group>` switch stays OUTSIDE bwrap so the socket-GID match in
  # modules/compartments.nix still fires.
  bwrap = "${pkgs.bubblewrap}/bin/bwrap";

  # graphene-hardened-malloc, LIGHT variant, scoped to the browser via LD_PRELOAD
  # — never system-wide (would break Wine/Steam allocators + W^X).
  ghmLight = "${pkgs.graphene-hardened-malloc}/lib/libhardened_malloc-light.so";

  mkBraveLauncher =
    name: domain:
    let
      # untrusted/disposable → Tor egress + deliberately NO KeePassXC path.
      heavy = domain.isolated or false;
    in
    pkgs.writeShellScript "brave-${name}-jailed" ''
      set -u
      DATA_DIR="$HOME/.config/BraveSoftware/${domain.dataDir}"

      # Default-deny: fresh tmpfs $HOME, then bind back only what is needed.
      # Order matters — `--tmpfs "$HOME"` must precede the bind of DATA_DIR.
      args=(
        --ro-bind /nix/store /nix/store
        --ro-bind /run/current-system /run/current-system
        --ro-bind /etc /etc
        --proc /proc
        --dev /dev
        --dev-bind /dev/dri /dev/dri
        --tmpfs /tmp
        --tmpfs "$HOME"
        --bind "$DATA_DIR" "$DATA_DIR"
        --bind-try "$HOME/Downloads" "$HOME/Downloads"
        --bind-try "$HOME/.cache/nv-shader-cache" "$HOME/.cache/nv-shader-cache"
        --ro-bind-try /run/dbus/system_bus_socket /run/dbus/system_bus_socket
        --die-with-parent
        --new-session
        --unshare-pid
        --unshare-ipc
        --unshare-uts
        --unshare-cgroup
        --setenv LD_PRELOAD "${ghmLight}"
      )

      # NVIDIA device nodes — bind only those that exist.
      for n in /dev/nvidia0 /dev/nvidiactl /dev/nvidia-modeset \
               /dev/nvidia-uvm /dev/nvidia-uvm-tools; do
        if [ -e "$n" ]; then args+=(--dev-bind "$n" "$n"); fi
      done

      # Wayland + audio + session-bus sockets — bind only if present.
      if [ -n "''${WAYLAND_DISPLAY:-}" ] && [ -e "$XDG_RUNTIME_DIR/$WAYLAND_DISPLAY" ]; then
        args+=(--bind "$XDG_RUNTIME_DIR/$WAYLAND_DISPLAY" "$XDG_RUNTIME_DIR/$WAYLAND_DISPLAY")
      fi
      for s in pipewire-0 pulse bus; do
        if [ -e "$XDG_RUNTIME_DIR/$s" ]; then
          args+=(--bind "$XDG_RUNTIME_DIR/$s" "$XDG_RUNTIME_DIR/$s")
        fi
      done
      ${lib.optionalString (!heavy) ''
        # vault/personal only: let KeePassXC-browser reach the proxy socket
        # (the manifest + proxy binary are already under bound paths). untrusted
        # /disposable deliberately get NO path to the password manager.
        if [ -e "$XDG_RUNTIME_DIR/org.keepassxc.KeePassXC.BrowserServer" ]; then
          args+=(--bind "$XDG_RUNTIME_DIR/org.keepassxc.KeePassXC.BrowserServer" \
                        "$XDG_RUNTIME_DIR/org.keepassxc.KeePassXC.BrowserServer")
        fi
      ''}

      # `brave` stays bare so it resolves (via inherited PATH) to the system
      # wrapper in /run/current-system/sw/bin, preserving the apps.nix override.
      exec ${bwrap} "''${args[@]}" -- brave \
        --user-data-dir="$DATA_DIR" \
        --class="brave-${name}" \
        ${lib.optionalString heavy "--proxy-server=socks5://127.0.0.1:9050"} "$@"
    '';

  # ── Wrapper script generator ──
  mkBraveWrapper =
    name: domain:
    let
<<<<<<< HEAD
      isolated = domain ? isolated && domain.isolated;
      # WebRTC can gather ICE candidates that bypass the SOCKS/VPN egress path
      # and reveal the local LAN or tunnel-internal IP. Isolated (Tor'd) domains
      # force every WebRTC route through the proxy only; the VPN domains keep
      # WebRTC working (video calls) but hide the local LAN address.
      webrtcPolicy = if isolated then "disable_non_proxied_udp" else "default_public_interface_only";
||||||| c2a8d20
=======
      launcher = mkBraveLauncher name domain;
      # vault → `sg vault` (LAN-blocked, NO Tor — banking + Tor = CAPTCHA hell).
      # untrusted/disposable → `sg untrusted` (LAN-blocked + Tor via launcher).
      group =
        if (domain.lanBlocked or false) then
          "vault"
        else if (domain.isolated or false) then
          "untrusted"
        else
          null;
>>>>>>> 82ddfbbd0695ff07ea017b15bc57e35402d64074
    in
    pkgs.writeShellScriptBin "brave-${name}" ''
      DATA_DIR="''${HOME}/.config/BraveSoftware/${domain.dataDir}"
      ${lib.optionalString (domain ? ephemeral && domain.ephemeral) ''
        # Disposable: wipe previous session, create fresh
        rm -rf "$DATA_DIR"
      ''}
      mkdir -p "$DATA_DIR"
      ${lib.optionalString (domain ? ephemeral && domain.ephemeral) ''
        # Trap: wipe on exit regardless of how browser closes
        trap 'rm -rf "$DATA_DIR"' EXIT INT TERM
      ''}

      # Seed the theme on first run (idempotent — only writes if missing)
      THEME_DIR="$DATA_DIR/Default/Extensions/qubes_theme_${name}"
      if [ ! -d "$THEME_DIR" ]; then
        mkdir -p "$THEME_DIR/1.0"
        cp "${themePath name domain}/manifest.json" "$THEME_DIR/1.0/"
      fi

      # Seed initial preferences — Brave reads this once on first launch
      if [ ! -f "$DATA_DIR/initial_preferences" ]; then
        printf '{"brave":{"sidebar":{"sidebar_show_option":2},"vertical_tabs":{"floating":true}}}\n' > "$DATA_DIR/initial_preferences"
      fi

      ${
<<<<<<< HEAD
        if isolated then
          # Isolated domains: switch to the "untrusted" GID (LAN dropped by
          # modules/compartments.nix) AND route through the local Tor SOCKS
          # proxy (modules/tor-isolation.nix) → Tor-over-VPN egress. Chromium
          # does remote DNS over the socks5 proxy, so no DNS leak.
          ''exec sg untrusted -c "brave --user-data-dir=\"$DATA_DIR\" --class=brave-${name} --proxy-server=socks5://127.0.0.1:9050 --webrtc-ip-handling-policy=${webrtcPolicy} $*"''
||||||| c2a8d20
        if domain ? isolated && domain.isolated then
          # Isolated domains: switch to the "untrusted" GID (LAN dropped by
          # modules/compartments.nix) AND route through the local Tor SOCKS
          # proxy (modules/tor-isolation.nix) → Tor-over-VPN egress. Chromium
          # does remote DNS over the socks5 proxy, so no DNS leak.
          ''exec sg untrusted -c "brave --user-data-dir=\"$DATA_DIR\" --class=brave-${name} --proxy-server=socks5://127.0.0.1:9050 $*"''
=======
        if group != null then
          ''
            # Switch to the "${group}" GID (modules/compartments.nix drops its
            # LAN egress), then launch the bubblewrap-jailed browser. printf %q
            # keeps any URL args intact across the `sg -c` shell re-parse.
            if [ "$#" -gt 0 ]; then argsq=$(printf '%q ' "$@"); else argsq=""; fi
            exec sg ${group} -c "exec ${launcher} $argsq"''
>>>>>>> 82ddfbbd0695ff07ea017b15bc57e35402d64074
        else
<<<<<<< HEAD
          ''exec brave --user-data-dir="$DATA_DIR" --class="brave-${name}" --webrtc-ip-handling-policy=${webrtcPolicy} "$@"''
||||||| c2a8d20
          ''exec brave --user-data-dir="$DATA_DIR" --class="brave-${name}" "$@"''
=======
          ''exec ${launcher} "$@"''
>>>>>>> 82ddfbbd0695ff07ea017b15bc57e35402d64074
      }
    '';

  # ── Theme manifest generator (Chromium extension theme) ──
  mkThemeManifest =
    _: domain:
    builtins.toJSON {
      manifest_version = 3;
      version = "1.0";
      name = "Qubes ${domain.label}";
      description = "${domain.label} domain — ${domain.description}";
      theme = {
        colors = {
          frame = hexToRgb domain.frame;
          frame_inactive = hexToRgb domain.color;
          frame_incognito = hexToRgb domain.frame;
          frame_incognito_inactive = hexToRgb domain.color;
          toolbar = hexToRgb domain.color;
          toolbar_text = [
            255
            255
            255
          ];
          tab_text = [
            255
            255
            255
          ];
          tab_background_text = [
            200
            200
            200
          ];
          bookmark_text = [
            255
            255
            255
          ];
          ntp_background = hexToRgb domain.color;
          ntp_text = [
            255
            255
            255
          ];
          omnibox_background = hexToRgb domain.color;
          omnibox_text = [
            255
            255
            255
          ];
        };
      };
    };

  # Write theme manifest to nix store
  themePath = name: domain: pkgs.writeTextDir "manifest.json" (mkThemeManifest name domain);

  # ── Desktop entry generator ──
  mkDesktopEntry = name: domain: {
    name = "Brave (${domain.label})";
    genericName = "Web Browser — ${domain.label} Domain";
    comment = domain.description;
    exec = "brave-${name} %U";
    terminal = false;
    type = "Application";
    icon = "brave-browser";
    categories = [
      "Network"
      "WebBrowser"
    ];
    settings.StartupWMClass = "brave-${name}";
    mimeType = lib.optionals (name == "personal") [
      "text/html"
      "x-scheme-handler/http"
      "x-scheme-handler/https"
    ];
  };

in
{
  home.packages = lib.mapAttrsToList mkBraveWrapper domains;

  xdg.desktopEntries = (lib.mapAttrs mkDesktopEntry domains) // {
    # Discord — untrusted domain (LAN blocked, VPN internet works)
    discord = {
      name = "Discord";
      genericName = "Chat — Untrusted Domain";
      comment = "Discord (LAN isolated)";
      exec = "discord %U";
      terminal = false;
      type = "Application";
      icon = "discord";
      categories = [
        "Network"
        "InstantMessaging"
      ];
      settings.StartupWMClass = "discord";
    };
  };
}
