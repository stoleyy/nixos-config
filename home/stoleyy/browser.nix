_:

{
  programs.firefox = {
    enable = true;
    profiles.default = {
      id = 0;
      isDefault = true;
      settings = {
        "browser.startup.homepage" = "about:blank";
        "privacy.donottrackheader.enabled" = true;
        "dom.security.https_only_mode" = true;
        "network.trr.mode" = 3;
        "network.trr.uri" = "https://dns.quad9.net/dns-query";
        "privacy.resistFingerprinting" = true; # F05: anti-fingerprinting
      };
    };
  };
}
