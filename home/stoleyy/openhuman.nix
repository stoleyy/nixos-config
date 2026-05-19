_:

{
  # openhuman is a prebuilt CEF (Chromium-embedded) app launched from PATH
  # (not packaged in this flake). `command openhuman` skips this function to
  # exec the real on-PATH binary wherever it lives — no recursion, no
  # hard-coded store path. ANGLE→Vulkan is this box's known-good NVIDIA
  # (RTX 4070, open module) backend, copied from the Brave wrapper in
  # modules/apps.nix; it clears the EGL_BAD_MATCH / DRM_IOCTL_MODE_CREATE_DUMB
  # flood the CEF GPU process hits with the default GL backend.
  programs.fish.functions.openhuman = {
    description = "openhuman with NVIDIA-safe ANGLE/Vulkan GL backend";
    body = ''
      command openhuman \
        --ozone-platform-hint=auto \
        --use-gl=angle \
        --use-angle=vulkan \
        $argv
    '';
  };
}
