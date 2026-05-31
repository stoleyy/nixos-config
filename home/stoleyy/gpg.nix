{ pkgs, ... }:

{
  programs.gpg = {
    enable = true;
    # Hardening: stronger digest/cipher preferences and quieter output.
    # SHA-512 certs, AES-256 first, drop the version banner, long key ids.
    settings = {
      personal-cipher-preferences = "AES256 AES192 AES";
      personal-digest-preferences = "SHA512 SHA384 SHA256";
      personal-compress-preferences = "ZLIB BZIP2 ZIP Uncompressed";
      default-preference-list = "SHA512 SHA384 SHA256 AES256 AES192 AES ZLIB BZIP2 ZIP Uncompressed";
      cert-digest-algo = "SHA512";
      s2k-digest-algo = "SHA512";
      s2k-cipher-algo = "AES256";
      keyid-format = "0xlong";
      with-fingerprint = true;
      no-emit-version = true;
      no-comments = true;
      no-symkey-cache = true;
      require-cross-certification = true;
    };
  };

  services.gpg-agent = {
    enable = true;
    pinentry.package = pkgs.pinentry-qt;
    enableFishIntegration = true;
    enableSshSupport = true;
    # Cache an unlocked key for 30 min, evict after 2 h (mirror for SSH keys).
    defaultCacheTtl = 1800;
    maxCacheTtl = 7200;
    defaultCacheTtlSsh = 1800;
    maxCacheTtlSsh = 7200;
  };
}
