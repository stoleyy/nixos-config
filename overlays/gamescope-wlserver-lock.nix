# Fix gamescope crash-loop on startup when input events arrive during
# wlserver_init(). Two distinct races fixed:
#
# 1. Mouse path (PR #2023, merged after 3.16.17): Logitech USB receiver
#    sends mouse motion events before the wlserver lock is initialised
#    → assertion failure in wlserver_mousemotion().
#    https://github.com/ValveSoftware/gamescope/issues/1746
#
# 2. Keyboard path (no upstream fix yet): USB HID keyboard events arrive
#    before any window surface exists → wlserver_keyboardfocus() passes
#    NULL to wlr_seat_keyboard_notify_enter() which asserts surface != NULL.
#    Fix: NULL guard that calls wlr_seat_keyboard_clear_focus() instead.
final: prev: {
  gamescope = prev.gamescope.overrideAttrs (old: {
    patches = (old.patches or [ ]) ++ [
      # Mouse input race (upstream PR #2023)
      (prev.fetchurl {
        url = "https://github.com/ValveSoftware/gamescope/commit/c366f47bf8102c205364d4ecadf091a378defe2d.patch";
        hash = "sha256-p9wt7oWULIsJ36HSENsQxvLvGc3/p8W+y0/pFKiOCbk=";
      })
      # Keyboard NULL surface race (local patch)
      ../patches/gamescope-keyboard-null-surface.patch
    ];
  });
}
