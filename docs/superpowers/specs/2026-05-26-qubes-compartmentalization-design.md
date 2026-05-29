# Qubes-Style NixOS Compartmentalization

Date: 2026-05-26
Status: Approved

## Summary

Transparent compartmentalization inspired by Qubes OS. Apps auto-launch into
the correct trust domain without user intervention. Network isolation via
GID-based nftables matching (preserves existing VPN kill switch). KeePassXC
fully offline via firejail. Visual enforcement via Hyprland border colors.

## Constraints

- ProtonVPN kernel WireGuard + nftables kill switch must remain intact
- UX unchanged — same keybinds, same rofi entries, same app names
- Wayland + NVIDIA GPU must work in all domains
- ~100ms max startup latency acceptable for sandboxed apps

## Architecture

### Trust Domains

| Domain | Network | LAN | Mechanism | Apps |
|--------|---------|-----|-----------|------|
| trusted | VPN | Yes | Default (no change) | Brave-vault, Brave-personal, Ghostty, Steam, Spotify, qBittorrent, Claude Code, file managers |
| untrusted | VPN | Blocked | `sg untrusted` + nftables GID match | Brave-untrusted, Brave-disposable, Discord |
| offline | None | None | firejail --net=none | KeePassXC |

### Network Isolation

GID-based nftables. A new table `inet compartments` at priority 50 (fires
after kill switch at -100):

```nftables
table inet compartments {
  chain output {
    type filter hook output priority 50; policy accept;
    meta skgid "untrusted" ip daddr { 192.168.0.0/16, 10.0.0.0/8, 172.16.0.0/12 } counter drop
    meta skgid "untrusted" ip6 daddr { fd00::/8, fe80::/10 } counter drop
  }
}
```

Flow:
1. Kill switch (priority -100): allows lo, LAN, VPN endpoint, protonvpn iface; drops rest
2. Compartments (priority 50): for untrusted GID, drops RFC1918/ULA destinations

Result: untrusted apps can reach internet (via VPN) but NOT local network.

### App Wrappers

All wrappers are `writeShellScriptBin` packages in home.packages. They shadow
the real binary name in PATH priority (home packages first).

**Untrusted apps** (Brave-untrusted, Brave-disposable, Discord):
```bash
exec sg untrusted -c "real-binary --class=app-name $*"
```

**Offline apps** (KeePassXC):
```bash
exec firejail --net=none --noprofile keepassxc "$@"
```

**Trusted apps**: No wrapper needed. Existing behavior unchanged.

### Visual Enforcement (Hyprland)

Window border colors per `class:` matching:

| Class pattern | Color | Meaning |
|---------------|-------|---------|
| `brave-vault` | #2E7D32 (green) | Sensitive/financial |
| `org.keepassxc.KeePassXC` | #2E7D32 (green) | Credentials (offline) |
| `brave-personal` | #0A094E (indigo) | Standard daily use |
| `brave-untrusted` | #C62828 (red) | Don't trust |
| `brave-disposable` | #F57C00 (orange) | Ephemeral |
| `discord` | #C62828 (red) | Don't trust |

### Disposable Runner

`disp-run` command for one-shot execution of any app:

```bash
#!/usr/bin/env bash
DISP_HOME=$(mktemp -d /tmp/disp-XXXX)
trap 'rm -rf "$DISP_HOME"' EXIT INT TERM
HOME="$DISP_HOME" exec sg untrusted -c "$*"
```

- Runs with untrusted GID (LAN blocked)
- tmpfs HOME (wiped on exit)
- Usable for opening suspicious files, links, etc.

## Implementation Files

| File | Change |
|------|--------|
| `modules/compartments.nix` | NEW: untrusted group, nftables table, firejail config |
| `home/stoleyy/browser.nix` | MODIFY: add `sg untrusted` to untrusted/disposable wrappers |
| `home/stoleyy/hyprland.nix` | MODIFY: add bordercolor windowrulev2 rules |
| `home/stoleyy/default.nix` | MODIFY: add discord-wrapped, keepassxc-wrapped, disp-run to packages |
| `lib/default.nix` | MODIFY: add compartments.nix to module list |

## Module: compartments.nix

```nix
{ config, pkgs, ... }:

{
  # Group for LAN-isolated apps
  users.groups.untrusted = {};
  users.users.stoleyy.extraGroups = [ "untrusted" ];

  # Firejail for offline isolation (KeePassXC)
  programs.firejail = {
    enable = true;
    wrappedBinaries.keepassxc = {
      executable = "${pkgs.keepassxc}/bin/keepassxc";
      extraArgs = [ "--net=none" "--noprofile" ];
    };
  };

  # nftables: block LAN for untrusted GID
  systemd.services.compartments-nftables = {
    description = "Compartment isolation nftables rules";
    after = [ "nftables.service" "network-online.target" ];
    wants = [ "network-online.target" ];
    wantedBy = [ "multi-user.target" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      ExecStart = pkgs.writeShellScript "compartments-nft-load" ''
        ${pkgs.nftables}/bin/nft -f - <<'EOF'
        table inet compartments {
          chain output {
            type filter hook output priority 50; policy accept;
            meta skgid "untrusted" ip daddr { 192.168.0.0/16, 10.0.0.0/8, 172.16.0.0/12 } counter drop
            meta skgid "untrusted" ip6 daddr { fd00::/8, fe80::/10 } counter drop
          }
        }
        EOF
      '';
      ExecStop = "${pkgs.nftables}/bin/nft delete table inet compartments";
    };
  };
}
```

## Browser.nix Changes

Untrusted/disposable wrappers gain `sg untrusted -c`:

```bash
# brave-untrusted / brave-disposable
exec sg untrusted -c "brave --user-data-dir=\"$DATA_DIR\" --class=brave-untrusted $*"
```

## Hyprland Changes

Add to windowrulev2 list:

```nix
# Qubes-style trust domain borders
"bordercolor rgb(2E7D32), class:^(brave-vault)$"
"bordercolor rgb(2E7D32), class:^(org.keepassxc.KeePassXC)$"
"bordercolor rgb(0A094E), class:^(brave-personal)$"
"bordercolor rgb(C62828), class:^(brave-untrusted)$"
"bordercolor rgb(C62828), class:^(discord)$"
"bordercolor rgb(F57C00), class:^(brave-disposable)$"
```

## What Stays Unchanged

- VPN tunnel configuration
- Kill switch table + service
- All keybinds (Super+B, Super+Space, etc.)
- Rofi app launcher (desktop entries point to wrappers)
- Steam, Spotify, terminal, file manager behavior
- qBittorrent's bindsTo VPN binding
- Service hardening (media-server, transcode)

## Verification

After implementation:
1. `nft list table inet compartments` — rules loaded
2. `sg untrusted -c "curl http://192.168.1.1"` — should timeout/drop
3. `sg untrusted -c "curl https://example.com"` — should work (via VPN)
4. `keepassxc` launches with no network (firejail)
5. `brave-untrusted` opens with red border, can reach internet, can't reach LAN
6. `disp-run firefox` runs with tmpfs home, wipes on exit
7. All existing apps behave identically
