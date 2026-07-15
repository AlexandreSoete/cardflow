# cardflow

Automatically copy photos and videos off an SD card the moment you plug it in —
sorted by date, verified byte-for-byte, then safely wiped and ejected. Built for
macOS and a perfect companion to a self-hosted [Immich](https://immich.app)
server.

![cardflow in action](docs/demo.gif)

---

## What it does

1. You insert your SD card.
2. macOS fires a LaunchAgent that runs `cardflow.sh`.
3. Every photo/video is copied to `DEST_DIR/<YYYY-MM-DD>/`, one folder per
   capture day.
4. Each file is re-read from the card and compared **byte-for-byte** (`cmp`)
   against its copy.
5. Only files that pass verification are deleted from the card.
6. The card is ejected, and you get a voice announcement / sound / optional
   push notification.

No cloud service, no API keys, no dependencies beyond what ships with macOS
(`bash`, `cp`, `cmp`, `stat`, `diskutil`, `say`, `afplay`, `curl`).

## How Immich fits in

**cardflow does not talk to Immich directly** — and that's the point. Instead of
uploading through the Immich API, it drops your photos into a plain folder. If
you point `DEST_DIR` at a folder that Immich watches as a
[read-only external library](https://immich.app/docs/guides/external-library),
your imports appear in Immich automatically after its next scan. Nothing to
authenticate, nothing to break.

If you don't use Immich, that's fine too — it's just a fast, safe card importer.

## Requirements

- macOS 13 (Ventura) or newer
- An SD card with a standard `DCIM/` folder (any camera)
- *(Optional)* An Immich server with an external library, if you want photos to
  show up there
- *(Optional)* An [ntfy](https://ntfy.sh) topic for push notifications

## Installation

```bash
git clone https://github.com/AlexandreSoete/cardflow.git
cd cardflow

# 1. Create your config
cp config.example.sh config.sh
#    then edit config.sh — at minimum set VOLUME_NAME

# 2. Make the script executable
chmod +x cardflow.sh

# 3. Install the LaunchAgent so it runs on card insertion
cp com.example.cardflow.plist ~/Library/LaunchAgents/com.$(whoami).cardflow.plist
#    edit that copied file: replace REPLACE_ME with the absolute path to this folder
launchctl load ~/Library/LaunchAgents/com.$(whoami).cardflow.plist
```

To find your card's exact name, insert it and run `ls /Volumes`.

### Try it before automating

Run it once by hand with the card inserted:

```bash
./cardflow.sh
```

Progress prints in the terminal. Once you're happy, the LaunchAgent takes over.

## Configuration

All settings live in `config.sh` (git-ignored). See
[`config.example.sh`](config.example.sh) for the full list. The important ones:

| Setting | Default | Meaning |
| --- | --- | --- |
| `VOLUME_NAME` | *(required)* | Card name as shown in `/Volumes` |
| `DEST_DIR` | `~/Pictures/CardFlow` | Where photos land (point at an Immich library) |
| `FILE_EXTENSIONS` | jpg, nef, cr2, mov… | Which file types to import |
| `DELETE_AFTER_COPY` | `true` | Wipe the card after verification |
| `EJECT_AFTER` | `true` | Eject when done |
| `SPEAK_ENABLED` | `true` | Spoken announcements |
| `NTFY_ENABLED` | `false` | Push notifications via ntfy |

## Safety

Losing photos to a bad import is the one thing this tool is designed to prevent.
Here is exactly how the card is handled:

- **Copy first, delete last, in two separate passes.** Pass 1 copies every file.
  Pass 2 re-reads each file from the card and compares it byte-for-byte (`cmp`)
  against the copy. A file is deleted **only** if that comparison passes.
- **Any mismatch keeps the file.** If a file fails verification (or its copy is
  missing), it is left on the card and logged. The card is **not** ejected and
  the run exits with an error so you notice.
- **Interrupted copy = nothing lost.** Deletion never happens during the copy
  pass. If you yank the card mid-copy or the disk fills up, the script aborts
  before any deletion — the card is left fully intact.
- **You can disable wiping entirely.** Set `DELETE_AFTER_COPY=false` to copy and
  verify without ever touching the card.
- **Immich being down doesn't matter.** Because import is just a file copy, your
  photos are safely on disk regardless of whether Immich is running. Nothing is
  deleted based on Immich's state.

- **Name collisions never overwrite.** If a different file already occupies a
  destination name, the new one is saved as `name-1.ext`, `name-2.ext`, and so
  on. Verification then matches each card file to its own copy by content, so
  the right file is checked before deletion.

Files already imported (byte-for-byte identical at the destination) are skipped
during copy but still verified before any deletion, so re-running is safe.

## Uninstall

```bash
launchctl unload ~/Library/LaunchAgents/com.$(whoami).cardflow.plist
rm ~/Library/LaunchAgents/com.$(whoami).cardflow.plist
```

## License

[MIT](LICENSE)
