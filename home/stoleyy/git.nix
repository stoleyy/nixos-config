{ ... }:

{
  programs.git = {
    enable  = true;
    ignores = [ ".direnv" "result" "result-*" ];
    settings = {
      user.name  = "stoleyy";
      user.email = "snapscanned@proton.me";
      init.defaultBranch   = "main";
      pull.rebase          = true;
      push.autoSetupRemote = true;
      rebase.autoStash     = true;
      fetch.prune          = true;
      merge.conflictStyle  = "zdiff3";
      rerere.enabled       = true;
      alias = {
        s    = "status -sb";
        lg   = "log --oneline --graph --decorate --all";
        last = "log -1 HEAD --stat";
      };
    };
  };
}
