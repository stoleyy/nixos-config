# Fix gamescope crash-loop on startup when input events arrive during
# wlserver_init(). The Logitech USB receiver sends mouse motion events
# before the wlserver lock is initialised → assertion failure (SIGABRT)
# in wlserver_mousemotion(). Upstream fix: PR #2023, merged after 3.16.17.
# https://github.com/ValveSoftware/gamescope/issues/1746
_: prev: {
  gamescope = prev.gamescope.overrideAttrs (old: {
    patches = (old.patches or [ ]) ++ [
      (prev.fetchurl {
        url = "https://github.com/ValveSoftware/gamescope/commit/c366f47bf8102c205364d4ecadf091a378defe2d.patch";
        hash = "sha256-p9wt7oWULIsJ36HSENsQxvLvGc3/p8W+y0/pFKiOCbk=";
      })
    ];
  });
}
