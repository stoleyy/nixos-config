{ pkgs, ... }:

{
  programs.git = {
    enable = true;
    settings = {
      user = {
        name = "stoleyy";
        email = "snapscanned@proton.me";
        # GPG-sign commits and tags. The key is selected by committer email,
        # so gpg resolves the matching secret key (the one gpg.nix's agent
        # unlocks via pinentry-qt). If you keep multiple keys for this address,
        # pin the long id instead: `gpg --list-secret-keys --keyid-format=long`.
        signingKey = "snapscanned@proton.me";
      };
      gpg.program = "${pkgs.gnupg}/bin/gpg";
      commit.gpgsign = true;
      alias = {
        s = "status -sb";
        lg = "log --oneline --graph --decorate --all";
        last = "log -1 HEAD --stat";
        co = "checkout";
        br = "branch";
        ci = "commit";
        amend = "commit --amend --no-edit";
        reword = "commit --amend";
        unstage = "reset HEAD --";
        undo = "reset --soft HEAD~1";
        wip = "!git add -A && git commit -m wip";
        aliases = "!git config --get-regexp '^alias\\.' | sed 's/alias\\.//'";
      };
      init.defaultBranch = "main";
      pull.rebase = true;
      push = {
        autoSetupRemote = true;
        followTags = true;
      };
      rebase.autoStash = true;
      fetch.prune = true;
      merge.conflictStyle = "zdiff3";
      diff = {
        colorMoved = "default";
        algorithm = "histogram";
      };
      column.ui = "auto";
      branch.sort = "-committerdate";
      tag = {
        gpgsign = true;
        sort = "version:refname";
      };
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
