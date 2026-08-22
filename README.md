# CineLight-Pi

Professional terminal-based media centre for Raspberry Pi 4, built around VLC.  
Provides CEC remote control, universal playback tracking, a TUI file manager, and a SQLite-backed series management system.  
Runs on Linux (Raspberry Pi) and macOS (development).

---

## How It Works

You launch `video-menu.sh` in a terminal. A file browser appears — navigate your home folder with the arrow keys, open directories, and select a video file to play. VLC starts in fullscreen automatically.

**While watching:**

- Your playback position is saved every 60 seconds in the background. If you stop mid-episode and come back later, the player picks up exactly where you left off.
- In the file browser, every file shows a status icon next to its name:
  - `[ ]` — not started
  - `[T]` — partially watched
  - `[X]` — finished

**Series (TV shows):**

- The system detects series episodes automatically by the `S01E05` pattern in the filename.
- Open the **Settings** screen for any series folder to configure three options:
  - **Auto continue** — after an episode ends, the next one starts automatically.
  - **Skip intro** — the opening credits are skipped without any action from you.
  - **Skip outro** — playback pauses just as the closing credits begin, and the episode is marked as watched.
- Intro and outro time markers are set directly from the remote: press the **Red** button at the moment credits begin and end. The system records the timestamps and applies them to every episode in the series.

**Remote control (via HDMI CEC):**

You use the TV remote. The standard arrow buttons seek forward/backward, OK plays/pauses, Back exits to the menu. Colour buttons control subtitles, volume, and marker recording. Number buttons jump to any 10 % point in the video.

**No configuration files needed.** Everything — playback positions, series settings, intro/outro markers — is stored in a single local SQLite database (`vlc_media.db`), created automatically on first run.

---

## Setting Intro / Outro Markers Without a Remote (macOS)

On macOS without a TV remote there are two ways to record markers.

### Option 1 — Settings dialog (no terminal knowledge required)

1. Open the file browser (`./video-menu.sh`).
2. Navigate to the folder with the series.
3. Press the **Settings** button (the extra button at the bottom of the `dialog` window).
4. Press the **Edit time** button — a full-screen time editor opens.
5. Enter the values in `MM:SS` format:
   - **Intro Start** — moment the opening credits begin
   - **Intro End** — moment the opening credits end
   - **Credits Duration** — how many seconds of closing credits to skip (count back from the end)
6. Press Enter to save. Done — markers are applied to all episodes of the series.

### Option 2 — CLI via `vlc_db.py` (precise, scriptable)

First, find out the `series_prefix` and `series_suffix` for your series.  
They are derived from the filename. For example:

```
Severance.S01E01.2160p.mkv
  → series_prefix:  Severance.S01
  → series_suffix:  2160p.mkv
```

Then run the commands directly in the terminal:

```bash
# Set intro markers (start and end in seconds)
python3 vlc_db.py set-intro "Severance.S01" "2160p.mkv" 30 90

# Set credits duration (seconds from end of episode)
python3 vlc_db.py set-credits-duration "Severance.S01" "2160p.mkv" 120

# Check what was saved
python3 vlc_db.py get-skip-markers "Severance.S01" "2160p.mkv"

# Clear markers if you need to redo them
python3 vlc_db.py clear-skip "Severance.S01" "2160p.mkv" all
```

After recording the markers, go into **Settings** in the file browser and enable **Skip intro** and/or **Skip outro**.

---

## Overview

| Feature | Details |
|---|---|
| Player | VLC via RC interface (localhost:4212) |
| UI | `dialog`-based TUI file browser |
| Remote | HDMI CEC via `cec-client` |
| Storage | SQLite + Python backend |
| Series | Auto-detect S##E## pattern, skip intro/outro |
| Platform | Raspberry Pi 4 / macOS (cross-platform wrapper included) |

---

## File Structure

### Root scripts (production)

