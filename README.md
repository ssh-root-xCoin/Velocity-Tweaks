# Velocity

A Windows performance toolkit that respects your system.

Velocity is the opposite of a paid "FPS unlocker." It does not disable Windows
Update, it does not turn off your antivirus, and it does not delete your page
file. It applies the tuning that actually moves frame rates and input latency,
it tells you the truth about what each change does, and **every tweak can be
undone** with the same switch that turned it on.

Built for Windows 10 and 11. No installer, no account, no telemetry.

---

## Why it exists

Most "tweaking utilities" sold in Discord servers do three bad things:

1. **Ship placebo.** Clearing Prefetch, "RAM cleaners", disabling TCP
   auto-tuning — these do nothing useful or actively slow you down.
2. **Open security holes.** Killing SmartScreen, Defender loggers and Windows
   Update is not a performance gain. It is a liability you paid for.
3. **Hide what they changed.** No revert, no state, no explanation.

Velocity fixes all three. It curates the changes that have a measurable effect,
refuses the snake oil, and shows you the current state of every setting before
you touch it.

---

## What's inside

**Dashboard** — reads your real hardware, drivers, displays and recent crash
history, then flags concrete issues (old BIOS on a CPU that needs a microcode
fix, devices missing drivers, a second display that can cause black-outs).

**Performance** — Hardware-Accelerated GPU Scheduling, disable Game DVR
background recording, foreground priority boost, disable CPU power throttling,
multimedia scheduler priority for games, disable Fast Startup (cures many
boot-time black screens), disable Multi-Plane Overlay/MPO (the standard fix for
multi-monitor flicker and random black-outs), and the hidden Ultimate
Performance power plan.

**Latency & Input** — disable mouse acceleration, instant menu response, remove
the startup app delay.

**Network** — disable network throttling, optionally disable Nagle's algorithm
on your active adapters.

**Privacy & Telemetry** — minimize diagnostic data, disable the advertising ID,
remove suggested content and Start-menu web search. None of this weakens
security.

**Security** — restore SmartScreen and repair Windows time sync, two things the
booster packs love to break.

**Cleanup** — clear temp files (never Prefetch), flush DNS, empty the Recycle
Bin.

**Debloat** — remove ad-ware Store apps. Keeps media, Xbox and Game Bar so your
games and captures still work. Everything removed is reinstallable.

**System & Repair** — create a restore point, run SFC and DISM, open Device
Manager / Display settings / Startup-apps manager / your GPU's control panel
(NVIDIA, AMD or Intel — auto-detected), launch WinUtil by Chris Titus Tech, and
open the GitHub page for Optimizer (a separate open-source tool — Velocity links
to it transparently rather than bundling it, because some of its options weaken
security in ways Velocity refuses to).

---

## How to use it

1. Double-click **`Velocity.bat`**. Approve the administrator prompt.
2. Start on the **Dashboard** and read the health checks.
3. Click **Create Restore Point** (top right). Always.
4. Flip individual toggles, or click **Apply Recommended** to apply the safe and
   security-restoring set in one pass.
5. Reboot if a tweak is tagged **Reboot**.

To undo anything, flip its switch back off, or use the restore point.

---

## Safety

- Admin is required because tuning touches system registry keys. The launcher
  asks for it explicitly.
- A restore point is one click away and recommended before any batch.
- Caution-tagged items (networking) are never part of the one-click batch.
- Velocity makes no network connections of its own. The only outbound action is
  the optional WinUtil launcher, which runs Chris Titus Tech's published script.

---

## Requirements

- Windows 10 (1909+) or Windows 11
- Windows PowerShell 5.1 (built in)
- Administrator account

---

## Files

| File           | Purpose                                  |
|----------------|------------------------------------------|
| `Velocity.bat` | Launcher (elevates, then starts the GUI) |
| `Velocity.ps1` | The application                     |
| `README.md`    | This file                                |

---

## Disclaimer

System tuning carries inherent risk. Velocity defaults to safe, reversible
changes and provides restore points, but you run it at your own risk. Read each
description before applying.
