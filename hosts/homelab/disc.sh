set -E

usage() {
  cat <<'USAGE'
disc — rip and burn discs on homelab

  disc auto [dev]                   what udev runs on insert: rip a disc, or
                                    burn the one non-empty Burn folder onto a blank
  disc rip [dev]                    rip whatever is in the drive
  disc burn data|audio|video [dir]  burn dir (default: the Burn space folder)
  disc status [dev]                 what the drive holds

Burn folders: $BURN_ROOT/{data,audio,video}. Burned files move to
$BURN_ROOT/done/. Rewritables that aren't blank are only erased by an
explicit `disc burn`.
USAGE
}

notify() {
  if [ -z "${TELEGRAM_TOKEN:-}" ] && [ -r "$TELEGRAM_ENV" ]; then
    set -a
    # shellcheck source=/dev/null
    . "$TELEGRAM_ENV"
    set +a
  fi
  echo "$1"
  [ -n "${TELEGRAM_TOKEN:-}" ] || return 0
  curl -sf -o /dev/null "https://api.telegram.org/bot$TELEGRAM_TOKEN/sendMessage" \
    --data-urlencode "chat_id=$TELEGRAM_CHAT_ID" \
    --data-urlencode "text=💿 $1" || true
}

die() {
  notify "$1"
  exit 1
}

prop() {
  udevadm info --query=property --name="$dev" | sed -n "s/^$1=//p"
}

label() {
  local name
  name=$(prop ID_FS_LABEL | tr -c 'A-Za-z0-9._-' '_' | sed 's/_*$//')
  echo "${name:-disc-$(date +%F-%H%M)}"
}

kind() {
  if [ "$(prop ID_CDROM_MEDIA)" != 1 ]; then
    echo none
  elif [ "$(prop ID_CDROM_MEDIA_STATE)" = blank ]; then
    echo blank
  elif [ -n "$(prop ID_CDROM_MEDIA_TRACK_COUNT_AUDIO)" ] && [ -z "$(prop ID_CDROM_MEDIA_TRACK_COUNT_DATA)" ]; then
    echo audio
  elif isoinfo -d -i "$dev" >/dev/null 2>&1 && isoinfo -f -i "$dev" 2>/dev/null | grep -qi '^/VIDEO_TS'; then
    echo video
  else
    echo data
  fi
}

workdir() {
  mkdir -p "$MEDIA/.disc"
  mktemp -d "$MEDIA/.disc/$1.XXXXXX"
}

own() {
  chown -R lux:media "$@"
  chmod -R g+rwX "$@"
}

rip_audio() {
  notify "Рип аудио-CD начался"
  abcde -N -x -c "$ABCDE_CONF" -d "$dev"
  find "$MEDIA/music" -user root -exec chown lux:media {} +
  notify "Аудио-CD готов: $MEDIA/music"
}

rip_video() {
  local name work
  name=$(label)
  work=$(workdir dvd)
  notify "Рип DVD «$name» начался"
  dvdbackup -M -i "$dev" -o "$work" -n "$name"
  eject "$dev"
  HandBrakeCLI -i "$work/$name" --main-feature -f av_mkv \
    -e x265 -q 22 --encoder-preset medium \
    --all-audio --aencoder copy --audio-fallback av_aac \
    --all-subtitles \
    -o "$MEDIA/movies/$name.mkv"
  rm -rf "$work"
  own "$MEDIA/movies/$name.mkv"
  notify "DVD «$name» готов: $MEDIA/movies/$name.mkv"
}

rip_data() {
  local name mnt dest
  name=$(label)
  mnt=$(mktemp -d)
  dest="$MEDIA/discs/$name"
  notify "Копирование диска «$name» началось"
  mount -o ro "$dev" "$mnt"
  mkdir -p "$dest"
  cp -r --no-preserve=ownership,mode "$mnt"/. "$dest"
  umount "$mnt"
  rmdir "$mnt"
  eject "$dev"
  own "$dest"
  notify "Диск «$name» скопирован: $dest"
}

rip() {
  case $(kind) in
    none) die "В приводе нет диска" ;;
    blank) die "Диск пустой, рипать нечего" ;;
    audio) rip_audio ;;
    video) rip_video ;;
    data) rip_data ;;
  esac
}

