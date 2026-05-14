# ProtonVPN via kernel WireGuard (wg-quick)

NixOS module: `modules/protonvpn.nix`.

## What this gives you over the ProtonVPN GUI

- **Boot-time activation.** Tunnel comes up before SDDM. No need to be logged in.
- **Kernel WireGuard.** Same speed as the GUI (which also uses kernel WG via
  NetworkManager), with one fewer userspace dependency.
- **True firewall-level kill switch.** Blocks all non-LAN, non-VPN outbound
  traffic regardless of tunnel state. Survives VPN crashes, daemon restarts,
  NetworkManager reconnects. The GUI's killswitch is process-based and has
  been observed to fail-open during certain reconnect scenarios.
- **Declarative config.** Tunnel parameters live in `modules/protonvpn.nix` and
  the host-config `hosts/predator/default.nix` — version-controlled, reviewable.

## One-time setup

### 1. Get a ProtonVPN WireGuard config

1. Log in at <https://account.proton.me>.
2. Go to **Downloads → WireGuard configurations**.
3. Pick a server (or rotate periodically — anything in the same metro area
   for low latency). Plus tier gives you "Plus" servers with higher bandwidth.
4. Set:
   - **Platform:** Linux (or any — the config is identical).
   - **VPN Accelerator:** on.
   - **NetShield:** off (you already have OISD blocking via Unbound on
     OPNsense — see [[opnsense-unbound-gotchas]]).
   - **Moderate NAT / Port forwarding:** as you prefer.
5. Click **Create** and **Download** the `.conf` file. Open it in a text editor.

The file looks like:

```
[Interface]
# Key for stoleyy_proton
# Bouncing = 5
# NetShield = 0
# Moderate NAT = off
# NAT-PMP = off
# VPN Accelerator = on
PrivateKey = <40-char base64 string>
Address = 10.2.0.2/32
DNS = 10.2.0.1

[Peer]
# US-NY#42
PublicKey = <44-char base64 string>
AllowedIPs = 0.0.0.0/0
Endpoint = 146.70.146.34:51820
```

You will use **PrivateKey**, **PublicKey**, **Endpoint**, and (rarely) **Address**.

### 2. Put the private key in a root-only file

```sh
sudo install -d -m 0700 -o root -g root /var/lib/protonvpn
echo '<PASTE-PRIVATE-KEY-HERE>' | sudo install -m 0400 -o root -g root /dev/stdin /var/lib/protonvpn/privkey
sudo cat /var/lib/protonvpn/privkey   # confirm only the key, no whitespace, no headers
```

> Replace `<PASTE-PRIVATE-KEY-HERE>` with the exact `PrivateKey` value, no quotes.

### 3. Enable the module in `hosts/predator/default.nix`

Add:

```nix
modules.protonvpn = {
  enable = true;
  serverPublicKey = "<PublicKey from [Peer] section>";
  serverEndpoint  = "<Endpoint from [Peer] section>";        # e.g. "146.70.146.34:51820"
  # clientAddress defaults to 10.2.0.2/32 — only change if your config differs
  # killSwitch defaults to true
};
```

Then push + pull + rebuild:

```sh
# in this repo
git add hosts/predator/default.nix
git commit -m "protonvpn: enable for predator with specific server"
git push

# on predator
cd /etc/nixos
sudo git pull origin main
sudo nixos-rebuild switch --flake .#predator
```

### 4. Verify

```sh
# tunnel up
sudo wg show
# expect: interface: protonvpn, listening port, peer with handshake timestamp

# kill switch active
sudo nft list table inet protonvpn_killswitch
# expect: chain output with allow rules + final `counter drop`

# external IP through VPN
curl -s https://ifconfig.me
# expect: a Proton server IP, NOT your home WAN (75.180.104.157)

# DNS still works via OPNsense
host cloudflare.com
# expect: 104.16.x.x

# LAN still reachable (kill switch allows 192.168.1.0/24)
ping -c2 192.168.1.114    # OPNsense
```

### 5. Disable the GUI client (optional)

Once you trust the kernel setup, prevent the GUI from racing for the default route:

- Either remove `protonvpn-gui` from `modules/apps.nix` (cleaner — closure shrinks).
- Or just don't launch it. The package can sit installed without doing anything.

## Operations

### Switching servers

When you want a different Proton server:

1. Download a new `.conf` from account.proton.me.
2. Update `serverPublicKey` and `serverEndpoint` in `hosts/predator/default.nix`.
3. If the new server issues a new PrivateKey (it usually does), replace
   `/var/lib/protonvpn/privkey`.
4. Commit, pull, rebuild. `wg-quick-protonvpn.service` restarts automatically.

### Temporarily disabling the VPN

```sh
sudo systemctl stop wg-quick-protonvpn.service
# kill switch is still active — your LAN works but you have no internet
sudo systemctl stop protonvpn-killswitch.service
# now you have direct internet via ISP (no kill switch, no VPN)
```

To put it back:
```sh
sudo systemctl start protonvpn-killswitch.service wg-quick-protonvpn.service
```

### Upgrading to sops-managed private key

Currently the private key lives plaintext at `/var/lib/protonvpn/privkey`
(root-only, 0400 — safe against userland processes but unencrypted at rest).
Once sops-nix is wired up (Tier 2.1 in the optimization roadmap):

1. Encrypt the key into `secrets/secrets.yaml`:
   ```sh
   nix-shell -p sops --run "sops secrets/secrets.yaml"
   # add line: protonvpn_wg_key: <key>
   ```
2. Declare it in `hosts/predator/default.nix`:
   ```nix
   sops.secrets.protonvpn_wg_key = {
     owner = "root";
     mode  = "0400";
     restartUnits = [ "wg-quick-protonvpn.service" ];
   };
   ```
3. Update `modules.protonvpn.privateKeyFile = config.sops.secrets.protonvpn_wg_key.path;`
4. Delete `/var/lib/protonvpn/privkey` (the sops-decrypted file replaces it).

## Troubleshooting

| Symptom | Likely cause | Fix |
|---|---|---|
| `wg show` returns nothing | Service failed to start | `journalctl -u wg-quick-protonvpn.service` — check for "key has wrong length" (private key file has whitespace/newline) |
| No internet at all, even LAN | Kill switch + tunnel never came up | Stop killswitch service temporarily; check journal; fix endpoint/pubkey; restart |
| Tunnel up but `ifconfig.me` shows home IP | `AllowedIPs = 0.0.0.0/0` not in peer config | Verify in `wg show protonvpn allowed-ips` |
| Handshake timestamp ages past 3 min | Server unreachable | Check server status at Proton's portal; switch to a different server |
| `nft: command not found` in journal | nftables not in PATH for the script | Module already uses `${pkgs.nftables}/bin/nft` — shouldn't happen unless module was hand-edited |

## Related

- `modules/protonvpn.nix` — the module
- [[wireguard-home]] memory — the OPNsense-side WG server (separate tunnel, not used in this setup)
- Tier 2.1 in `/home/stoleyy/.claude/plans/cozy-singing-kurzweil.md` — sops-nix upgrade path
