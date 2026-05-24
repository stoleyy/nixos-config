# Self-Repairing NixOS Infrastructure

## Goal

The system stays up to date and functional with minimal user input.
Updates build silently in the background and activate on next reboot.
Crashed services auto-restart. Bad generations auto-rollback at boot.

## Layer 1: Unattended Updates

### Auto-upgrade flow

1. `flake-lock-update.timer` (Sunday 03:00) — runs `nix flake update`,
   commits updated lock file directly to `main` in `/etc/nixos`.
2. `nixos-upgrade.timer` (Sunday 04:00) — runs `nixos-rebuild boot
   --flake /etc/nixos`. Builds the new generation and sets it as the
   next boot entry. Does NOT activate live (`operation = "boot"`).
3. On success, chains `nix-gc.service` via `runGarbageCollection = true`.
4. On failure, logs error to journal. Current generation is untouched.

### Deprecated flag fix

Remove `--update-input nixpkgs` and `--no-write-lock-file` from
`system.autoUpgrade.flags`. These are deprecated in Nix 2.19+ and will
break. The flake-lock-update service handles input bumping separately.

### Reboot notification

After `nixos-upgrade.service` succeeds, a oneshot service checks if the
new generation differs from the running one (kernel/initrd). If so,
sends a desktop notification: "System update ready — reboot to apply."

### Store maintenance

- `min-free = 500MB` / `max-free = 2GB` — reactive GC on disk pressure
  (prevents build failures from full disk)
- `nix.optimise.automatic = true` — weekly store deduplication
- `nh.clean` remains the primary scheduled GC (already configured)

## Layer 2: Boot Safety

### Boot counting

```
boot.loader.systemd-boot.bootCounting = {
  enable = true;
  trials = 2;
};
```

On each boot, systemd-boot decrements `tries-left` in the entry
filename. If it reaches 0 (two failed boots), the entry is marked "bad"
and systemd-boot skips to the previous generation automatically.

A boot is "successful" when `boot-complete.target` is reached (all
required system units started). `systemd-bless-boot.service` then marks
the entry as permanent.

### Configuration limit

Reduce `configurationLimit` from 20 to 10. With weekly upgrades, 10
generations = 10 weeks of rollback headroom.

## Layer 3: Service Supervision

### Services to convert from exec-once to systemd user units

| Service | Current | Target | Restart policy |
|---|---|---|---|
| waybar | `programs.waybar.systemd.enable` | Already done | on-failure |
| swaync | exec-once | systemd user service | on-failure |
| swayosd-server | exec-once | systemd user service | on-failure |
| wl-paste (text) | exec-once | systemd user service | on-failure |
| wl-paste (image) | exec-once | systemd user service | on-failure |
| wl-clip-persist | exec-once | systemd user service | on-failure |
| pyprland | exec-once | systemd user service | on-failure |
| hypridle | exec-once | `services.hypridle` HM module | on-failure |

### Services to keep in exec-once (one-shots)

- `linux-wallpaperengine` — background process, no stdin/stdout
- `nm-applet --indicator` — tray app, low crash risk
- `cliphist wipe` — one-shot initialization
- `udiskie --tray` — tray app, low crash risk
- `kdeconnect-indicator` — tray app
- `kwalletd6` — D-Bus activated, doesn't need supervision
- `hyprsunset` — daemon mode, auto-restarts internally
- `systemctl --user start hyprpolkitagent.service` — already systemd

### Pattern for each converted service

```nix
systemd.user.services.<name> = {
  Unit = {
    Description = "<description>";
    After = [ "graphical-session.target" ];
    PartOf = [ "graphical-session.target" ];
  };
  Service = {
    ExecStart = "<command>";
    Restart = "on-failure";
    RestartSec = "5s";
  };
  Install.WantedBy = [ "graphical-session.target" ];
};
```

## Files Changed

- `modules/update-routines.nix` — fix auto-upgrade, add reboot notification
- `modules/system.nix` — add min-free/max-free, nix.optimise
- `hosts/predator/default.nix` — enable bootCounting, reduce configurationLimit
- `home/stoleyy/hyprland.nix` — move services from exec-once to systemd, add user service definitions
