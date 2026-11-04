{
  lib,
  stdenvNoCC,
  rustPlatform,
  makeWrapper,
  pkg-config,
  pipewire,
  python3,
  src,
  # Runtime tools, from the README's required table.
  quickshell,
  niri,
  matugen,
  zenity,
  imagemagick,
  librsvg,
  wl-clipboard,
  grim,
  slurp,
  tesseract,
  wl-screenrec,
  fd,
  jq,
  libqalculate,
  xdg-utils,
  curl,
  brightnessctl,
  ddcutil,
  pciutils,
  libnotify,
  glib,
  libsecret,
  networkmanager,
  bluez,
  cups,
  avahi,
  upower,
  power-profiles-daemon,
  gamemode,
  fontconfig,
  udisks,
  hyprlock,
  systemd,
  util-linux,
  procps,
  coreutils,
  findutils,
  gnugrep,
  gnused,
  gawk,
  bash,
  # Files the package points at instead of /usr.
  xkeyboard_config,
  sound-theme-freedesktop,
  qt6,
}: let
  sinestesia-bands = rustPlatform.buildRustPackage {
    pname = "sinestesia-bands";
    version = "0.1.0";
    src = "${src}/tools/sinestesia-bands";
    cargoLock.lockFile = "${src}/tools/sinestesia-bands/Cargo.lock";
    nativeBuildInputs = [pkg-config rustPlatform.bindgenHook];
    buildInputs = [pipewire];
    meta.mainProgram = "sinestesia-bands";
  };

  python = python3.withPackages (ps: [ps.python-dateutil ps.evdev]);

  # pipewire provides pw-play and pw-record; the rest are what the QML and
  # scripts call by name. pkexec lives in /run/wrappers (setuid).
  path = lib.makeBinPath [
    quickshell
    niri
    python
    matugen
    zenity
    imagemagick
    librsvg
    wl-clipboard
    grim
    slurp
    tesseract
    wl-screenrec
    fd
    jq
    libqalculate
    xdg-utils
    curl
    brightnessctl
    ddcutil
    pciutils
    libnotify
    glib
    libsecret
    networkmanager
    bluez
    cups
    avahi
    upower
    power-profiles-daemon
    gamemode
    fontconfig
    udisks
    hyprlock
    pipewire
    systemd
    util-linux
    procps
    coreutils
    findutils
    gnugrep
    gnused
    gawk
    bash
  ];
