# =============================================================================
# config.example.sh — Copy this file to config.sh and edit the values.
#
#   cp config.example.sh config.sh
#
# config.sh is git-ignored so your personal values never get committed.
# Only VOLUME_NAME is strictly required; everything else has a sane default.
# =============================================================================

# --- Card & destination -------------------------------------------------------

# Name of your SD card as it appears in /Volumes (run `ls /Volumes` with the
# card inserted). Example: "NIKON D3200", "EOS_DIGITAL", "UNTITLED".
VOLUME_NAME="MY SD CARD"

# Where photos are copied. One subfolder per capture day (YYYY-MM-DD) is created.
# Tip: point this at an Immich external-library folder so photos appear in Immich
# automatically — no API key needed. See README.md "How Immich fits in".
DEST_DIR="$HOME/Pictures/CardFlow"

# Log file and lock file (defaults are fine for most people).
LOG_FILE="$HOME/Library/Logs/cardflow.log"
LOCK_FILE="/tmp/cardflow.lock"

# File types to import (case-insensitive, no leading dot).
FILE_EXTENSIONS=("jpg" "jpeg" "nef" "cr2" "cr3" "arw" "raf" "dng" "mov" "mp4")

# --- Safety -------------------------------------------------------------------

# Delete files from the card ONLY after each copy passes a byte-for-byte check.
# Set to false to keep the card untouched (copy + verify only).
DELETE_AFTER_COPY=true

# Eject the card automatically when finished.
EJECT_AFTER=true

# --- Voice & sounds (macOS) ---------------------------------------------------

SPEAK_ENABLED=true       # Spoken announcements via macOS `say`
SPEAK_VOICE="Samantha"   # Voice name — list options with: say -v '?'
SPEAK_VOLUME=20          # Volume (0-100) used only during announcements
SOUNDS_ENABLED=true      # Play macOS system sounds on success/failure

# --- Push notifications (optional, off by default) ----------------------------

# ntfy sends a push to your phone/desktop. NOTE: anyone who knows the topic name
# can read your notifications, so pick a long, unguessable topic.
NTFY_ENABLED=false
NTFY_TOPIC="change-me-to-something-random-1a2b3c"
NTFY_SERVER="https://ntfy.sh"
