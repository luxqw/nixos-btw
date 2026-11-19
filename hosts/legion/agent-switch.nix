# Agent-run switch of legion (migration step 4.5, owner decision R4).
#
# An agent starts one root unit: `systemctl start --no-ask-password nixos-agent-switch.service`.
# The unit builds committed `main` of /etc/nixos, asks for the YubiKey touch itself (the touch is
# the owner's approval), switches, runs probes and rolls back when one fails. Result of the last
# run: /var/lib/nixos-agent-switch/last.json (history: history.jsonl).
#
# It builds committed `main` only. When the live /etc/nixos tree has uncommitted changes to files
# legion can import, the run is refused (the build would silently drop them). Paths that cannot
# affect legion are listed in agentSwitch.ignoredDirtyPaths.
{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.agentSwitch;
  stateDir = "/var/lib/nixos-agent-switch";
  fnName = name: "probe_" + lib.replaceStrings ["-"] ["_"] name;

  probeDefs = lib.concatStringsSep "\n" (lib.mapAttrsToList (name: p: ''
      ${fnName name}() {
      ${p.script}
      }
    '')
    cfg.probes);
  probeCalls = lib.concatStringsSep "\n" (lib.mapAttrsToList (name: _: "run_probe ${lib.escapeShellArg name} ${fnName name}") cfg.probes);
  ignoredPrefixes = lib.concatMapStringsSep " " lib.escapeShellArg cfg.ignoredDirtyPaths;
  gitSafeDirs = lib.concatMapStrings (d: "  directory = ${d}\n") ([cfg.repo] ++ cfg.extraSafeDirectories);

  switchScript = pkgs.writeShellApplication {
    name = "nixos-agent-switch";
    runtimeInputs = with pkgs; [
      coreutils
      diffutils
      findutils
      gawk
      git
      gnugrep
      iproute2
      jq
      libnotify
      nix
      nvd
      pamtester
      systemd
      util-linux
    ];
    text = ''
      repo=''${AGENT_SWITCH_REPO:-${cfg.repo}}
      state=''${AGENT_SWITCH_STATE:-${stateDir}}
      attr=''${AGENT_SWITCH_ATTR:-nixosConfigurations.${cfg.hostName}.config.system.build.toplevel}
      # Test hooks (never set by the unit): 1 = stop before the touch, probes = only run the probes.
      dry=''${AGENT_SWITCH_DRY_RUN:-0}
      profile=''${AGENT_SWITCH_PROFILE:-/nix/var/nix/profiles/system}
      owner=${cfg.user}
      touch_timeout=${toString cfg.touchTimeoutSec}
      build_timeout=${toString cfg.buildTimeoutSec}
      settle=${toString cfg.settleSec}

      log() { echo "nixos-agent-switch: $*"; }

      mkdir -p "$state"
      exec 9>"$state/lock"
      if ! flock -n 9; then
        log "another run holds the lock, nothing done"
        exit 1
      fi

      snap=$(mktemp -d)
      trap 'rm -rf "$snap"' EXIT
      started=$(date -Is)
      rev="" prev_sys="" new_sys="" outcome="" reason="" probes_json="[]"

      # Write last.json (readable by the owner) and append one line to history.jsonl.
      finish() {
        outcome=$1 reason=$2
        jq -n --arg rev "$rev" --arg start "$started" --arg end "$(date -Is)" \
          --arg outcome "$outcome" --arg reason "$reason" \
          --arg from "$prev_sys" --arg to "$new_sys" --argjson probes "$probes_json" \
          '{rev: $rev, started: $start, ended: $end, outcome: $outcome, reason: $reason, from: $from, to: $to, probes: $probes}' \
          > "$state/last.json.new"
        chmod 0644 "$state/last.json.new"
        mv "$state/last.json.new" "$state/last.json"
        jq -c . "$state/last.json" >> "$state/history.jsonl"
        tail -n 50 "$state/history.jsonl" > "$state/history.jsonl.new"
        chmod 0644 "$state/history.jsonl.new"
        mv "$state/history.jsonl.new" "$state/history.jsonl"
        log "result: $outcome ($reason)"
      }

      # Anything unexpected still leaves a result file.
      on_error() {
        if [ -z "$outcome" ]; then
          finish error "unexpected failure at line $1, see the journal"
        fi
      }
      trap 'on_error $LINENO' ERR

      # Root reads repositories owned by the owner: allow exactly those, in a private gitconfig.
      export HOME="$snap"
      printf '[safe]\n%s' ${lib.escapeShellArg gitSafeDirs} > "$HOME/.gitconfig"

      # ---- 1. revision and dirty-tree check -------------------------------------------------
      rev=$(git -C "$repo" rev-parse --verify main)
      head_rev=$(git -C "$repo" rev-parse --verify HEAD)
      log "rev $rev (main of $repo)"
      if [ "$head_rev" != "$rev" ]; then
        log "REFUSED: the working tree is on $head_rev, not on main; switching main would drop it"
        finish refused "working tree HEAD is not main"
        exit 1
      fi

      ignored_prefixes=(${ignoredPrefixes})
      dirty=""
      # Paths that legion can import: everything tracked outside ignored_prefixes. Untracked
      # files are invisible to the flake, so they cannot change what legion builds.
      is_ignored() {
        local p=$1 pre
        for pre in "''${ignored_prefixes[@]}"; do
          case $p in "$pre"*) return 0 ;; esac
        done
        return 1
      }
      while IFS= read -r -d "" entry; do
        status=''${entry:0:2}
        path=''${entry:3}
        case $status in
          *R* | *C*) IFS= read -r -d "" orig || true; is_ignored "$orig" || dirty="$dirty $orig" ;;
        esac
        is_ignored "$path" || dirty="$dirty $path"
      done < <(git -C "$repo" status --porcelain -z --untracked-files=no)
      if [ -n "$dirty" ]; then
        log "REFUSED: uncommitted changes to files legion can import (commit or stash them first):"
        for p in $dirty; do log "  $p"; done
        finish refused "uncommitted changes:$dirty"
        exit 1
      fi

      # ---- 2. build ------------------------------------------------------------------------
      prev_sys=$(readlink -f /run/current-system)
      ref="git+file://$repo?rev=$rev#$attr"
      log "building $ref"
      if ! new_sys=$(timeout "$build_timeout" nix build --no-link --print-out-paths \
            --extra-experimental-features 'nix-command flakes' ${lib.escapeShellArgs cfg.extraNixArgs} "$ref"); then
        new_sys=""
        finish build-failed "nix build failed or timed out after $build_timeout s"
        exit 1
      fi
      log "built $new_sys"

      if [ "$new_sys" = "$prev_sys" ]; then
        log "the running system already is this build, nothing to switch"
        finish unchanged "running system equals the build of $rev"
        exit 0
      fi

      log "closure diff against $prev_sys:"
      nvd --color never diff "$prev_sys" "$new_sys" || true
      summary=$(nvd --color never diff "$prev_sys" "$new_sys" | tail -n 1 || true)

      # ---- 3. snapshot of the live state, used by the probes ---------------------------------
      graphical_sessions() {
        local id user
        loginctl list-sessions --no-legend | while read -r id _ user _; do
          [ "$user" = "$owner" ] || continue
          case $(loginctl show-session "$id" -p Type --value) in
            wayland | x11 | mir) echo "$id" ;;
          esac
        done
      }
      failed_units() { systemctl list-units --state=failed --plain --no-legend --no-pager | awk 'NF {print $1}' | sort -u; }
      default_route() { { ip -4 route show default; ip -6 route show default; } | grep -c . || true; }

      failed_units > "$snap/failed-before"
      { systemctl is-system-running || true; } > "$snap/state-before"
      default_route > "$snap/route-before"
      graphical_sessions > "$snap/sessions-before"

      # Probes: each function returns 0 (pass) or non-zero with a reason on stdout. They see the
      # snapshot files above ($snap/failed-before, state-before, route-before, sessions-before).
      ${probeDefs}
      run_probe() {
        local name=$1 fn=$2 out rc=0
        out=$("$fn" 2>&1) || rc=$?
        out=$(printf '%s' "$out" | tail -c 400)
        if [ "$rc" = 0 ]; then
          log "probe $name: ok''${out:+ ($out)}"
        else
          log "probe $name: FAILED ''${out:+($out)}"
          probes_failed=1
        fi
        probes_json=$(jq -c --arg n "$name" --argjson ok "$([ "$rc" = 0 ] && echo true || echo false)" --arg d "$out" \
          '. + [{name: $n, ok: $ok, detail: $d}]' <<< "$probes_json")
      }
      probes_failed=0
      run_all_probes() {
        probes_json="[]"
        probes_failed=0
        ${probeCalls}
      }

      if [ "$dry" = probes ]; then
        run_all_probes
        log "dry run (probes only): failed=$probes_failed"
        finish dry-run "probes only"
        exit "$probes_failed"
      fi

      # ---- 4. the touch ---------------------------------------------------------------------
      log "TOUCH REQUIRED: touch the YubiKey within $touch_timeout s to switch legion to ''${rev:0:12} ($summary)"
      if [ "$dry" = 1 ]; then
        log "dry run: stopping before the touch"
        finish dry-run "stopped before the touch"
        exit 0
      fi
      owner_uid=$(id -u "$owner")
      msg="Touch the YubiKey within $touch_timeout s to switch legion to ''${rev:0:12}. $summary"
      timeout 10 systemd-run --machine="$owner@.host" --user --collect --quiet \
          notify-send -u critical -t $((touch_timeout * 1000)) -a nixos-agent-switch "legion switch waiting for you" "$msg" \
        || timeout 10 setpriv --reuid "$owner_uid" --regid "$(id -g "$owner")" --init-groups \
          env "DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/$owner_uid/bus" \
          notify-send -u critical -t $((touch_timeout * 1000)) -a nixos-agent-switch "legion switch waiting for you" "$msg" \
        || log "no desktop notification (the touch prompt is only in the journal)"

      if ! timeout "$touch_timeout" pamtester nixos-agent-switch "$owner" authenticate; then
        finish no-touch "no YubiKey touch within $touch_timeout s (or authentication failed)"
        exit 1
      fi
      log "touch accepted"

      # ---- 5. switch, probes, rollback --------------------------------------------------------
      prev_gen=$(readlink "$profile" || true)
      roll_back() {
        log "rolling back to $prev_sys"
        local gen=''${prev_gen//[!0-9]/}
        if [ "$(readlink -f "$profile")" = "$prev_sys" ]; then
          :
        elif [ -n "$gen" ] && [ "$(readlink -f "$(dirname "$profile")/$prev_gen")" = "$prev_sys" ]; then
          nix-env -p "$profile" --switch-generation "$gen" || nix-env -p "$profile" --set "$prev_sys" || return 1
        else
          nix-env -p "$profile" --set "$prev_sys" || return 1
        fi
        "$prev_sys/bin/switch-to-configuration" switch || return 1
      }

      nix-env -p "$profile" --set "$new_sys"
      switch_rc=0
      "$new_sys/bin/switch-to-configuration" switch || switch_rc=$?
      log "switch-to-configuration exited $switch_rc; waiting $settle s before probes"
      sleep "$settle"
      run_all_probes

      if [ "$switch_rc" != 0 ] || [ "$probes_failed" != 0 ]; then
        if roll_back; then
          finish rolled-back "switch exit $switch_rc, probes failed=$probes_failed; back on $prev_sys"
        else
          finish rollback-failed "switch exit $switch_rc, probes failed=$probes_failed; the rollback itself failed, owner must act"
        fi
        exit 1
      fi
      finish switched "switched to $new_sys"
    '';
  };

  probeType = lib.types.submodule {
    options.script = lib.mkOption {
      type = lib.types.lines;
      description = ''
        Body of a bash function: return 0 to pass, non-zero (print the reason) to fail.
        Always write `|| return 1` explicitly: errexit is off inside the function. Available:
        `$snap/failed-before`, `$snap/state-before`, `$snap/route-before`,
        `$snap/sessions-before` (state taken before the switch) and `$owner`.
      '';
    };
  };
