{...}: {
  programs.git = {
    enable = true;
    settings = {
      user.name = "lux";
      user.email = "rakhmatullin.damir@tutamail.com";
      init.defaultBranch = "main";
      pull.rebase = true;
    };
  };
}
