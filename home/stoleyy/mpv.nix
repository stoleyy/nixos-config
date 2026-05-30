{ pkgs, theme, ... }:

# mpv tuned for the Samsung G80SD OLED + RTX 4070:
# - gpu-next renderer with PQ/HLG decode and HDR metadata forwarding to KWin
#   (KWin 6.3+ honors the colorspace hint and switches the output into HDR
#   mode when the user has HDR enabled in System Settings → Display).
# - NVDEC hardware decode (matches the system-wide nvidia-vaapi-driver in
#   modules/nvidia.nix; copy variant keeps frames addressable for shaders).
# - interpolation + display-resample → smooths 24 / 30 / 60 fps content
#   onto the panel's 240 Hz refresh.
# - deband on by default — OLED reveals 8-bit gradient banding aggressively.
# - inverse-tone-mapping boosts SDR sources into the HDR signal envelope
#   when the output is in HDR mode — the closest Plasma has to Windows
#   "Auto HDR" for video. No-op when watching native HDR / when KWin is
#   in SDR mode.
let
  videoTypes = [
    "video/mp4"
    "video/x-matroska"
    "video/webm"
    "video/avi"
    "video/x-msvideo"
    "video/x-flv"
    "video/quicktime"
    "video/mpeg"
    "video/ogg"
    "video/3gpp"
    "video/3gpp2"
    "video/x-m4v"
    "video/mp2t"
  ];
  mpvAssoc = builtins.listToAttrs (
    map (t: {
      name = t;
      value = "mpv.desktop";
    }) videoTypes
  );
in
{
  programs.mpv = {
    enable = true;
    # uosc — modern, themeable OSC + menu; thumbfast feeds it seek previews.
    # uosc requires the stock OSC disabled (osc=no, set below).
    scripts = with pkgs.mpvScripts; [
      uosc
      thumbfast
    ];
    config = {
      vo = "gpu-next";
      gpu-context = "wayland";
      # NVDEC on the 4070. mpv falls through this list left-to-right, so a
      # non-NVIDIA host (or a stream NVDEC can't decode) lands on software.
      hwdec = "nvdec-copy,no";
      profile = "high-quality";
      target-colorspace-hint = "yes";
      hdr-compute-peak = "yes";
      tone-mapping = "bt.2446a";
      inverse-tone-mapping = "yes";
      interpolation = "yes";
      video-sync = "display-resample";
      deband = "yes";

      # uosc owns the on-screen UI.
      osc = "no";
      border = "no";

      # Subtitles — Inter from lib/theme.nix, white with the default outline.
      sub-font = theme.font.general;
      sub-font-size = 46;
      sub-color = "#FFFFFFFF";
      sub-back-color = "#00000000";
      sub-auto = "fuzzy";
      sub-pos = 95;
      slang = "eng,en";
      alang = "eng,en,jpn,ja";

      # Resume where you left off, keep the window open at EOF.
      save-position-on-quit = "yes";
      keep-open = "yes";

      # PNG screenshots into a tidy folder.
      screenshot-format = "png";
      screenshot-directory = "~/Pictures/Screenshots";
      screenshot-template = "%F-%P";

      # Generous demuxer cache for network/large files.
      cache = "yes";
      demuxer-max-bytes = "150MiB";
      demuxer-max-back-bytes = "75MiB";

      volume = 100;
      volume-max = 130;
    };
  };

  xdg.mimeApps = {
    enable = true;
    defaultApplications = mpvAssoc;
  };

  xdg.desktopEntries.mpv = {
    name = "mpv Media Player";
    genericName = "Multimedia Player";
    exec = "mpv -- %U";
    icon = "mpv";
    terminal = false;
    type = "Application";
    categories = [
      "AudioVideo"
      "Audio"
      "Video"
      "Player"
    ];
    mimeType = videoTypes;
  };
}
