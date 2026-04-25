# tmux-timer

[![Shell](https://img.shields.io/badge/shell-bash-4EAA25?logo=gnu-bash&logoColor=white)](https://www.gnu.org/software/bash/)
[![Platform](https://img.shields.io/badge/platform-Linux-FCC624?logo=linux&logoColor=black)](#requirements)
[![License: MIT](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)
[![Requires: tmux](https://img.shields.io/badge/requires-tmux-1BB91F?logo=tmux&logoColor=white)](https://github.com/tmux/tmux)
[![Requires: at](https://img.shields.io/badge/requires-at-555555)](https://manpages.debian.org/stable/at/at.1.en.html)
[![PRs Welcome](https://img.shields.io/badge/PRs-welcome-brightgreen.svg)](#contributing)

> Interactive CLI to schedule any shell command into a running **tmux** session at a future time, powered by **`at`**.

Pick a tmux session, type the command, choose when — done. The command is delivered to that session at the scheduled time as if you typed it yourself.

---

## Why

You want a long-running command to fire later (a backup at 3 AM, a deploy at 14:00, a `git pull` "in 30 minutes") **inside a specific tmux session** so the output stays attached, scrollable, and visible. `cron` and `at` alone don't talk to tmux. `tmux-timer` glues them together with an interactive prompt.

---

## Features

- 🖥️ Lists all active tmux sessions and lets you pick one
- ⏰ Five scheduling modes: today, tomorrow, specific date, weekday, or relative (`now + 30 minutes`)
- 👤 sudo-aware — schedules under the invoking user, not root
- 🔍 Confirmation step shows the parsed execution time before queueing
- 🧹 Self-cleaning temp scripts in `/tmp`
- 📋 Manage queued jobs with standard `atq` / `atrm`

---

## Requirements

| Tool        | Purpose            |
|-------------|--------------------|
| `bash`      | shell              |
| `tmux`      | target sessions    |
| `at` + `atd` | scheduling backend |

`install.sh` will install any missing dependencies for you and enable the `atd` service. Supported package managers: **apt, dnf, yum, pacman, zypper, apk, brew**.

---

## Installation

### One-liner

```bash
git clone https://github.com/hehljo/tmux-timer.git && cd tmux-timer && sudo ./install.sh
```

This will:

1. Detect your package manager and install `at` and `tmux` if missing.
2. Enable and start the `atd` service.
3. Deploy `timer.sh` to `/usr/local/bin/timer`.

### Skip dependency install

If you've already got `at` and `tmux` set up — or want to manage them yourself:

```bash
sudo ./install.sh --no-deps
```

### Manual

```bash
git clone https://github.com/hehljo/tmux-timer.git
cd tmux-timer
sudo install -m 0755 timer.sh /usr/local/bin/timer
```

### Uninstall

```bash
sudo rm /usr/local/bin/timer
```

---

## Usage

```bash
timer
```

You'll be walked through:

1. **Session** — pick from your active tmux sessions
2. **Command** — what to run (e.g. `git pull && npm run build`)
3. **When** — today / tomorrow / `DD.MM.YYYY` / weekday name / relative
4. **Time** — `HH:MM` (skipped in relative mode)
5. **Confirm** — review and queue the job

### Example

```
$ timer
=== TMUX Timer Scheduler ===

Verfügbare tmux Sessions:
[1] dev: 3 windows (created Mon Apr 21 09:14:02 2026)
[2] backup: 1 windows (created Mon Apr 21 10:02:11 2026)

Wähle Session (Nummer): 2
Befehl der ausgeführt werden soll: rsync -av /data/ /backup/

=== Wann soll der Befehl ausgeführt werden? ===
[1] Heute   [2] Morgen   [3] Datum   [4] Wochentag   [5] Relativ
Wähle Option (1-5): 1
Uhrzeit (HH:MM): 03:00

✓ Timer erfolgreich erstellt!
```

---

## Managing scheduled jobs

```bash
atq                  # list pending jobs
atrm <job-number>    # cancel a job
at -c <job-number>   # show what a queued job will run
```

---

## How it works

1. You answer the prompts. The script writes a one-shot helper into `/tmp/tmux_timer.XXXXXX.sh`.
2. The helper is queued via `at` to run at the chosen time.
3. When `at` fires, the helper runs `tmux send-keys` against your chosen session — first the command text, then `Enter` — then deletes itself.

When invoked with `sudo`, the helper is `chown`ed to `$SUDO_USER` and queued under that user, so it sees the right tmux server.

---

## Limitations

- **Linux only.** Requires `at`/`atd`. macOS has `atrun` disabled by default.
- **Interactive only.** Prompts cannot be piped; the script is meant to be driven by a human.
- **Survives only as long as the target tmux session does.** If the session is killed before fire time, the command will fail silently.

---

## Contributing

Issues and PRs welcome. Keep the script POSIX-friendly bash and preserve the German user-facing strings (or add i18n).

---

## License

[MIT](LICENSE)