| File | Role |
|---|---|
| `video-menu.sh` | Entry point — TUI file browser and launcher |
| `vlc-cec.sh` | VLC player wrapper with CEC remote support |
| `cvlc.sh` | Cross-platform VLC launcher (macOS / Linux) |
| `playback-tracker.sh` | Library: saves playback position every 60 s |
| `db-manager.sh` | Shell DB layer — delegates all SQL to `vlc_db.py` |
| `vlc_db.py` | Python 3 SQLite backend with connection pool |
| `serials.sh` | Series settings UI (dialog checklist + time editor) |
| `edit-time-tput.sh` | Full-screen tput time editor for intro/outro markers |
| `platform-utils.sh` | macOS / Linux compatibility helpers |
| `vlc_media.db` | SQLite database (auto-created on first run) |

### Directories

| Directory | Contents |
|---|---|
| `DOCS/` | Project documentation and session instructions |
| `Log/` | Runtime log files |
| `Py/` | Python-based menu prototypes and experiments |
| `RELIS/` | Self-contained release copy of all scripts |
| `Test/` | Test and debug scripts |
| `Pic/` | Screenshots / assets |

---

## Requirements

| Dependency | Minimum | Notes |
|---|---|---|
| Bash | 4.0 | macOS ships 3.x — `brew install bash` |
| Python 3 | 3.7 | Used by `vlc_db.py` |
| VLC | any | `brew install --cask vlc` / `apt install vlc` |
| dialog | any | `apt install dialog` |
| netcat (`nc`) | any | VLC RC interface communication |
| cec-client | any | Only for CEC-capable devices |

---

## Quick Start

```bash
# 1. Clone or copy the project
cd /path/to/VLC_TUI_Light_

# 2. Launch the TUI file browser
./video-menu.sh
```

Navigate folders with arrow keys, press Enter to play, Esc to exit.  
The database is created automatically on first run.

---

## Architecture

```
video-menu.sh
    |
    +-- playback-tracker.sh   (cache, save/load position)
    |       +-- db-manager.sh
    |               +-- vlc_db.py   (SQLite: playback + series_settings)
    |
    +-- serials.sh            (series settings dialog)
    |       +-- db-manager.sh
    |       +-- edit-time-tput.sh
    |
    +-- platform-utils.sh     (OS detection, sort compatibility)
    |
    +-- vlc-cec.sh            (launched per video)
            +-- cvlc.sh
            +-- playback-tracker.sh
            +-- db-manager.sh
```

---

## Database Schema

`vlc_media.db` is auto-created and auto-migrated on library load.

### `playback` table

| Column | Type | Description |
|---|---|---|
| `filename` | TEXT PK | Basename of the video file |
| `position` | INTEGER | Last position in seconds |
| `duration` | INTEGER | Total duration in seconds |
| `percent` | INTEGER | Playback percentage (0–100) |
| `status` | TEXT | `watched` / `partial` / `sleep` / NULL |
| `series_prefix` | TEXT | E.g. `ShowName.S01` |
| `series_suffix` | TEXT | E.g. `HDR.2160p.mkv` |
| `outro_triggered` | INTEGER | 1 if outro pause already fired |

### `series_settings` table

| Column | Type | Description |
|---|---|---|
| `series_prefix` | TEXT PK | Show + season identifier |
| `series_suffix` | TEXT PK | Quality/format tag |
| `autoplay` | BOOLEAN | Auto-play next episode |
| `skip_intro` | BOOLEAN | Auto-seek past opening credits |
| `skip_outro` | BOOLEAN | Pause at end credits |
| `intro_start` | INTEGER | Intro start (seconds) |
| `intro_end` | INTEGER | Intro end (seconds) |
| `credits_duration` | INTEGER | Duration of end credits (seconds) |

---

## Status Icons

| Icon | Meaning |
|---|---|
| `[ ]` | Not started |
| `[T]` | Partially watched (>= 1 %) |
| `[X]` | Watched (>= 90 % or outro triggered) |
| `[S]` | Sleep (reserved) |

---

## CEC Remote Control

