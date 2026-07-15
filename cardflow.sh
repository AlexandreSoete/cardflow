#!/bin/bash
# =============================================================================
# cardflow.sh — Automatically copies photos/videos from an SD card to a local
# folder, organized by date. Files are removed from the card ONLY after each
# copy has been verified byte-for-byte (cmp). Optional voice announcements,
# system sounds and ntfy push notifications.
#
# The destination folder can be an Immich "external library" path, so photos
# show up in Immich automatically without any API call or key. See README.md.
#
# Configuration lives in config.sh (copy it from config.example.sh). Override
# the config path with the CARDFLOW_CONFIG environment variable.
# =============================================================================

# ------------------------------ LOAD CONFIG ----------------------------------

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="${CARDFLOW_CONFIG:-$SCRIPT_DIR/config.sh}"

# ---- Defaults (any of these may be overridden in config.sh) ----
VOLUME_NAME=""                       # Required: SD card volume name as shown in /Volumes
DEST_DIR="$HOME/Pictures/CardFlow"   # Where photos are copied, one subfolder per day
LOG_FILE="$HOME/Library/Logs/cardflow.log"
LOCK_FILE="/tmp/cardflow.lock"

# File types to import (case-insensitive)
FILE_EXTENSIONS=("jpg" "jpeg" "nef" "cr2" "cr3" "arw" "raf" "dng" "mov" "mp4")

DELETE_AFTER_COPY=true   # Delete from the card AFTER a successful byte-for-byte cmp
EJECT_AFTER=true         # Eject the card when done

SPEAK_ENABLED=true       # Voice announcements via `say`
SPEAK_VOICE="Samantha"   # `say` voice name (see: say -v '?')
SPEAK_VOLUME=20          # Output volume (0-100) during announcements; restored after
SOUNDS_ENABLED=true      # Play macOS system sounds on success/failure

NTFY_ENABLED=false       # Push notifications via ntfy (https://ntfy.sh)
NTFY_TOPIC=""            # Your ntfy topic (anyone who knows it can read your alerts)
NTFY_SERVER="https://ntfy.sh"

if [ -f "$CONFIG_FILE" ]; then
    # shellcheck source=/dev/null
    source "$CONFIG_FILE"
else
    echo "No config file found at: $CONFIG_FILE" >&2
    echo "Copy config.example.sh to config.sh and edit it first." >&2
    exit 1
fi

if [ -z "$VOLUME_NAME" ]; then
    echo "VOLUME_NAME is not set in $CONFIG_FILE." >&2
    exit 1
fi

# ------------------------------ FUNCTIONS ------------------------------------

log() { echo "$(date '+%Y-%m-%d %H:%M:%S') $1" >> "$LOG_FILE"; }

# Build the reusable find predicate for the configured extensions.
find_media() {
    local args=()
    local ext
    for ext in "${FILE_EXTENSIONS[@]}"; do
        args+=(-o -iname "*.$ext")
    done
    # Drop the leading -o
    find "$DCIM" -type f \( "${args[@]:1}" \) "$@"
}

# Resolve the Nth destination candidate for a filename, so we never overwrite a
# different file that already occupies the base name:
#   index 0 -> name.ext,  1 -> name-1.ext,  2 -> name-2.ext, ...
candidate_path() {
    local dir="$1" name="$2" i="$3"
    if [ "$i" -eq 0 ]; then
        printf '%s/%s' "$dir" "$name"
        return
    fi
    local stem="$name" ext=""
    if [[ "$name" == ?*.* ]]; then
        stem="${name%.*}"
        ext=".${name##*.}"
    fi
    printf '%s/%s-%s%s' "$dir" "$stem" "$i" "$ext"
}

speak() {
    [ "$SPEAK_ENABLED" = true ] || return 0
    # Lower the volume to SPEAK_VOLUME, speak, then restore the previous volume.
    # Runs in the background so it never slows down the copy.
    (
        PREV_VOL=$(osascript -e 'output volume of (get volume settings)' 2>/dev/null)
        osascript -e "set volume output volume $SPEAK_VOLUME" 2>/dev/null
        say -v "$SPEAK_VOICE" "$1" 2>/dev/null
        [ -n "$PREV_VOL" ] && osascript -e "set volume output volume $PREV_VOL" 2>/dev/null
    ) &
}

play_sound() {
    [ "$SOUNDS_ENABLED" = true ] || return 0
    afplay "$1" 2>/dev/null
}

notify() {
    # $1 = title, $2 = message, $3 = tags, $4 = priority (optional)
    [ "$NTFY_ENABLED" = true ] || return 0
    [ -n "$NTFY_TOPIC" ] || return 0
    curl -s --max-time 10 \
        -H "Title: $1" \
        -H "Tags: $3" \
        -H "Priority: ${4:-default}" \
        -d "$2" \
        "$NTFY_SERVER/$NTFY_TOPIC" > /dev/null 2>&1
}

fail() {
    log "ERROR: $1"
    play_sound /System/Library/Sounds/Basso.aiff
    speak "Error while copying the SD card"
    notify "SD import FAILED 🚨" "$1" "rotating_light" "high"
    wait
    exit 1
}

# ------------------------------- GUARDS --------------------------------------

VOLUME_PATH="/Volumes/$VOLUME_NAME"
[ -d "$VOLUME_PATH" ] || exit 0

