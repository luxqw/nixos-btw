{...}: {
  programs.starship = {
    enable = true;
    enableZshIntegration = true;

    settings = {
      add_newline = true;

      format = "$username$hostname$directory$nix_shell$cmd_duration$line_break$character";

      username = {
        style_user = "bold green";
        show_always = false;
        format = "[$user]($style)";
      };

      hostname = {
        ssh_only = true;
        style = "bold green";
        format = "[@$hostname]($style) ";
      };

      directory = {
        style = "bold cyan";
        truncation_length = 4;
      };

      character = {
        success_symbol = "[❯](bold green)";
        error_symbol = "[❯](bold red)";
        vicmd_symbol = "[❮](bold green)";
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
