_:

{
  programs.git = {
    enable = true;
    settings = {
      user.name = "stoleyy";
      user.email = "snapscanned@proton.me";
      alias = {
        s = "status -sb";
        lg = "log --oneline --graph --decorate --all";
        last = "log -1 HEAD --stat";
      };
      init.defaultBranch = "main";
      pull.rebase = true;
      push.autoSetupRemote = true;
      rebase.autoStash = true;
      fetch.prune = true;
      merge.conflictStyle = "zdiff3";
      rerere.enabled = true;
      # delta — pretty diff/blame/log pager. Package shipped from modules/apps.nix.
      core.pager = "delta";
      interactive.diffFilter = "delta --color-only";
      delta.features = "side-by-side line-numbers";
    };
    ignores = [
      ".direnv"
      "result"
      "result-*"
    ];
  };
}
