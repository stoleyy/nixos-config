# Secure Boot signature verification at activation time.
#
# Runs after `nixos-rebuild switch` (and `boot`) to ensure the newly written
# boot chain is fully signed BEFORE the user reboots into it. Catches the
# class of failure where lanzaboote's `Successfully installed Lanzaboote`
# message is misleading — e.g. when UKIs reference kernels that nh-clean
# garbage-collected, or when sbctl is missing the kernel from its DB.
#
# Behavior:
#   - If sbctl is not installed (no Secure Boot in use), the hook is a no-op.
#   - If sbctl is installed but SB is currently Disabled, the hook still
#     runs `sbctl verify` so you catch unsigned binaries before turning SB on.
#   - If any file in the ESP shows `is not signed`, activation FAILS and
#     the rebuild aborts with a clear error.
#
# The check uses /run/current-system/sw/bin/sbctl so the module is safe to
# import even when sbctl isn't in systemPackages — the script just no-ops.
_:

{
  system.activationScripts.verifySecureBoot = {
    text = ''
      SBCTL=/run/current-system/sw/bin/sbctl
      if [ ! -x "$SBCTL" ]; then
        exit 0
      fi

      echo "Verifying Secure Boot signatures..."
      VERIFY_OUT=$("$SBCTL" verify 2>&1 || true)
      UNSIGNED=$(printf '%s\n' "$VERIFY_OUT" | grep "is not signed" || true)

      if [ -n "$UNSIGNED" ]; then
        echo ""
        echo "ERROR: Unsigned EFI binaries detected in /boot."
        echo "       Refusing to complete activation — the system would not boot"
        echo "       with Secure Boot enabled."
        echo ""
        printf '%s\n' "$UNSIGNED"
        echo ""
        echo "Recovery:"
        echo "  1. Add the file to sbctl's DB: sudo sbctl sign -s <path>"
        echo "  2. Re-run nixos-rebuild (or sudo sbctl sign-all)"
        echo "  3. Re-verify:                  sudo sbctl verify"
        exit 1
      fi

      echo "Secure Boot: all boot files signed."
    '';
    # Run after /etc and packages are in place so /run/current-system/sw
    # actually points at the new system closure.
    deps = [ "etc" ];
  };
}