in
  stdenvNoCC.mkDerivation {
    pname = "bioma";
    version = "1.0.0-beta.60";
    inherit src;

    nativeBuildInputs = [makeWrapper python];

    dontConfigure = true;
    dontBuild = true;

    installPhase = ''
      runHook preInstall

      share=$out/share/bioma
      mkdir -p $share
      cp -r --no-preserve=ownership assets cells components config core greeter lock organisms services structure scripts $share/
      chmod -R u+w $share
      install -m644 shell.qml lock.qml greeter.qml $share/

      # The shell looks for the spectrum tool inside its own tree.
      mkdir -p $share/tools/sinestesia-bands/target/release
      ln -s ${sinestesia-bands}/bin/sinestesia-bands $share/tools/sinestesia-bands/target/release/sinestesia-bands

      install -Dm644 LICENSE $out/share/licenses/bioma/LICENSE
      install -Dm644 README.md $out/share/doc/bioma/README.md
      install -Dm644 docs/configuration.md $out/share/doc/bioma/configuration.md

      # The store is read-only and has no /usr.

      # The lock screen's PAM stack is the NixOS service security.pam.services.bioma-lock.
      substituteInPlace $share/lock.qml \
        --replace-fail 'configDirectory: Qt.resolvedUrl("assets/pam").toString().replace("file://", "")' \
                       'configDirectory: "/etc/pam.d"'

      # The service starts with pam_u2f, so Enter with an empty field must
      # start PAM too (touch the key). pam_unix has no nullok, so an empty
      # password still fails. pam_u2f's cue ("Please touch the device") is
      # shown on the line where the lock already puts its errors.
      substituteInPlace $share/lock.qml \
        --replace-fail 'if (root.checking || root.password.length === 0)' 'if (root.checking)' \
        --replace-fail 'root.checking = true;' 'root.checking = true; root.reason = "";' \
        --replace-fail 'config: "bioma-lock"' 'config: "bioma-lock"; onPamMessage: { if (!responseRequired) root.reason = message; }'
      substituteInPlace $share/components/Gate.qml \
        --replace-fail 'opacity: root.gate.failed ? 1 : 0' 'opacity: root.gate.failed || (root.gate.checking && root.gate.reason.length > 0) ? 1 : 0' \
        --replace-fail 'color: Theme.alert' 'color: root.gate.failed ? Theme.alert : Theme.textMuted'

      substituteInPlace $share/scripts/xkb \
        --replace-fail '/usr/share/X11/xkb/rules/evdev.lst' '${xkeyboard_config}/share/X11/xkb/rules/evdev.lst'

      # NixOS keeps the booted kernel's modules under /run/booted-system, so
      # the "restart due" check finds them for as long as the system runs.
      substituteInPlace $share/services/Session.qml \
        --replace-fail '/usr/lib/modules/''${root.release}/pkgbase' '/run/booted-system/kernel-modules/lib/modules/''${root.release}/modules.dep'

      substituteInPlace $share/services/Time.qml \
        --replace-fail '/usr/share/sounds/freedesktop/stereo/alarm-clock-elapsed.oga' '${sound-theme-freedesktop}/share/sounds/freedesktop/stereo/alarm-clock-elapsed.oga'

      # Noctalia stays a separate session on this machine: the shell switch
      # must never stop it, start it, or remember it.
      substituteInPlace $share/scripts/shell \
        --replace-fail 'noctalia_running() { pgrep -x noctalia >/dev/null 2>&1; }' 'noctalia_running() { return 1; }' \
        --replace-fail 'noctalia_installed() { command -v noctalia >/dev/null 2>&1; }' 'noctalia_installed() { return 1; }'

      # The login screen is declarative here (greetd, /etc/pam.d and the
      # display-manager unit are NixOS-managed); the script would fight it.
      substituteInPlace $share/scripts/greeter-setup \
        --replace-fail '    enable) enable ;;' '    enable|disable) echo "the login screen is managed by NixOS" >&2; exit 1 ;;'

      # `qs -p` and the scripts above find a running Bioma only by the exact
      # store path they were built with. After an update the surviving shell
      # keeps its old path, so everything here is made to find the running
      # instance whatever store path it started from: by the config path
      # `qs list` reports, which always ends in /share/bioma/shell.qml (and so
      # never matches another shell such as Noctalia). On Nix the process is
      # `.../bin/quickshell -p ...`, not `qs -p ...`, so upstream's pgrep
      # patterns matched nothing here.
      cat > $share/scripts/bioma-pids <<'EOF'
      #!/usr/bin/env bash
      # bioma-pids: the pids of the running Bioma shells (not the lock screen).
      {
        qs list --all --json 2>/dev/null | jq -r '.[] | select(.config_path | test("/share/bioma/shell\\.qml$")) | .pid' 2>/dev/null
        pgrep -f -- '(^|/)(qs|quickshell|\.quickshell-wrapped) -p [^ ]*/share/bioma/shell\.qml$' 2>/dev/null
      } | sort -u
      exit 0
      EOF
      cat > $share/scripts/ipc <<'EOF'
      #!/usr/bin/env bash
      # ipc TARGET FUNCTION [ARGS...]: qs ipc call into the running Bioma, from
      # whichever store path it started. With none running, the same call
      # upstream makes (this package's path), which says so.
      here="$(cd "$(dirname "$(readlink -f "''${BASH_SOURCE[0]}")")/.." && pwd)"
      pid="$("$here/scripts/bioma-pids" | head -n 1)"
      if [ -n "$pid" ]; then
        exec qs ipc --pid "$pid" call "$@"
      fi
      exec qs -p "$here/shell.qml" ipc call "$@"
      EOF
      chmod +x $share/scripts/ipc $share/scripts/bioma-pids

      substituteInPlace $share/scripts/key \
        --replace-fail 'qs -p "$here/shell.qml" ipc call "$@" >/dev/null 2>&1 || true' '"$here/scripts/ipc" "$@" >/dev/null 2>&1 || true' \
        --replace-fail 'running_bioma() { pgrep -f -- "qs -p $here/shell.qml" >/dev/null 2>&1; }' 'running_bioma() { [ -n "$("$here/scripts/bioma-pids")" ]; }'
      substituteInPlace $share/scripts/shell \
        --replace-fail 'bioma_pattern="qs -p $here/shell.qml"' "bioma_pattern='(^|/)(qs|quickshell|\\.quickshell-wrapped) -p [^ ]*/share/bioma/shell\\.qml\$'" \
        --replace-fail 'if ($0 == want && pid != "")' 'if ($0 ~ /\/share\/bioma\/shell\.qml$/ && pid != "")'
      substituteInPlace $share/scripts/lock \
        --replace-fail 'lock_pattern="qs -p $here/lock.qml"' "lock_pattern='(^|/)(qs|quickshell|\\.quickshell-wrapped) -p [^ ]*/share/bioma/lock\\.qml\$'"
      substituteInPlace $share/scripts/setup-scan \
        --replace-fail 'grep -qF "$here/"' "grep -qE '/share/bioma/'"

      patchShebangs --build $share/scripts

      # Every script is also run on its own (niri binds, systemd-run), so each
      # carries the PATH and the Qt 5 compat import it needs.
      for f in $share/scripts/*; do
        case $f in *.py) continue ;; esac
        wrapProgram $f \
          --suffix PATH : ${path}:/run/wrappers/bin:/run/current-system/sw/bin \
          --prefix QML2_IMPORT_PATH : ${qt6.qt5compat}/${qt6.qtbase.qtQmlPrefix}
      done

      mkdir -p $out/bin
      ln -s $share/scripts/bioma $out/bin/bioma

      runHook postInstall
    '';

    passthru = {inherit sinestesia-bands;};

    meta = {
      description = "A desktop shell for niri, built with Quickshell";
      homepage = "https://github.com/AkusenArcade/Bioma";
      license = lib.licenses.gpl3Plus;
      mainProgram = "bioma";
      platforms = lib.platforms.linux;
    };
  }
