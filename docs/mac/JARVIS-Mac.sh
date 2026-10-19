# JARVIS Mac — da incollare nell'azione «Esegui script shell» (Shell: zsh, Passa input: come argomenti)
# Conosce solo questi comandi: tutto il resto viene ignorato.
set -- ${=1}
cmd=$1; shift; arg="$*"

riordina() {
  cd "$1" || return
  mkdir -p Screenshot Immagini Documenti Video Audio Archivi Lotti
  for f in *(N.); do
    case $f in Screenshot*|Istantanea*|Schermata*) mv -n -- "$f" Screenshot/; continue;; esac
    case ${f:e:l} in
      png|jpg|jpeg|heic|gif|webp|tif|tiff) mv -n -- "$f" Immagini/ ;;
      pdf|doc|docx|xls|xlsx|csv|numbers|pages|key|txt|rtf|md) mv -n -- "$f" Documenti/ ;;
      mov|mp4|m4v) mv -n -- "$f" Video/ ;;
      mp3|wav|aif|aiff|m4a|flac) mv -n -- "$f" Audio/ ;;
      zip|rar|7z|dmg) mv -n -- "$f" Archivi/ ;;
    esac
  done
  for d in lotto-*(N/); do mv -n -- "$d" Lotti/; done
  for d in Screenshot Immagini Documenti Video Audio Archivi Lotti; do rmdir "$d" 2>/dev/null; done
}

case $cmd in
  volume)   [[ $arg == <0-100> ]] && osascript -e "set volume output volume $arg" ;;
  muto)     osascript -e "set volume with output muted" ;;
  musica)
    app=Music; pgrep -xq Spotify && app=Spotify
    case $arg in
      play)     osascript -e "tell application \"$app\" to play" ;;
      pausa)    osascript -e "tell application \"$app\" to pause" ;;
      avanti)   osascript -e "tell application \"$app\" to next track" ;;
      indietro) osascript -e "tell application \"$app\" to previous track" ;;
    esac ;;
  apri)     [[ $arg =~ '^[A-Za-z0-9 ._-]+$' ]] && open -a "$arg" ;;
  cartella) [[ $arg =~ '^[A-Za-z0-9 ._-]+$' ]] && open "$HOME/Desktop/$arg" ;;
  scura)    [[ $arg == on ]] && v=true || v=false
            osascript -e "tell application \"System Events\" to tell appearance preferences to set dark mode to $v" ;;
  blocca)   pmset displaysleepnow ;;
  screenshot) screencapture -x "$HOME/Desktop/Screenshot $(date '+%Y-%m-%d %H.%M.%S').png" ;;
  riordina_scrivania) riordina "$HOME/Desktop" ;;
  ordina_download)    riordina "$HOME/Downloads" ;;
  svuota_cestino)     osascript -e 'tell application "Finder" to empty trash' ;;
esac
