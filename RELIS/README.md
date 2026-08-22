# VLC TUI — RELIS Edition

> **RELIS** is a self-contained variant of the VLC TUI project intended for use with TV series libraries.  
> All scripts are copies of the root-level scripts, adapted and fixed for series-specific workflows.  
> The folder is fully standalone: copy it anywhere and it will work independently.

---

## Overview

RELIS provides a terminal-based media centre built around VLC.  
It adds series-aware playback tracking, automatic intro/outro skipping, and CEC remote control — all driven by a local SQLite database.

---

## File Structure

| File | Role |
|---|---|
| `video-menu_RELIS.sh` | Entry point — TUI file browser and launcher |
| `vlc-cec_RELIS.sh` | VLC player wrapper with CEC remote support |
| `cvlc_RELIS.sh` | Cross-platform VLC launcher (macOS / Linux) |
| `playback-tracker_RELIS.sh` | Background library: saves playback position every 60 s |
| `db-manager_RELIS.sh` | Shell DB layer — delegates all SQL to `vlc_db_RELIS.py` |
| `vlc_db_RELIS.py` | Python 3 SQLite backend, SQL-injection-safe |
| `serials_RELIS.sh` | Series settings UI (dialog checklist + time editor) |
| `series-tracker_RELIS.sh` | Legacy file-based tracker (kept for reference) |
| `edit-time-tput_RELIS.sh` | Full-screen tput time editor for intro/outro markers |

---

## Requirements

| Dependency | Minimum version | Notes |
|---|---|---|
| Bash | 4.0 | macOS ships 3.x — install via `brew install bash` |
| Python 3 | 3.7 | Used by `vlc_db_RELIS.py` |
| VLC | any | `brew install --cask vlc` / `apt install vlc` |
| dialog | any | `apt install dialog` |
| netcat (`nc`) | any | Used to communicate with VLC RC interface |
| cec-client | any | Only required if using a CEC-capable device |

---

## Quick Start

```bash
# 1. Go to the RELIS directory
cd /path/to/RELIS

# 2. Launch the TUI menu (starts in $HOME)
./video-menu_RELIS.sh
```

The menu opens in the terminal. Navigate folders with the arrow keys, select a video with Enter, press **Cancel** (Esc) to exit.

---

## Architecture

```
video-menu_RELIS.sh
    |
    +-- playback-tracker_RELIS.sh   (batch status cache, save/load progress)
    |       +-- db-manager_RELIS.sh
    |               +-- vlc_db_RELIS.py   (SQLite: playback + series_settings)
    |
    +-- serials_RELIS.sh            (series settings dialog)
    |       +-- db-manager_RELIS.sh
    |       +-- edit-time-tput_RELIS.sh
    |
    +-- vlc-cec_RELIS.sh            (launched for each video)
            +-- cvlc_RELIS.sh
            +-- playback-tracker_RELIS.sh
            +-- db-manager_RELIS.sh
```

---

## Database Schema

The SQLite database (`vlc_media.db`) is auto-created on first run.

### `playback` table

| Column | Type | Description |
|---|---|---|
| `filename` | TEXT PK | Basename of the video file |
| `position` | INTEGER | Last position in seconds |
| `duration` | INTEGER | Total video duration in seconds |
| `percent` | INTEGER | Playback percentage (0–100) |
| `status` | TEXT | `watched` / `partial` / `sleep` / NULL |
| `series_prefix` | TEXT | E.g. `ShowName.S01` |
| `series_suffix` | TEXT | E.g. `HDR.2160p.mkv` |
| `outro_triggered` | INTEGER | 1 if the outro pause was already fired |

### `series_settings` table

