{...}: {
  programs.starship = {
    enable = true;
    enableZshIntegration = true;

    settings = {
      add_newline = true;

      format = "$directory$git_branch$git_status$nix_shell$cmd_duration$line_break$character";

      directory = {
        style = "bold cyan";
        truncation_length = 4;
      };

      character = {
        success_symbol = "[❯](bold green)";
        error_symbol = "[❯](bold red)";
      };

      git_branch = {
        style = "bold magenta";
        symbol = " ";
      };

      git_status = {
        style = "bold yellow";
      };

      nix_shell = {
        symbol = " ";
        format = "via [$symbol$state]($style) ";
      };

      cmd_duration = {
        min_time = 2000;
        format = "took [$duration](bold yellow) ";
      };
    };
  };
}
