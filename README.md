<p align="center"><img src="assets/ozzyhn-pfp-512.png" width="160" alt="OZZYHN TWEAKS"></p>

# OPTIMIZACIONES DE OZZYHN

**by OZZYHN TWEAKS** · [github.com/ozzyhntweaks](https://github.com/ozzyhntweaks) · **English / Español**

**A hardware-aware Windows 10 / 11 optimizer with a futuristic neon interface.**
It scans the PC, works out what kind of machine it is, and tunes Windows for *that* machine. That holds whether it is a $150 Celeron laptop that needs reviving or an RTX 4090 rig chasing every frame.

Every switch shows the **real state read from Windows right now**, every change is **logged and reversible**, and the whole thing is one open-source PowerShell file you can read before you run it. The interface switches between **English and Spanish** with one click (EN | ES in the title bar), and starts in Spanish on Spanish Windows.

---

## Launch

Open **PowerShell as Administrator** and paste:

```powershell
irm https://raw.githubusercontent.com/ozzyhntweaks/optimizaciones-de-ozzyhn/main/ozzyhn.ps1 | iex
```

Or download **`Run-Ozzyhn.cmd`** and double-click it (it asks for admin rights by itself).
On older Windows 10 builds, if the download fails, use this longer command:

```powershell
[Net.ServicePointManager]::SecurityProtocol='Tls12'; irm https://raw.githubusercontent.com/ozzyhntweaks/optimizaciones-de-ozzyhn/main/ozzyhn.ps1 | iex
```

**Requirements:** Windows 10 (1809+) or Windows 11, x64 or ARM64, administrator account. Nothing to install: it uses the PowerShell built into Windows.

---

## What it does

| Tab | What you get |
|---|---|
| **Dashboard** | CPU-Z-style spec sheet (CPU, cores and cache, GPU and VRAM, RAM type, speed and channels, drives, board, BIOS, battery wear, VBS/HVCI, Secure Boot, TPM). Live CPU load, real clock speed, RAM, temperature and uptime. **OZ Score** and tier: **CHEAP / BUDGET / MID-RANGE / FANCY**. Smart insights such as an HDD system drive, single-channel RAM, XMP probably off, old GPU driver, too many startup apps, or a hot laptop. |
| **Tweaks** | **129 tweaks in 14 categories**. Each one detects its own state, so the switches show what is actually active. Flip what you want, then apply. Search, filters, *Recommended for this PC* badges and risk labels (Safe, Moderate, Advanced, Danger). |
| **Profiles** | One click, resolved for this PC: **Auto-Tune**, **Revive Cheap PC**, **Max Performance**, **Cool & Quiet**, **Competitive Gaming**, **Privacy Max**, **Clean Windows UI**. *Preview* stages the changes for review; *Apply* does it now. |
| **Debloat** | Lists only the bloat that is actually installed (66 known packages), with recommended ones pre-selected. Core apps (Store, Calculator, Notepad, Terminal, Security) are protected and never shown. Also includes the official Edge uninstall where Microsoft allows it. |
| **Drivers** | Official download links for the detected NVIDIA / AMD / Intel GPU, the chipset, the laptop or board maker and the network adapter. It also lists devices with missing drivers and the age of key drivers, and links to NVCleanstall and DDU for clean GPU installs. |
| **Tools** | Quick clean, DISM component cleanup, DISM + SFC repair, network stack reset, disk scan, DNS switcher (Cloudflare, Google, Quad9, AdGuard), three custom power plans, battery report, CompactOS for tiny eMMC drives, a startup app manager and shortcuts to the classic panels. |
| **Backup & Undo** | Automatic System Restore point, an **undo journal** that records the original value of everything changed, one-click revert per tweak or *Revert everything*, and export or import of your setup. |

### Tweak categories

Privacy & Telemetry (17), AI & Copilot (4), Performance (14), Gaming & Input (9), Power & Thermals (6), Services (12), Network & Latency (7), Explorer & UI (16), Start, Taskbar & Search (14), Edge, OneDrive & Store (7), Windows Update (5), Storage & NTFS (6), Security Hardening (7), Danger Zone (5).

### Fast **and** cool

Three power plans are built to keep idle temperatures low:

* **OZZYHN PERFORMANCE**: aggressive boost and unparked cores under load, but a 5% minimum CPU state so the CPU idles cool. PCIe, USB and disk power saving are off while plugged in.
* **OZZYHN SMART**: efficient-aggressive boost. Close to full speed when you need it, with much less heat and noise the rest of the time. The default for laptops.
* **OZZYHN COOL**: turbo off. The rescue plan for laptops that overheat.

Undervolting and BIOS settings (XMP / EXPO, fan curves) cannot be changed safely from Windows. The app tells you when they are worth doing instead of pretending.

---

## Safety

* A **System Restore point** is created before changes (you can turn this off).
* The **original value of every registry key, service and task is saved** before it is touched, in `C:\ProgramData\Ozzyhn\journal.json`.
* **Danger Zone** settings (Defender real-time, SmartScreen, Memory Integrity, VBS, CPU mitigations) are **never part of any profile** and always ask for confirmation.
* Hardware-specific tweaks hide themselves where they do not apply: laptop-only, desktop-only, Windows 11-only, NVIDIA/AMD-only and VMs.
* No telemetry, no ads, no downloads of other tools. Logs stay in `C:\ProgramData\Ozzyhn\logs`.

> Use at your own risk. This tool changes system settings. Read what a switch does before you flip it.

---

## FAQ

**Will it break Windows Update?** No. Updates are never disabled. There are optional switches to delay feature updates, stop auto-restarts or skip driver updates.

**Can I undo everything?** Yes. Use *Backup & Undo → Revert everything*, or turn individual switches back off. Removed apps can be reinstalled from the Microsoft Store.

**Why is my temperature "N/A"?** Many motherboards hide their sensors from Windows. Use HWiNFO for exact readings. Everything else still works.

**Does it work in Spanish (or any language) Windows?** Yes. All detection is language-independent.

---

## What's new in 1.1

* **Registry tweaks now really apply.** 1.0 had a bug that deleted registry values instead of writing them, so switches showed ON while nothing changed, and some flipped back later. If you used 1.0, open the app and press **RE-APPLY** on the Tweaks page.
* **Honest counts.** Tweaks with nothing to change on your PC (for example a service that is not installed) show **N/A** and are not counted. Anything Windows blocks or later undoes is flagged with the reason and a one-click re-apply.
* **Faster.** The scan and every background task run inside the app instead of starting a new PowerShell each time. The restore point is reused if one was made in the last 24 hours.
* **Smooth scrolling.** The tweak list only draws the rows on screen.
* **English / Español** switch, the new OZ logo, and the GitHub links point to the right page.

---

## Source

Everything is in one file, `ozzyhn.ps1`. The logo and profile picture are in `/assets` (SVG source + PNG).

---

## En español

**Optimizaciones de Ozzyhn** (por **OZZYHN TWEAKS**) analiza tu PC (CPU, GPU, RAM, disco, placa y batería) y detecta si es de escritorio o portátil, si usa Windows 10 u 11 y si es una PC **barata, económica, de gama media o de gama alta**. Luego la optimiza según ese resultado. Cada interruptor muestra el estado real de Windows y todo se puede deshacer. La app está **en español y en inglés**: cambia con el botón **EN | ES** de la barra de título.

Ábrelo en **PowerShell como administrador**:

```powershell
irm https://raw.githubusercontent.com/ozzyhntweaks/optimizaciones-de-ozzyhn/main/ozzyhn.ps1 | iex
```

---

MIT License. Made by **OZZYHN TWEAKS** · [github.com/ozzyhntweaks](https://github.com/ozzyhntweaks)