| Column | Type | Description |
|---|---|---|
| `series_prefix` | TEXT PK | Show + season identifier |
| `series_suffix` | TEXT PK | Quality/format tag |
| `autoplay` | BOOLEAN | Auto-play next episode |
| `skip_intro` | BOOLEAN | Auto-skip opening credits |
| `skip_outro` | BOOLEAN | Pause at end credits |
| `intro_start` | INTEGER | Intro start position (seconds) |
| `intro_end` | INTEGER | Intro end position (seconds) |
| `credits_duration` | INTEGER | Duration of end credits (seconds) |

---

## Status Icons in the Menu

| Icon | Meaning |
|---|---|
| `[ ]` | Not started |
| `[T]` | Partially watched (>= 1 %) |
| `[X]` | Watched (>= 90 % or outro triggered) |
| `[S]` | Sleep (reserved) |

---

## CEC Remote Control

The table below maps physical remote buttons (HDMI CEC codes) to player actions.

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
| Info | `44:35` | Show current / remaining time |
| 0 | `44:20` | Jump to start |
| 1–9 | `44:21`–`44:29` | Jump to 10 %–90 % |
| Red | `44:72` | Set intro / outro marker at current position |
| Green | `44:73` | Cycle subtitle tracks (including off) |
| Yellow | `44:74` | Volume up |
| Blue | `44:71` | Volume down |

### Setting `CEC_DEVICE`

Edit `vlc-cec_RELIS.sh` and change the line:

```bash
CEC_DEVICE="/dev/cec1"
```

to match the device node on your system (`/dev/cec0`, etc.).

---

## Skip Intro / Skip Outro

### How to record markers (RED button)

1. Start playback of any episode.
2. When the opening credits **begin**, press **Red** — marker `Intro Start` is saved.
3. When the opening credits **end**, press **Red** again — marker `Intro End` is saved.
4. Near the end of the episode, when the closing credits begin, press **Red** — `Credits Duration` is calculated and saved.

The script applies a 5-second reaction-delay correction automatically.  
Markers are stored in `series_settings` and apply to all episodes of the same series/quality combination.

### Enabling auto-skip

Open the **Settings** screen inside the file browser (the extra button in the dialog), then check:

- **Skip intro** — automatically seek past the opening.
- **Skip outro** — automatically pause when closing credits begin and mark the episode as `[X]`.

### Fine-tuning markers manually

Press the **Settings** button, then **Edit time** to open the full-screen tput editor.  
Enter values in `MM:SS` format for Intro Start, Intro End, and Credits Duration.

---

## Series Detection

A file is recognised as a series episode if its name contains the pattern `S##E##`  
(any separator: `.`, `-`, `_`, space, or none).

Examples that are recognised:

```
ShowName.S01E05.mkv
Show Name S02.E12 HDR.mkv
show_name_s03e01_720p.mp4
```

The `series_prefix` is everything up to and including `S##`, and the `series_suffix` is everything after `E##`.  
Settings are shared across all episodes with the same prefix/suffix pair.

---

## Platform Notes

### macOS

`cvlc_RELIS.sh` detects macOS and replaces `--intf rc` with `--extraintf rc`  
so the GUI window is not suppressed.

### Raspberry Pi / Linux

`cvlc_RELIS.sh` passes `-I dummy` to VLC (same as the original `cvlc` command).

---

## Logging

| Log file | Content |
|---|---|
| `Log/vlc-cec_YYMMDDHHММ.log` | VLC RC command log (disabled by default, uncomment lines in `vlc-cec_RELIS.sh`) |
| `Log/serials.log` | Series settings save/load events (auto-rotated at 1 MB) |
| `Log/video-menu-timing.log` | Menu render timing (disabled by default, set `ENABLE_TIMING_LOG=1`) |

---

## Version Reference

| Component | Version |
|---|---|
| `vlc-cec_RELIS.sh` | 0.8.0 |
| `video-menu_RELIS.sh` | 0.8.0 |
| `serials_RELIS.sh` | 0.3.0 |
| `playback-tracker_RELIS.sh` | 0.4.0 |
| `db-manager_RELIS.sh` | 0.2.0 |
| `vlc_db_RELIS.py` | 1.2.0 |
