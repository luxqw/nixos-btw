# Agent housekeeping for the laptop (home-manager user units):
#  - agent-cleanup: weekly disk cleanup (owner policy NX-1, no questions asked)
#  - t3-db-snapshot: daily streamed dump of the T3 state DB to homelab
# Claude transcripts are not in the offsite restic paths (owner decision DP-7).
{
  lib,
  pkgs,
  ...
}: let
  home = "/home/lux";

  cleanup = pkgs.writeShellApplication {
    name = "agent-cleanup";
    runtimeInputs = with pkgs; [coreutils findutils gawk git gnugrep nix sqlite];
    text = ''
      dry=''${CLEANUP_DRY_RUN:-0}
      repo=''${CLEANUP_REPO:-${home}/Documents/projects/dispatcher}
      wtroot=''${CLEANUP_WORKTREES:-${home}/.t3/worktrees/dispatcher}
      db=${home}/.t3/userdata/statev2.sqlite
      now=$(date +%s)
      today=$(date +%F)
      n_codex=0 n_wt=0 n_tag=0 n_tr=0 n_skip=0

      run() { if [ "$dry" = 1 ]; then echo "dry-run: $*"; else "$@"; fi; }

      # 1. nix store GC. Never -d: system generations stay.
      if [ "$dry" = 1 ]; then
        nix-collect-garbage --dry-run 2>&1 | tail -n 1 || true
      else
        nix-collect-garbage 2>&1 | tail -n 1 || echo "nix-collect-garbage failed"
      fi

      # 2. leaked Codex temp dirs (read-only trees), older than 1 day
      while IFS= read -r d; do
        [ -n "$d" ] || continue
        run chmod -R u+w "$d"
        run rm -rf "$d"
        n_codex=$((n_codex + 1))
      done < <(find ${home}/.codex/.tmp/bundled-marketplaces -maxdepth 1 -name 'openai-bundled.staging-*' -mtime +1 2>/dev/null;
               find ${home}/.codex/.tmp -maxdepth 1 -name 'git-*' -mtime +1 2>/dev/null)

      # 3. merged, clean, old, unlinked dispatcher worktrees
      # Clean = no changes, and no ignored files besides test dirs, caches and build links.
      wt_clean() {
        local l p b
        while IFS= read -r l; do
          case $l in
            "!! "*)
              p=''${l#"!! "}; p=''${p%/}; b=''${p##*/}
              case $b in .pt* | __pycache__ | node_modules | result*) ;; *) return 1 ;; esac ;;
            *) return 1 ;;
          esac
        done < <(git -C "$1" status --porcelain --ignored 2>/dev/null || echo dirty)
        return 0
      }

      if [ -d "$repo/.git" ] || [ -f "$repo/.git" ]; then
        mainbranch=$(git -C "$repo" symbolic-ref -q --short HEAD || true)
        open_links=$(sqlite3 -readonly "$db" "select json_extract(payload_json,'\$.worktreePath') from orchestration_v2_projection_threads where archived_at is null and deleted_at is null and json_extract(payload_json,'\$.settledAt') is null and json_extract(payload_json,'\$.worktreePath') is not null" 2>/dev/null) && links_ok=1 || links_ok=0
        if [ "$links_ok" = 1 ]; then
          path="" branch="" locked=0
          while IFS= read -r line || [ -n "$path" ]; do
            case $line in
              "worktree "*) path=''${line#worktree } branch="" locked=0 ;;
              "branch refs/heads/"*) branch=''${line#branch refs/heads/} ;;
              locked* | prunable*) locked=1 ;;
              "")
                if [ -n "$path" ] && [ -n "$branch" ] && [ "$locked" = 0 ]; then
                  case $path in "$wtroot"/*)
                    skip=1
                    case $branch in main | master | "$mainbranch") ;; *)
                      if git -C "$repo" merge-base --is-ancestor "$branch" main 2>/dev/null \
                        && wt_clean "$path" \
                        && ! printf '%s\n' "$open_links" | grep -qxF "$path"; then
                        ct=$(git -C "$repo" log -1 --format=%ct "$branch" 2>/dev/null || echo "$now")
                        [ $((now - ct)) -gt 604800 ] && skip=0
                      fi ;;
                    esac
                    if [ "$skip" = 0 ]; then
                      tag="archive/$today/$branch"
                      git -C "$repo" rev-parse -q --verify "refs/tags/$tag" >/dev/null && tag="$tag-$(date +%H%M%S)"
                      if ! run git -C "$repo" tag "$tag" "$branch"; then
                        echo "worktree $path: tag failed, kept"; n_skip=$((n_skip + 1))
                      elif ! run git -C "$repo" worktree remove "$path"; then
                        echo "worktree $path: remove failed, kept"
                        run git -C "$repo" tag -d "$tag" >/dev/null || true
                        n_skip=$((n_skip + 1))
                      else
                        run git -C "$repo" branch -D "$branch" >/dev/null || echo "branch $branch: delete failed"
                        n_wt=$((n_wt + 1))
                      fi
                    else
                      n_skip=$((n_skip + 1))
                    fi ;;
                  esac
                elif [ -n "$path" ]; then
                  case $path in "$wtroot"/*) n_skip=$((n_skip + 1)) ;; esac
                fi
                path="" branch="" locked=0 ;;
            esac
          done < <(git -C "$repo" worktree list --porcelain; echo)
        else
          echo "worktrees: T3 DB unreadable, skipped"
        fi
        # archive tags older than 30 days (date is in the tag name)
        while IFS= read -r t; do
          d=''${t#archive/}; d=''${d%%/*}
          ts=$(date -d "$d" +%s 2>/dev/null) || continue
          if [ $((now - ts)) -gt 2592000 ]; then
            if run git -C "$repo" tag -d "$t" >/dev/null; then n_tag=$((n_tag + 1)); fi
          fi
        done < <(git -C "$repo" tag -l 'archive/*')
      fi

      # 4. transcripts: 60 days local, no offsite copy (owner decision DP-7)
      for dir in ${home}/.claude/projects ${home}/.codex/sessions ${home}/.codex/archived_sessions; do
        [ -d "$dir" ] || continue
        while IFS= read -r f; do
          run rm -f -- "$f" || continue
          n_tr=$((n_tr + 1))
          case $dir in
            */.claude/projects)
              s=''${f%.jsonl}
              if [ -d "$s" ] && [ -z "$(find "$s" -mtime -61 -print -quit 2>/dev/null)" ]; then
                run rm -rf -- "$s" || true
              fi ;;
          esac
        done < <(find "$dir" -type f \( -name '*.jsonl' -o -name '*.jsonl.zst' \) -mtime +60 2>/dev/null)
      done
      [ "$dry" = 1 ] || find ${home}/.codex/sessions -mindepth 1 -type d -empty -delete 2>/dev/null || true

      echo "agent-cleanup: dry=$dry codex_tmp=$n_codex worktrees_removed=$n_wt worktrees_kept=$n_skip archive_tags_deleted=$n_tag transcripts_deleted=$n_tr"
    '';
  };

  snapshot = pkgs.writeShellApplication {
    name = "t3-db-snapshot";
    runtimeInputs = with pkgs; [coreutils openssh sqlite zstd];
    text = ''
      db=''${T3_DB:-${home}/.t3/userdata/statev2.sqlite}
      target=''${SNAP_SSH_TARGET:-homelab}
      keep=''${SNAP_KEEP:-7}
      name=statev2-$(date +%Y%m%dT%H%M%S).sql.zst
      # shellcheck disable=SC2206
      ssh_opts=(-o BatchMode=yes -o ConnectTimeout=10 -o ServerAliveInterval=30 -o ServerAliveCountMax=4 -o ForwardAgent=no ''${SNAP_SSH_OPTS:-})

      qc=$(nice -n 10 sqlite3 -readonly "$db" 'PRAGMA quick_check' | head -n 1)
      if [ "$qc" != ok ]; then
        echo "t3-db-snapshot: quick_check says '$qc', aborting" >&2
        exit 1
      fi

      ok=0
      cleanup_remote() {
        if [ "$ok" != 1 ]; then
          # shellcheck disable=SC2029
          ssh "''${ssh_opts[@]}" "$target" "rm -f ~/backups/t3/$name.part" || true
        fi
      }
      trap cleanup_remote EXIT

      # Drop leftovers of earlier failed runs, then stream one read transaction:
      # no local copy of the 3+ GB DB is written.
      # shellcheck disable=SC2029
      ssh "''${ssh_opts[@]}" "$target" "umask 077; mkdir -p ~/backups/t3 && find ~/backups/t3 -name '*.part' -delete"
      # shellcheck disable=SC2029
      nice -n 10 sqlite3 -readonly "$db" .dump | nice -n 10 zstd -T0 -3 -q \
        | ssh "''${ssh_opts[@]}" "$target" "umask 077; cat > ~/backups/t3/$name.part"

      # Verify on the far side (valid zstd, dump ends with COMMIT;), publish atomically,
      # and only then prune to the newest $keep.
      # shellcheck disable=SC2029
      ssh "''${ssh_opts[@]}" "$target" "cd ~/backups/t3 && zstd -tq $name.part \
        && zstd -dcq $name.part | tail -n 1 | grep -qx 'COMMIT;' && mv $name.part $name \
        && ls -1 statev2-*.sql.zst | sort -r | tail -n +$((keep + 1)) | xargs -r rm -- \
        && ls -1 statev2-*.sql.zst | wc -l && ls -l $name"
      ok=1
      echo "t3-db-snapshot: wrote $target:backups/t3/$name"
    '';
  };
in {
  home-manager.users.lux = {
    systemd.user.services = {
      agent-cleanup = {
        Unit.Description = "Weekly agent cleanup (nix GC, temp dirs, worktrees, transcripts)";
        Service = {
          Type = "oneshot";
          ExecStart = lib.getExe cleanup;
          Nice = 10;
          IOSchedulingClass = "idle";
        };
      };
      t3-db-snapshot = {
        Unit.Description = "Stream a T3 state DB snapshot to homelab";
        Service = {
          Type = "oneshot";
          ExecStart = lib.getExe snapshot;
          TimeoutStartSec = "2h";
          Nice = 10;
          IOSchedulingClass = "idle";
        };
      };
    };
    systemd.user.timers = {
      agent-cleanup = {
        Unit.Description = "Weekly agent cleanup";
        Timer = {
          OnCalendar = "weekly";
          Persistent = true;
          RandomizedDelaySec = "1h";
        };
        Install.WantedBy = ["timers.target"];
      };
      t3-db-snapshot = {
        Unit.Description = "Daily T3 DB snapshot to homelab";
        Timer = {
          OnCalendar = "daily";
          Persistent = true;
          RandomizedDelaySec = "1h";
        };
        Install.WantedBy = ["timers.target"];
      };
    };
  };
}
