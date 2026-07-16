{pkgs, ...}: {
  programs.tmux = {
    enable = true;
    baseIndex = 1;
    keyMode = "vi";
    mouse = true;
    escapeTime = 0;
    historyLimit = 2000;

    plugins = with pkgs.tmuxPlugins; [
      {
        plugin = tokyo-night-tmux;
        extraConfig = ''
          set -g @tokyo-night-tmux_theme night
          set -g @tokyo-night-tmux_show_hostname 1
          set -g @tokyo-night-tmux_show_path 1
        '';
      }
      resurrect
      {
        plugin = continuum;
        extraConfig = ''
          set -g @continuum-restore 'on'
          set -g @continuum-save-interval '15'
        '';
      }
    ];

    extraConfig = ''
      # Neovim auto-negotiates the Kitty keyboard protocol with foot; without
      # this, tmux doesn't reliably translate that back into its own key
      # names, so root-table Alt binds (M-c etc.) stop matching once nvim has
      # touched the pane and the raw sequence falls through to the shell/nvim.
      set -g extended-keys always

      # mouse=true + keyMode vi means any scroll over a pane silently drops
      # you into copy-mode-vi, which rebinds the whole keytable (Ctrl+C,
      # M-c, etc. stop meaning what you expect) until you press q/Escape.
      # Flash a message on entry/exit so it's never a silent surprise.
      set-hook -g pane-mode-changed 'if -F "#{pane_in_mode}" "display-message \"-- COPY MODE (q/Escape to exit) --\"" "display-message \"-- copy mode exited --\""'

      unbind-key -a -T root

      # unbind-key -a -T root above wipes tmux's built-in mouse bindings too
      # (root table only -- copy-mode-vi's own MouseDrag1Pane/MouseDragEnd1Pane
      # selection binds are untouched). Re-add just the entry points so
      # click-drag still starts a selection.
      bind -n MouseDown1Pane select-pane -t = \; send-keys -M
      bind -n MouseDrag1Pane select-pane -t = \; copy-mode -M
      bind -n MouseDrag1Border resize-pane -M

      set -g pane-border-lines "double"

      set -g renumber-windows on

      bind -n M-r source-file ~/.config/tmux/tmux.conf \; display "Config reloaded!"
      bind -n M-s choose-tree -s

      bind -n M-1 select-window -t 1
      bind -n M-2 select-window -t 2
      bind -n M-3 select-window -t 3
      bind -n M-4 select-window -t 4
      bind -n M-5 select-window -t 5
      bind -n M-6 select-window -t 6
      bind -n M-7 select-window -t 7
      bind -n M-8 select-window -t 8
      bind -n M-9 select-window -t 9

      bind -n M-Left select-pane -L
      bind -n M-Right select-pane -R
      bind -n M-Up select-pane -U
      bind -n M-Down select-pane -D

      bind -n M-S-Left resize-pane -L 5
      bind -n M-S-Right resize-pane -R 5
      bind -n M-S-Up resize-pane -U 3
      bind -n M-S-Down resize-pane -D 3

      bind -n M-h split-window -v
      bind -n M-v split-window -h

      bind -n M-Enter new-window
      bind -n M-c kill-pane
      bind -n M-q kill-window
      bind -n M-d detach
      bind -n M-Q confirm-before -p "Kill entire session? (y/n)" kill-session

      bind -T copy-mode-vi v send -X begin-selection
      bind -T copy-mode-vi y send -X copy-pipe-and-cancel "wl-copy || xclip -in -selection clipboard"
      bind -n M-/ copy-mode \; command-prompt -p "(search down)" "send -X search-forward '%%%'"
      bind -n M-? copy-mode \; command-prompt -p "(search up)"   "send -X search-backward '%%%'"
    '';
  };
}
