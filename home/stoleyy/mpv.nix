_:

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
{
  programs.mpv = {
    enable = true;
    config = {
      vo                     = "gpu-next";
      gpu-context            = "wayland";
      hwdec                  = "nvdec-copy";
      profile                = "high-quality";
      target-colorspace-hint = "yes";
      hdr-compute-peak       = "yes";
      tone-mapping           = "bt.2446a";
      inverse-tone-mapping   = "yes";
      interpolation          = "yes";
      video-sync             = "display-resample";
      deband                 = "yes";
    };
  };
}
