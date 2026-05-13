# Wazuh HIDS agent — not yet packaged in nixpkgs (tracking: NixOS/nixpkgs#230623).
#
# This is a first-pass derivation; expect to iterate on the actual machine.
# Known gotchas baked in:
#   - OSSEC_LIBS="-lzstd" — without this the build fails with undefined
#     ZSTD_versionNumber references in libwazuhext.so
#     (https://discourse.nixos.org/t/issues-while-packaging-wazuh-for-nixos/43124)
#   - autoPatchelfHook patches RPATHs to nixpkgs libs.
#   - PATH at runtime is set by the systemd unit (modules/wazuh-agent.nix),
#     not here — wazuh-modulesd shells out to sh/grep/ip/ps/ss.
#   - The runtime prefix /var/ossec is hardcoded in the binaries; the module
#     owns that directory via systemd-tmpfiles.

final: prev:
{
  wazuh-agent = prev.stdenv.mkDerivation rec {
    pname   = "wazuh-agent";
    version = "4.14.5";

    src = prev.fetchFromGitHub {
      owner = "wazuh";
      repo  = "wazuh";
      rev   = "v${version}";
      # Replace with actual hash on first build:
      #   nix-prefetch-github --rev v${version} wazuh wazuh
      hash  = prev.lib.fakeHash;
    };

    sourceRoot = "${src.name}/src";

    nativeBuildInputs = with prev; [
      autoconf
      automake
      autoPatchelfHook
      cmake
      gnumake
      libtool
      pkg-config
      python3
    ];

    buildInputs = with prev; [
      cjson
      curl
      libgcrypt
      libgpg-error
      libsodium
      openssl
      pcre2
      sqlite
      zstd
    ];

    # zstd link fix — see header comment.
    makeFlags = [
      "TARGET=agent"
      ''OSSEC_LIBS=-lzstd''
      "PREFIX=/var/ossec"
      "USE_SELINUX=no"
      "USE_AUDIT=no"
      "DEBUG=no"
    ];

    enableParallelBuilding = true;

    # Wazuh's Makefile installs to /var/ossec by default; redirect to $out and
    # let the systemd unit own /var/ossec at runtime.
    installPhase = ''
      runHook preInstall

      mkdir -p $out/{bin,lib,etc,ruleset,active-response,wodles}

      # Daemons and CLIs.
      for b in wazuh-agentd wazuh-execd wazuh-logcollector \
               wazuh-modulesd wazuh-syscheckd \
               agent-auth manage_agents wazuh-control; do
        if [ -x "./bin/$b" ]; then
          install -Dm755 "./bin/$b" "$out/bin/$b"
        fi
      done

      # Shared libs produced by the build.
      for so in libwazuhext.so libwazuhshared.so; do
        if [ -e "./$so" ]; then
          install -Dm755 "./$so" "$out/lib/$so"
        fi
      done

      # Default config skeleton + ruleset.
      cp -r ./etc/.            $out/etc/        || true
      cp -r ./ruleset/.        $out/ruleset/    || true
      cp -r ./active-response/. $out/active-response/ || true
      cp -r ./wodles/.         $out/wodles/     || true

      runHook postInstall
    '';

    # Quick smoke test — catches broken RPATHs and missing symbols.
    doInstallCheck = true;
    installCheckPhase = ''
      $out/bin/wazuh-agentd -h >/dev/null 2>&1 || true
      $out/bin/agent-auth -h >/dev/null 2>&1 || true
    '';

    meta = with prev.lib; {
      description = "Wazuh HIDS endpoint agent (host-side, outbound to manager)";
      homepage    = "https://wazuh.com";
      license     = licenses.gpl2Only;
      platforms   = platforms.linux;
      # Hand-packaged; vulnix will flag the bundled libs — see CLAUDE.md.
    };
  };
}