if [ -f "$LOCK_FILE" ]; then exit 0; fi
touch "$LOCK_FILE"
trap 'rm -f "$LOCK_FILE"' EXIT

DCIM="$VOLUME_PATH/DCIM"
[ -d "$DCIM" ] || fail "No DCIM folder on the card."

mkdir -p "$DEST_DIR" || fail "Cannot create destination folder: $DEST_DIR"

log "=== Card detected, copying to $DEST_DIR ==="
START_TIME=$(date +%s)

# Total number of files to process
TOTAL=$(find_media | wc -l | tr -d ' ')
if [ "$TOTAL" -eq 0 ]; then
    log "Card is empty, nothing to copy."
    play_sound /System/Library/Sounds/Pop.aiff
    [ "$EJECT_AFTER" = true ] && diskutil eject "$VOLUME_PATH" >> "$LOG_FILE" 2>&1
    exit 0
fi

speak "Starting SD card copy"
echo "Total: $TOTAL files"

# ------------------------- PHASE 1: COPY -------------------------------------

COPIED=0
SKIPPED=0

while IFS= read -r -d '' f; do
    day=$(stat -f "%Sm" -t "%Y-%m-%d" "$f")
    dir="$DEST_DIR/$day"
    mkdir -p "$dir" || fail "Cannot create $dir (disk full?) — card left intact."
    name=$(basename "$f")

    # Pick a destination: if a candidate already holds a byte-identical file it
    # was already imported (skip); otherwise advance to the next name-N.ext slot
    # so a name collision never overwrites a different file.
    i=0
    while :; do
        dest=$(candidate_path "$dir" "$name" "$i")
        if [ ! -e "$dest" ]; then
            cp -p "$f" "$dest" || fail "Copy failed: $f — card left intact."
            COPIED=$((COPIED+1))
            break
        elif cmp -s "$f" "$dest"; then
            SKIPPED=$((SKIPPED+1))
            break
        fi
        i=$((i+1))
    done

    PCT=$(( (COPIED + SKIPPED) * 100 / TOTAL ))
    printf "\rCopy   : %3d%% (%d copied, %d skipped)" "$PCT" "$COPIED" "$SKIPPED"
done < <(find_media -print0)
echo ""

# ---------------- PHASE 2: VERIFY + DELETE -----------------------------------
# Every file on the card is compared byte-for-byte (cmp) with its copy.
# Identical  -> deleted from the card (when DELETE_AFTER_COPY=true).
# Different/missing -> kept on the card + logged as a mismatch.

VERIFIED=0
DELETED=0
MISMATCH=0

while IFS= read -r -d '' f; do
    day=$(stat -f "%Sm" -t "%Y-%m-%d" "$f")
    dir="$DEST_DIR/$day"
    name=$(basename "$f")

    # Walk the same candidate sequence and match this card file to the copy
    # that is byte-for-byte identical. Slots are filled contiguously, so the
    # first missing candidate means there is no matching copy -> keep on card.
    match=""
    i=0
    while :; do
        dest=$(candidate_path "$dir" "$name" "$i")
        [ -e "$dest" ] || break
        if cmp -s "$f" "$dest"; then
            match="$dest"
            break
        fi
        i=$((i+1))
    done

    if [ -n "$match" ]; then
        VERIFIED=$((VERIFIED+1))
        if [ "$DELETE_AFTER_COPY" = true ]; then
            rm "$f" && DELETED=$((DELETED+1))
        fi
    else
        MISMATCH=$((MISMATCH+1))
        log "VERIFICATION FAILED (kept on card): $f"
    fi

    PCT=$(( (VERIFIED + MISMATCH) * 100 / TOTAL ))
    printf "\rVerify : %3d%% (%d ok, %d failed)" "$PCT" "$VERIFIED" "$MISMATCH"
done < <(find_media -print0)
echo ""

DURATION=$(( $(date +%s) - START_TIME ))
DURATION_STR="$(( DURATION / 60 ))m$(( DURATION % 60 ))s"

# ------------------------------- SUMMARY -------------------------------------

if [ "$MISMATCH" -gt 0 ]; then
    log "Finished with errors: $VERIFIED verified, $MISMATCH failed, $DELETED deleted from card."
    play_sound /System/Library/Sounds/Basso.aiff
    speak "Warning. $MISMATCH files could not be verified and were left on the card"
    notify "SD import: partial verification ⚠️" \
        "$VERIFIED/$TOTAL files verified and copied in $DURATION_STR. $MISMATCH files NOT verified, kept on the card (see the log)." \
        "warning" "high"
    wait
    exit 1
fi

if [ "$EJECT_AFTER" = true ]; then
    sync
    diskutil eject "$VOLUME_PATH" >> "$LOG_FILE" 2>&1
fi

log "Finished: $COPIED copied, $SKIPPED already present, $VERIFIED verified, $DELETED deleted from card, in $DURATION_STR."

CARD_MSG="Card emptied."
[ "$DELETE_AFTER_COPY" = false ] && CARD_MSG="Card left unchanged."

play_sound /System/Library/Sounds/Glass.aiff
speak "Copy complete. $COPIED photos copied and verified"
notify "SD import complete ✅" \
    "$COPIED copied, $SKIPPED already present, $VERIFIED verified in $DURATION_STR. $CARD_MSG You can remove the card." \
    "white_check_mark,camera"

wait
exit 0
