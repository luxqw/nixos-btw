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
#
# Trust model (the agent shell is lux, and lux can write /etc/nixos and its .git):
#  - root never runs git, never evaluates Nix code and never fetches anything on or from the repo:
#    the revision, the dirty check and the whole flake evaluation run as lux (setpriv, minimal
#    environment, no capabilities). A lux-planted core.fsmonitor or filter, or a committed .nix
#    file calling builtins.fetchTree/fetchGit, therefore runs as lux, which is no escalation: lux
#    cannot read a root-only path, so none can be copied into the world-readable store;
#  - the evaluation prints the toplevel's .drv path; root validates it (one /nix/store/*.drv path
#    named nixos-system-<host>) and only realises that .drv (`nix build '<drv>^out'`, which
#    evaluates nothing);
#  - what the owner approves is what gets switched: the closure diff summary is computed by root
#    from the realised result against /run/current-system, shown in the touch notice and written
#    to last.json, and exactly that store path is the one switched;
#  - lux is not in nix.settings.trusted-users on legion (hosts/legion/configuration.nix), so lux
#    cannot pre-register store paths with forged content for the build to reuse: the daemon
#    takes only signed or content-addressed paths from lux;
#  - the touch is bound to this unit: its own PAM service, with its own u2f origin/appid and
#    its own authfile (u2f_keys_agent_switch), so a sudo/polkit/login touch cannot satisfy it.
# The former flake.lock input-type allowlist and the restricted-mode flake.nix/flake.lock
# comparison are gone: they only guarded root's own fetching and evaluation, which no longer
# exist, and they refused legitimate new inputs. nix still refuses a flake.nix that disagrees
# with flake.lock (--no-update-lock-file), now as lux.
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
  # Shared by the unit script and its ExecStopPost helper: write last.json and history.jsonl.
  commonFns = ''
    log() { echo "nixos-agent-switch: $*"; }

    # Write last.json (readable by the owner) and append one line to history.jsonl. Needs the
    # globals state, started, rev, drv, prev_sys, new_sys, summary, probes_json, probes_after_json.
    # `summary` is the closure diff summary root computed between prev_sys and the realised new_sys.
    finish() {
      outcome=$1 reason=$2
      jq -n --arg rev "$rev" --arg start "$started" --arg end "$(date -Is)" \
        --arg outcome "$outcome" --arg reason "$reason" --arg invocation "''${INVOCATION_ID:-}" \
        --arg drv "$drv" --arg from "$prev_sys" --arg to "$new_sys" --arg summary "$summary" \
        --argjson probes "$probes_json" --argjson after "$probes_after_json" \
        '{invocation: $invocation, rev: $rev, started: $start, ended: $end, outcome: $outcome, reason: $reason, drv: $drv, from: $from, to: $to, closure_diff: $summary, probes: $probes, probes_after_rollback: $after}' \
        > "$state/last.json.new"
      chmod 0644 "$state/last.json.new"
      mv "$state/last.json.new" "$state/last.json"
      jq -c . "$state/last.json" >> "$state/history.jsonl"
      tail -n 50 "$state/history.jsonl" > "$state/history.jsonl.new"
      chmod 0644 "$state/history.jsonl.new"
      mv "$state/history.jsonl.new" "$state/history.jsonl"
      log "result: $outcome ($reason)"
    }
  '';

  # Unit ExecStopPost: when the unit ended without a result for this invocation (killed by the
  # timeout, stopped mid-switch, SIGKILL), leave one.
  stopScript = pkgs.writeShellApplication {
    name = "nixos-agent-switch-stop";
    runtimeInputs = with pkgs; [coreutils jq];
    text = ''
      state=${stateDir}
      started="" rev="" drv="" prev_sys="" new_sys="" summary="" outcome="" reason="" probes_json="[]" probes_after_json="[]"
      ${commonFns}
      inv=''${INVOCATION_ID:-none}
      rm -f "$state/pending"
      if [ -r "$state/last.json" ] && [ "$(jq -r '.invocation // ""' "$state/last.json")" = "$inv" ]; then
        exit 0
      fi
      phase=unknown
      if [ -r "$state/current.json" ] && [ "$(jq -r '.invocation // ""' "$state/current.json")" = "$inv" ]; then
        phase=$(jq -r '.phase // "unknown"' "$state/current.json")
        rev=$(jq -r '.rev // ""' "$state/current.json")
        started=$(jq -r '.started // ""' "$state/current.json")
        prev_sys=$(jq -r '.from // ""' "$state/current.json")
        new_sys=$(jq -r '.to // ""' "$state/current.json")
        drv=$(jq -r '.drv // ""' "$state/current.json")
        summary=$(jq -r '.closure_diff // ""' "$state/current.json")
      fi
      [ -n "$started" ] || started=$(date -Is)
      finish interrupted "the unit ended without a result (service result ''${SERVICE_RESULT:-?}, exit ''${EXIT_STATUS:-?}, last phase $phase); check the journal and /run/current-system"
    '';
  };

  # testHooks = true builds a variant for dry runs as lux against a scratch repo and state dir:
  # env overrides, as-lux git without privileges. The production unit never has them.
  mkSwitchScript = testHooks:
    pkgs.writeShellApplication {
      name =
        "nixos-agent-switch"
        + lib.optionalString testHooks "-test";
      runtimeInputs = with pkgs; [
        coreutils
        diffutils
        findutils
        gawk
        git
        getent
        gnugrep
        iproute2
        jq
        nix
        nvd
        openssh
        pamtester
        systemd
        util-linux
      ];
      text = ''
        ${
          if testHooks
          then ''
            repo=''${AGENT_SWITCH_REPO:-${cfg.repo}}
            state=''${AGENT_SWITCH_STATE:-${stateDir}}
            attr=''${AGENT_SWITCH_ATTR:-nixosConfigurations.${cfg.hostName}.config.system.build.toplevel}
            profile=''${AGENT_SWITCH_PROFILE:-/nix/var/nix/profiles/system}
            agent_keys=''${AGENT_SWITCH_KEYS:-${cfg.u2fKeysFile}}
            nix_home=''${AGENT_SWITCH_NIX_HOME:-$state/home}
            # 1 = stop before the touch, probes = only run the probes.
            dry=''${AGENT_SWITCH_DRY_RUN:-0}
            # Not root: no groups to initialise, no capability bounding set to drop.
            owner_priv=(--no-new-privs --keep-groups)
          ''
          else ''
            repo=${lib.escapeShellArg cfg.repo}
            state=${stateDir}
            attr=nixosConfigurations.${cfg.hostName}.config.system.build.toplevel
            profile=/nix/var/nix/profiles/system
            agent_keys=${cfg.u2fKeysFile}
            nix_home=$state/home
            dry=0
            owner_priv=(--no-new-privs --init-groups --bounding-set=-all --inh-caps=-all)
          ''
        }
        owner=${cfg.user}
        touch_timeout=${toString cfg.touchTimeoutSec}
        eval_timeout=${toString cfg.evalTimeoutSec}
        build_timeout=${toString cfg.buildTimeoutSec}
        settle=${toString cfg.settleSec}
        notify_send=${lib.getExe' pkgs.libnotify "notify-send"}

        started=$(date -Is)
        rev="" drv="" prev_sys="" new_sys="" summary="" outcome="" reason="" probes_json="[]" probes_after_json="[]" phase=start
        ${commonFns}

        mkdir -p "$state"
        exec 9>"$state/lock"
        if ! flock -n 9; then
          log "another run holds the lock, nothing done"
          exit 1
        fi

        snap=$(mktemp -d)
        trap 'rm -rf "$snap"; rm -f "$state/pending"' EXIT
        rm -f "$state/pending"

        # Progress marker for the ExecStopPost helper (what ran last if the unit is cut off).
        progress() {
          phase=$1
          jq -n --arg i "''${INVOCATION_ID:-}" --arg phase "$phase" --arg rev "$rev" --arg start "$started" \
            --arg drv "$drv" --arg from "$prev_sys" --arg to "$new_sys" --arg summary "$summary" \
            '{invocation: $i, phase: $phase, rev: $rev, started: $start, drv: $drv, from: $from, to: $to, closure_diff: $summary}' \
            > "$state/current.json.new"
          mv "$state/current.json.new" "$state/current.json"
        }
        progress start

        # Anything unexpected still leaves a result file.
        on_error() {
          if [ -z "$outcome" ]; then
            finish error "unexpected failure at line $1 (phase $phase), see the journal"
          fi
        }
        trap 'on_error $LINENO' ERR

        # ---- 0. the touch key must be enrolled --------------------------------------------------
        # The unit's PAM service only accepts a credential made for it (own origin/appid): see
        # hosts/legion/u2f_keys_agent_switch. Until the owner has enrolled one, nothing can work.
        if ! grep -q "^$owner:" "$agent_keys"; then
          log "REFUSED: no YubiKey is enrolled for this unit ($agent_keys has no $owner line). The owner must run: pamu2fcfg -o pam://nixos-agent-switch -i pam://nixos-agent-switch, paste the line into hosts/legion/u2f_keys_agent_switch, commit it and switch"
          finish refused "touch key not enrolled for nixos-agent-switch (hosts/legion/u2f_keys_agent_switch has no $owner line)"
          exit 1
        fi

        # ---- 1. revision and dirty-tree check, as the owner ------------------------------------
        # The repo (and its .git/config) is writable by the owner, so root must not run git on it:
        # these calls run as the owner with an empty environment, no global/system gitconfig and
        # the config-driven exec points switched off. Their output is only data; the revision is
        # validated before it is used.
        owner_uid=$(id -u "$owner")
        owner_gid=$(id -g "$owner")
        owner_git() {
          timeout 120 setpriv --reuid "$owner_uid" --regid "$owner_gid" "''${owner_priv[@]}" \
            env -i "PATH=$PATH" HOME=/var/empty GIT_CONFIG_NOSYSTEM=1 GIT_CONFIG_GLOBAL=/dev/null \
              GIT_OPTIONAL_LOCKS=0 GIT_TERMINAL_PROMPT=0 GIT_ATTR_NOSYSTEM=1 \
            git -c core.fsmonitor=false -c core.hooksPath=/dev/null -c core.untrackedCache=false \
              -c core.pager=cat -c protocol.ext.allow=never "$@"
        }

        rev=$(owner_git -C "$repo" rev-parse --verify --quiet "refs/heads/main^{commit}") || rev=""
        head_rev=$(owner_git -C "$repo" rev-parse --verify --quiet "HEAD^{commit}") || head_rev=""
        if ! [[ $rev =~ ^[0-9a-f]{40}$ ]]; then
          log "REFUSED: cannot resolve main of $repo"
          finish refused "cannot resolve main of $repo"
          exit 1
        fi
        progress checked
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
        owner_git -C "$repo" status --porcelain -z --untracked-files=no > "$snap/status" \
          || { finish refused "git status as $owner failed"; exit 1; }
        while IFS= read -r -d "" entry; do
          status=''${entry:0:2}
          path=''${entry:3}
          case $status in
            *R* | *C*) IFS= read -r -d "" orig || true; is_ignored "$orig" || dirty="$dirty $orig" ;;
          esac
          is_ignored "$path" || dirty="$dirty $path"
        done < "$snap/status"
        if [ -n "$dirty" ]; then
          log "REFUSED: uncommitted changes to files legion can import (commit or stash them first):"
          for p in $dirty; do log "  $p"; done
          finish refused "uncommitted changes:$dirty"
          exit 1
        fi

        # ---- 2. evaluate as the owner, realise as root -------------------------------------------
        # H2 and the fetchTree hole: root never evaluates Nix code from the repo. The owner runs the
        # evaluation (same setpriv as the git calls), so a committed .nix file (builtins.fetchTree or
        # fetchGit on a root-readable path, import of a planted file, import-from-derivation) can only
        # do what the owner can do. The result is one .drv path; root validates it and only realises
        # that derivation, which evaluates nothing.
        # The owner's nix gets its own HOME, in the state dir: the eval and fetcher caches survive
        # between runs, and the owner's ~/.config/nix/nix.conf (plugin-files, ...) stays out of it.
        # ssh finds the owner's keys and known_hosts through the passwd home directory, not $HOME, so
        # a git+ssh flake input works from here; BatchMode makes a key that needs a passphrase or a
        # touch fail the evaluation (a refusal) instead of hanging the unit.
        owner_home=$(getent passwd "$owner" | cut -d: -f6)
        eval_home=$state/eval-home
        mkdir -p "$eval_home"
        chown "$owner_uid:$owner_gid" "$eval_home"
        chmod 0700 "$eval_home"
        ssh_cmd=${lib.escapeShellArg cfg.evalSshCommand}
        if [ -r "$owner_home/.ssh/config" ]; then ssh_cmd="$ssh_cmd -F $owner_home/.ssh/config"; fi
        owner_nix() {
          timeout "$eval_timeout" setpriv --reuid "$owner_uid" --regid "$owner_gid" "''${owner_priv[@]}" \
            env -i "PATH=$PATH" "HOME=$eval_home" NIX_REMOTE=daemon GIT_TERMINAL_PROMPT=0 \
              "GIT_SSH_COMMAND=$ssh_cmd" \
            nix --extra-experimental-features 'nix-command flakes' "$@"
        }

        progress eval
        ref="git+file://$repo?rev=$rev#$attr"
        log "evaluating $ref as $owner"
        # --no-update-lock-file: nix refuses when flake.nix and flake.lock disagree, and then writes
        # nothing into the owner's tree. (Do NOT add --no-write-lock-file: together they make nix go
        # on with an in-memory lock instead of refusing; verified.)
        drv=$(owner_nix eval --raw --no-update-lock-file --no-use-registries "$ref.drvPath" 2> "$snap/eval.err" | head -c 1024) || drv=""
        drv_re='^/nix/store/[0-9a-z]{32}-[A-Za-z0-9+._?=-]+\.drv$'
        if ! [[ $drv =~ $drv_re ]] || [[ $drv != *-nixos-system-${cfg.hostName}-*.drv ]]; then
          log "REFUSED: the evaluation as $owner did not give one nixos-system-${cfg.hostName} .drv path: $(head -c 600 "$snap/eval.err" | tr '\n' ' ')"
          drv=""
          finish refused "evaluating $rev as $owner failed or gave no nixos-system-${cfg.hostName} .drv path (see the journal)"
          exit 1
        fi
        if [ ! -f "$drv" ] || [ -L "$drv" ]; then
          log "REFUSED: $drv is not a regular file in the store"
          finish refused "$drv is not a regular file in the store"
          exit 1
        fi
        log "derivation $drv"

        mkdir -p "$nix_home"
        chmod 0700 "$nix_home"
        export HOME="$nix_home"
        prev_sys=$(readlink -f /run/current-system)
        progress build
        log "realising $drv"
        # --out-link roots the result in the state dir while we wait for the touch (removed on exit).
        # `<drv>^out` is a derivation, not a flake reference: nothing is evaluated here.
        if ! new_sys=$(timeout "$build_timeout" nix build --out-link "$state/pending" --print-out-paths \
              --no-use-registries --extra-experimental-features nix-command ${lib.escapeShellArgs cfg.extraNixArgs} "$drv^out"); then
          new_sys=""
          finish build-failed "nix build of the derivation failed or timed out (limit $build_timeout s); see the journal"
          exit 1
        fi
        out_re='^/nix/store/[0-9a-z]{32}-[A-Za-z0-9+._?=-]+$'
        if ! [[ $new_sys =~ $out_re ]] || [ "$(nix-store --query --outputs "$drv")" != "$new_sys" ]; then
          log "REFUSED: the realised path '$new_sys' is not the output of $drv"
          new_sys=""
          finish refused "the realised path is not the output of $drv"
          exit 1
        fi
        log "built $new_sys"

        if [ "$new_sys" = "$prev_sys" ]; then
          log "the running system already is this build, nothing to switch"
          finish unchanged "running system equals the build of $rev"
          exit 0
        fi

        # A switch must never remove the unit that runs it (the cgroup kill would cut the
        # activation, the probes and the rollback).
        if [ ! -e "$new_sys/etc/systemd/system/nixos-agent-switch.service" ]; then
          log "REFUSED: $new_sys has no nixos-agent-switch.service; switching would stop this unit mid-run"
          finish refused "the built system does not contain nixos-agent-switch.service"
          exit 1
        fi

        # The summary is computed by root from the realised result: it is what the touch notice and
        # last.json show, and $new_sys is the very path that is switched below.
        diff_out=$(nvd --color never diff "$prev_sys" "$new_sys" || true)
        log "closure diff against $prev_sys:"
        printf '%s\n' "$diff_out"
        summary="$(printf '%s\n' "$diff_out" | tail -n 1); $(printf '%s\n' "$diff_out" | grep -c '^\[' || true) entries changed"
        progress diffed

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
        progress touch
        log "TOUCH REQUIRED: touch the YubiKey within $touch_timeout s to switch legion to ''${rev:0:12} (result ''${new_sys:11:12}): $summary"
        if [ "$dry" = 1 ]; then
          log "dry run: stopping before the touch"
          finish dry-run "stopped before the touch"
          exit 0
        fi
        msg="Touch the YubiKey within $touch_timeout s to switch legion to ''${rev:0:12} (result ''${new_sys:11:12}). $summary"
        timeout 10 systemd-run --machine="$owner@.host" --user --collect --quiet \
            "$notify_send" -u critical -t $((touch_timeout * 1000)) -a nixos-agent-switch "legion switch waiting for you" "$msg" \
          || timeout 10 setpriv --reuid "$owner_uid" --regid "$owner_gid" --init-groups \
            env "DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/$owner_uid/bus" \
            "$notify_send" -u critical -t $((touch_timeout * 1000)) -a nixos-agent-switch "legion switch waiting for you" "$msg" \
          || log "no desktop notification (the touch prompt is only in the journal)"

        if ! timeout "$touch_timeout" pamtester nixos-agent-switch "$owner" authenticate; then
          finish no-touch "no YubiKey touch within $touch_timeout s (or authentication failed)"
          exit 1
        fi
        log "touch accepted"
        # What was shown (and approved) is the realised path: it must still be the one rooted here.
        if [ "$(readlink -f "$state/pending")" != "$new_sys" ] || [ ! -x "$new_sys/bin/switch-to-configuration" ]; then
          finish refused "the rooted result no longer is $new_sys; nothing switched"
          exit 1
        fi

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
        # After a rollback, units the new system failed and the old one does not know stay as
        # `not-found failed`; clear them so the probes judge the restored system.
        reset_orphan_failures() {
          local u
          while read -r u; do
            [ -n "$u" ] || continue
            if [ "$(systemctl show -p LoadState --value "$u")" = not-found ]; then
              systemctl reset-failed "$u" || true
            fi
          done < <(failed_units | grep -vxFf "$snap/failed-before" || true)
        }

        progress switch
        nix-env -p "$profile" --set "$new_sys"
        switch_rc=0
        "$new_sys/bin/switch-to-configuration" switch || switch_rc=$?
        log "switch-to-configuration exited $switch_rc; waiting $settle s before probes"
        sleep "$settle"
        progress probes
        run_all_probes

        if [ "$switch_rc" != 0 ] || [ "$probes_failed" != 0 ]; then
          progress rollback
          first_probes=$probes_json
          if roll_back; then
            sleep "$settle"
            reset_orphan_failures
            run_all_probes
            probes_after_json=$probes_json
            probes_json=$first_probes
            if [ "$probes_failed" = 0 ]; then
              finish rolled-back "switch exit $switch_rc, probes failed; back on $prev_sys, probes after the rollback pass"
            else
              finish rolled-back-degraded "switch exit $switch_rc, probes failed; back on $prev_sys, but probes after the rollback still fail (see probes_after_rollback): owner must look"
            fi
          else
            finish rollback-failed "switch exit $switch_rc, probes failed; the rollback itself failed, owner must act"
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
    u2fKeysFile = lib.mkOption {
      type = lib.types.path;
      default = ./u2f_keys_agent_switch;
      description = ''
        pamu2fcfg output for this unit's own credential (origin/appid pam://nixos-agent-switch).
        The unit refuses while it has no line for the owner.
      '';
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
    evalTimeoutSec = lib.mkOption {
      type = lib.types.ints.positive;
      default = 1800;
      description = "Limit for the evaluation the owner runs (the first run fetches the flake inputs).";
    };
    evalSshCommand = lib.mkOption {
      type = lib.types.str;
      default = "ssh -o BatchMode=yes";
      description = ''
        GIT_SSH_COMMAND of the owner's evaluation, for a git+ssh flake input. The owner's ~/.ssh/config
        is added with -F when it exists. BatchMode: a key that needs a passphrase or a touch fails the
        evaluation (the run is refused) instead of waiting. The key and known_hosts of the owner must
        therefore work without a prompt.
      '';
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
      default = mkSwitchScript false;
      readOnly = true;
      internal = true;
      description = "The switch script (exposed so it can be built and run on its own).";
    };
    testPackage = lib.mkOption {
      type = lib.types.package;
      default = mkSwitchScript true;
      readOnly = true;
      internal = true;
      description = "Same script with env overrides for dry runs as the owner; never used by the unit.";
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
    # The u2f rule has its own origin, appid and authfile, so only a credential enrolled for this
    # unit works: a sudo, login or polkit touch (origin pam://legion) cannot satisfy it, and a
    # touch for this unit cannot satisfy those.
    security.pam.services.nixos-agent-switch = {
      unixAuth = false;
      u2f.enable = true;
      rules.auth.u2f.settings = {
        origin = lib.mkForce "pam://nixos-agent-switch";
        appid = lib.mkForce "pam://nixos-agent-switch";
        authfile = lib.mkForce "${cfg.u2fKeysFile}";
        cue = lib.mkForce true;
      };
    };

    # The stack must stay exactly: pam_u2f (sufficient), pam_deny. A future global PAM option
    # (fprint, rssh, ...) that adds an auth path without a touch fails the build instead.
    assertions = let
      svc = config.security.pam.services.nixos-agent-switch;
      authRules = lib.attrNames (lib.filterAttrs (_: r: r.enable) svc.rules.auth);
    in [
      {
        assertion = lib.sort lib.lessThan authRules == ["deny" "u2f"];
        message = "security.pam.services.nixos-agent-switch must authenticate with pam_u2f and pam_deny only, found auth rules: ${lib.concatStringsSep ", " authRules}";
      }
    ];

    systemd.services.nixos-agent-switch = {
      description = "Build committed main of /etc/nixos, switch legion after a YubiKey touch, roll back on a failed probe";
      # Start only. A switch must never restart or stop its own unit.
      restartIfChanged = false;
      stopIfChanged = false;
      serviceConfig = {
        Type = "oneshot";
        User = "root";
        ExecStart = lib.getExe cfg.package;
        # Leaves a result when the unit is cut off (timeout, stop, kill) before the script wrote one.
        ExecStopPost = lib.getExe stopScript;
        # Build (buildTimeoutSec) + touch + switch + probes, with room to spare.
        TimeoutStartSec = "2h";
        TimeoutStopSec = "60s";
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