burn_data() {
  local iso
  iso="$(workdir data)/disc.iso"
  xorrisofs -r -J -joliet-long -V "$(date +%F)" -o "$iso" "$1"
  xorriso -as cdrecord -v dev="$dev" blank=as_needed -eject "$iso"
  rm -rf "$(dirname "$iso")"
}

burn_audio() {
  local work i=0 f
  work=$(workdir audio)
  while IFS= read -r -d '' f; do
    i=$((i + 1))
    ffmpeg -nostdin -loglevel error -i "$f" -ar 44100 -ac 2 -sample_fmt s16 "$work/$(printf %02d "$i").wav"
  done < <(find "$1" -maxdepth 1 -type f -print0 | sort -z)
  if [ "$(prop ID_CDROM_MEDIA_STATE)" != blank ]; then
    wodim -v dev="$dev" blank=fast
  fi
  wodim -v -dao -audio -pad -eject dev="$dev" "$work"/*.wav
  rm -rf "$work"
}

burn_video() {
  local work i=0 f
  work=$(workdir video)
  while IFS= read -r -d '' f; do
    i=$((i + 1))
    ffmpeg -nostdin -loglevel error -i "$f" -target pal-dvd -aspect 16:9 "$work/$(printf %02d "$i").mpg"
  done < <(find "$1" -maxdepth 1 -type f -print0 | sort -z)
  VIDEO_FORMAT=PAL dvdauthor -o "$work/dvd" -t "$work"/*.mpg
  VIDEO_FORMAT=PAL dvdauthor -o "$work/dvd" -T
  xorrisofs -dvd-video -V DVD -o "$work/disc.iso" "$work/dvd"
  xorriso -as cdrecord -v dev="$dev" blank=as_needed -eject "$work/disc.iso"
  rm -rf "$work"
}

burn() {
  local mode=${1:-} src=${2:-$BURN_ROOT/${1:-}} archive
  case $mode in
    data | audio | video) ;;
    *) usage >&2; exit 1 ;;
  esac
  [ -n "$(ls -A "$src" 2>/dev/null)" ] || die "Нечего записывать: $src пуст"
  [ "$(prop ID_CDROM_MEDIA)" = 1 ] || die "В приводе нет диска"
  notify "Запись ($mode) из $src началась"
  "burn_$mode" "$src"
  if [ "$src" = "$BURN_ROOT/$mode" ]; then
    archive="$BURN_ROOT/done/$(date +%F-%H%M)-$mode"
    mkdir -p "$archive"
    mv "$src"/* "$archive"/
    chown -R opencloud:opencloud "$BURN_ROOT/done"
  fi
  notify "Запись ($mode) готова"
}

auto() {
  local pending
  if [ -d "$BURN_ROOT" ]; then
    for mode in data audio video; do
      if [ ! -d "$BURN_ROOT/$mode" ]; then
        mkdir "$BURN_ROOT/$mode"
        chown opencloud:opencloud "$BURN_ROOT/$mode"
      fi
    done
  fi
  case $(kind) in
    none) exit 0 ;;
    blank)
      pending=$(for mode in data audio video; do
        if [ -n "$(ls -A "$BURN_ROOT/$mode" 2>/dev/null)" ]; then echo "$mode"; fi
      done)
      case $(grep -c . <<<"$pending" || true) in
        0) notify "Вставлен пустой диск, а папки Burn пусты" ;;
        1) burn "$pending" ;;
        *) notify "Вставлен пустой диск, но непусто несколько папок Burn ($(echo "$pending" | xargs)); запусти disc burn <режим>" ;;
      esac
      ;;
    *) rip ;;
  esac
}

cmd=${1:-}
[ $# -gt 0 ] && shift
case $cmd in
  auto)
    dev=${1:-/dev/sr0}
    trap 'notify "Ошибка, см. journalctl -u disc@${dev#/dev/}"' ERR
    auto
    ;;
  rip)
    dev=${1:-/dev/sr0}
    rip
    ;;
  burn)
    dev=/dev/sr0
    burn "$@"
    ;;
  status)
    dev=${1:-/dev/sr0}
    kind
    ;;
  *) usage ;;
esac