in {
  options.agentSwitch = {
    repo = lib.mkOption {
      type = lib.types.str;
      default = "/etc/nixos";
      description = "Git repository whose committed `main` is built and switched.";
    };
    extraSafeDirectories = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = ["/home/lux/Documents/projects/dispatcher"];
      description = "Other repositories (flake inputs fetched with git+file) that root must be allowed to read.";
    };
    hostName = lib.mkOption {
      type = lib.types.str;
      default = "legion";
      description = "nixosConfigurations attribute to build.";
    };
    user = lib.mkOption {
      type = lib.types.str;
      default = "lux";
      description = "The owner: touches the YubiKey, may start the unit, gets the notification.";
    };
    ignoredDirtyPaths = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = ["hosts/homelab/" "secrets/homelab/"];
      description = ''
        Path prefixes (relative to the repo root) that cannot affect legion. An uncommitted change
        to any other tracked path (`git status --porcelain`, untracked files excluded: the flake
        cannot see them) makes the run refuse, because building committed main would drop it.
      '';
    };
    touchTimeoutSec = lib.mkOption {
      type = lib.types.ints.positive;
      default = 60;
    };
    buildTimeoutSec = lib.mkOption {
      type = lib.types.ints.positive;
      default = 3600;
      description = "Limit for the build; the switch never starts close to the unit's total timeout.";
    };
    settleSec = lib.mkOption {
      type = lib.types.ints.unsigned;
      default = 20;
      description = "Wait after the switch before the probes (units still starting).";
    };
    extraNixArgs = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = ["--builders" ""];
      description = "Extra `nix build` arguments. Default: no remote builder (root has no SSH key for it).";
    };
    probes = lib.mkOption {
      type = lib.types.attrsOf probeType;
      description = "Checks after the switch; any failure rolls back.";
    };
    package = lib.mkOption {
      type = lib.types.package;
      default = switchScript;
      readOnly = true;
      internal = true;
      description = "The switch script (exposed so it can be built and run on its own).";
    };
  };

  config = {
    agentSwitch.probes = {
      no-new-failed-units.script = ''
        local new
        new=$(failed_units | grep -vxFf "$snap/failed-before" || true)
        [ -z "$new" ] || { echo "new failed units: $(echo "$new" | tr '\n' ' ')"; return 1; }
      '';
      system-state-not-worse.script = ''
        local now before
        rank() { case $1 in running) echo 0 ;; degraded) echo 1 ;; *) echo 2 ;; esac; }
        now=$(systemctl is-system-running || true)
        before=$(cat "$snap/state-before")
        [ "$(rank "$now")" -le "$(rank "$before")" ] || { echo "was $before, now $now"; return 1; }
        echo "$before -> $now"
      '';
      network-online.script = ''
        local tries=0
        [ "$(cat "$snap/route-before")" != 0 ] || { echo "no default route before the switch, nothing to protect"; return 0; }
        while [ "$tries" -lt 20 ]; do
          [ "$(default_route)" != 0 ] && return 0
          sleep 1
          tries=$((tries + 1))
        done
        echo "the default route is gone"
        return 1
      '';
      graphical-session.script = ''
        local id state
        while read -r id; do
          [ -n "$id" ] || continue
          state=$(loginctl show-session "$id" -p State --value 2>/dev/null) || { echo "session $id is gone"; return 1; }
          case $state in active | online) ;; *) echo "session $id is $state"; return 1 ;; esac
        done < "$snap/sessions-before"
      '';
    };

    environment.systemPackages = [pkgs.pamtester];

    # Own PAM stack: the YubiKey touch is the only way in (no password fallback). With unixAuth
    # off the auth stack is pam_u2f (sufficient) then pam_deny: success only through the key.
    # (u2f as `required` would be followed by pam_deny and always fail.)
    security.pam.services.nixos-agent-switch = {
      unixAuth = false;
      u2f.enable = true;
    };

    systemd.services.nixos-agent-switch = {
      description = "Build committed main of /etc/nixos, switch legion after a YubiKey touch, roll back on a failed probe";
      # Start only. A switch must never restart or stop its own unit.
      restartIfChanged = false;
      stopIfChanged = false;
      serviceConfig = {
        Type = "oneshot";
        User = "root";
        ExecStart = lib.getExe cfg.package;
        # Build (buildTimeoutSec) + touch + switch + probes, with room to spare.
        TimeoutStartSec = "2h";
        StateDirectory = "nixos-agent-switch";
        StateDirectoryMode = "0755";
        UMask = "0022";
        Nice = 10;
      };
    };

    # lux may start this one unit, no password; stop/restart/enable stay denied. The touch in the
    # unit is the approval.
    security.polkit.extraConfig = lib.mkAfter ''
      polkit.addRule(function(action, subject) {
        if (action.id == "org.freedesktop.systemd1.manage-units" &&
            action.lookup("unit") == "nixos-agent-switch.service" &&
            action.lookup("verb") == "start" &&
            subject.user == "${cfg.user}") {
          return polkit.Result.YES;
        }
      });
    '';
  };
}
