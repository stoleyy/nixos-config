{ ... }:

{
  programs.git = {
    enable    = true;
    userName  = "stoleyy";
    userEmail = "snapscanned@proton.me";
    aliases = {
      s    = "status -sb";
      lg   = "log --oneline --graph --decorate --all";
      last = "log -1 HEAD --stat";
    };
    extraConfig = {
      init.defaultBranch   = "main";
      pull.rebase          = true;
      push.autoSetupRemote = true;
      rebase.autoStash     = true;
      fetch.prune          = true;
      merge.conflictStyle  = "zdiff3";
      rerere.enabled       = true;
    };
    ignores = [ ".direnv" "result" "result-*" ];
  };
}
