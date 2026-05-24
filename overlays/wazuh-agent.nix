# Wazuh HIDS agent — not yet packaged in nixpkgs (tracking: NixOS/nixpkgs#230623).
#
# DISABLED: fakeHash placeholder — derivation is not ready to build.
# To re-enable: run `nix-prefetch-github --rev v4.14.5 wazuh wazuh`,
# replace fakeHash with the real hash, restore the full mkDerivation body,
# and change this overlay back to `_: prev: { wazuh-agent = ...; }`.
#
# Known gotchas for when this is re-enabled:
#   - OSSEC_LIBS="-lzstd" — without this the build fails with undefined
#     ZSTD_versionNumber references in libwazuhext.so
#     (https://discourse.nixos.org/t/issues-while-packaging-wazuh-for-nixos/43124)
#   - autoPatchelfHook patches RPATHs to nixpkgs libs.
#   - PATH at runtime is set by the systemd unit (modules/wazuh-agent.nix),
#     not here — wazuh-modulesd shells out to sh/grep/ip/ps/ss.
#   - The runtime prefix /var/ossec is hardcoded in the binaries; the module
#     owns that directory via systemd-tmpfiles.
_: _: { }