| Button | CEC code | Action |
|---|---|---|
| OK | `44:00` | Play / Pause |
| Up | `44:01` | +30 seconds |
| Down | `44:02` | -30 seconds |
| Right | `44:04` | +10 seconds |
| Left | `44:03` | -10 seconds |
| Ch Up | `44:30` | +60 seconds |
| Ch Down | `44:31` | -60 seconds |
| Back | `44:0d` | Exit to menu |
| Info | `44:35` | Show time / remaining |
| 0 | `44:20` | Jump to start |
| 1–9 | `44:21`–`44:29` | Jump to 10 %–90 % |
| Red | `44:72` | Set intro / credits marker |
| Green | `44:73` | Cycle subtitle tracks |
| Yellow | `44:74` | Volume up |
| Blue | `44:71` | Volume down |

Set your CEC device node in `vlc-cec.sh`:

```bash
CEC_DEVICE="/dev/cec1"   # adjust to /dev/cec0, etc.
```

---

## Skip Intro / Skip Outro

### Recording markers with the RED button

1. Play any episode of a series.
2. At the start of the opening credits — press **Red** (`Intro Start` saved).
3. At the end of the opening credits — press **Red** again (`Intro End` saved).
4. When closing credits begin — press **Red** (`Credits Duration` calculated and saved).

A 5-second reaction-delay correction is applied automatically.  
Markers are stored per `series_prefix + series_suffix` and apply to all episodes.

### Enabling auto-skip

Press the **Settings** button in the file browser, then check:

- **Skip intro** — auto-seek past the opening.
- **Skip outro** — pause at credits and mark the episode `[X]`.

### Manual marker editing

In Settings → **Edit time**: opens the full-screen `tput` editor.  
Enter values in `MM:SS` format for Intro Start, Intro End, Credits Duration.

---

## Series Detection

Files are recognised as series episodes when the name contains `S##E##`  
(any separator: `.` `-` `_` space, or none).

```
ShowName.S01E05.mkv         # recognised
Show Name S02.E12 HDR.mkv   # recognised
show_name_s03e01_720p.mp4   # recognised
movie_2024.mkv              # NOT a series
```

`series_prefix` = everything up to and including `S##`  
`series_suffix` = everything after `E##`  
Settings are shared across all episodes with the same prefix/suffix pair.

---

## Platform Notes

### macOS

`cvlc.sh` replaces `--intf rc` with `--extraintf rc` so the VLC GUI window is not suppressed.

### Raspberry Pi / Linux

`cvlc.sh` passes `-I dummy` to VLC, matching the behaviour of the original `cvlc` binary.

`platform-utils.sh` abstracts differences in `sort`, `stat`, `date`, and `find` between BSD (macOS) and GNU (Linux) toolchains.

---

## Database CLI Reference

```bash
# Initialise (called automatically on library load)
python3 vlc_db.py init

# Save playback position
python3 vlc_db.py save_playback "video.mkv" 120 3600 3

# Get playback percent
python3 vlc_db.py get_percent "video.mkv"

# Get batch status for menu
python3 vlc_db.py get_batch_status "/path/to/dir" "ep1.mkv" "ep2.mkv"

# Save series settings
python3 vlc_db.py save_settings "Show.S01" "1080p.mkv" 1 1 0 60 90 120

# Get series settings
python3 vlc_db.py get_settings "Show.S01" "1080p.mkv"
```

---

## Logging

| File | Content | Default |
|---|---|---|
| `Log/vlc-cec_YYMMDDHHММ.log` | VLC RC commands | Off (uncomment in `vlc-cec.sh`) |
| `Log/serials.log` | Series settings events | On (rotates at 1 MB) |
| `Log/video-menu-timing.log` | Menu render timing | Off (`ENABLE_TIMING_LOG=1`) |

---

## Version Reference

| Component | Version |
|---|---|
| `vlc-cec.sh` | 0.8.0 |
| `video-menu.sh` | 0.8.0 |
| `serials.sh` | 0.3.0 |
| `playback-tracker.sh` | 0.4.0 |
| `db-manager.sh` | 0.3.0 |
| `platform-utils.sh` | 1.0.0 |
| `vlc_db.py` | root (with connection pool) |

---

## License

See [LICENSE](LICENSE).
