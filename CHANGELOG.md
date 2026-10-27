# Changelog

Each release on the [Releases page](https://github.com/ozzyhntweaks/optimizaciones-de-ozzyhn/releases) uses its section below as release notes. To release: add a section for the new version at the top, set `$Oz.Version` in `ozzyhn.ps1` to match, and push to `main`.

## 1.3.0

* **CLEAN UP FILES replaces QUICK CLEAN** (TOOLS page). Nothing is deleted until you choose it:
  1. Tick the drives to look at. Only the Windows drive is ticked at first. Network drives are never listed.
  2. Press **SCAN**. Every item shows its size and the exact folders it would empty, grouped by drive. Scanning only reads; it deletes nothing.
  3. Recommended items that have something to clean come ticked. **SELECT RECOMMENDED** and **SELECT NONE** change them all at once, and the total updates as you tick.
  4. **CLEAN SELECTED** lists what will be deleted and asks first. Afterwards the app scans again, so you see what was freed.
* What can be listed: your temp folder, Windows temp, Windows Update downloads, Delivery Optimization cache, thumbnail cache, crash dumps, error reports, the legacy web cache, servicing logs, and graphics shader caches (DirectX, NVIDIA, AMD, Intel; not ticked by default, since games rebuild them and can stutter on the first launch). All of these are Windows folders on the Windows drive.
* On other drives, only the **Recycle Bin** is offered, never ticked by default, and only for drives you picked. Your own files are never listed anywhere.
* Every folder is checked when it is measured and again right before it is emptied, with the same rules as 1.2.1: Windows drive only, no whole drives, no personal or system folders, no links. Anything left alone is shown under its item with the reason.
* New automatic tests on real Windows: measuring and cleaning around junctions and symbolic links, a scan that must not delete anything, cleaning that refuses a folder turned into a link, and emptying the Windows drive's Recycle Bin while a second drive's Recycle Bin stays as it was. The UI test runs a scan, ticks items in English and Spanish, and answers NO to the confirmation.

## 1.2.1

* **Important fix: QUICK CLEAN could delete files on other drives.** If a folder it cleans held a link (a junction or symbolic link) to a folder on another drive, Windows PowerShell followed the link and deleted the files at the other end. It also trusted the TEMP setting even when it pointed at another drive, and it emptied the Recycle Bin of every drive. Now:
  * It only cleans a fixed list of Windows cache folders on the Windows drive (usually C:). Each folder is checked first. A whole drive, a folder that holds personal or system folders, or a folder that leads somewhere else through a link is skipped and named in the log.
  * Links inside those folders are never followed and never deleted.
  * Only the Recycle Bin of the Windows drive is emptied.
  * QUICK CLEAN asks before it starts.
* If files went missing after a QUICK CLEAN, stop saving anything to that drive and run a file recovery tool before new files overwrite them.
* New automatic test on real Windows: it builds folders with junctions and links to "work" files, runs the cleanup, and blocks the release if anything outside the cleaned folder is touched.

## 1.2.0

* **New GAMES page** for Apex Legends, Fortnite, Counter-Strike 2, VALORANT, Overwatch 2 and Rainbow Six Siege X:
  * Finds each game and the launcher it came from (Steam, EA app, Epic, Battle.net, Ubisoft Connect, Riot Client), and shows the game's own icon from your PC.
  * Reads the game's own video settings file (Apex `videoconfig.txt`, Fortnite `GameUserSettings.ini`, CS2 `cs2_video.txt`) and shows which settings already match the competitive setup and which to change.
  * Lists what to set in each game's menu, adjusted to your PC (GPU maker, video memory, laptop or desktop, screen refresh rate).
  * Gives the launch options for your launcher with a COPY button and the exact place to paste them (for example `-dev +fps_max 0` for Apex). Where a game has no useful launch options, it says so instead of listing placebo ones.
  * Game files are never changed.
* **Fits small screens.** The window sizes itself to the screen it opens on, so 1366x768 laptops at 125% scaling see the whole app. On short screens the menu hides its two bottom cards so every page button fits.
* **New-style pop-ups.** Confirmations use the app's neon look instead of plain Windows boxes.
* **Results card** after applying several changes: how many worked, any that failed or that Windows kept off, tweaks active before and after, and a restart button when needed.
* **Ctrl+F** jumps to the tweak search from any page; Esc clears it.
* The PowerShell window behind the app is minimized while the app is open, and comes back when you close it.
* Every release is now tested by opening the real app on Windows: every page at normal and small-laptop size, in English and Spanish, plus the dialogs. Any error, or any text without a Spanish translation, blocks the release.

## 1.1.2

* **The double-click launcher always gets the newest version.** `Run-Ozzyhn.cmd` now downloads the latest release first, and only uses the `ozzyhn.ps1` next to it when there is no internet. Before, anyone who had both files kept running their old copy forever.
* **Fix: settings Windows protects no longer break a tweak.** *Diagnostic services OFF* (part of *Revive Cheap PC* on PCs under 8 GB) stopped halfway on a service Windows does not let anyone change, and *Revert* stopped on the same one. Protected settings are now skipped and logged, like protected tasks already were, and revert always restores everything else.
* **Every tweak is tested on real Windows before release.** Each registry, service and task tweak is applied, checked to read ON, reverted, and checked that every original value came back exactly.
* Bug report form that asks for the version, Windows build and log.

## 1.1.1

* **Security fix.** The data folder `C:\ProgramData\Ozzyhn` could be written by any account on the PC. A program without admin rights could plant an undo journal there, and *Revert* would then apply it with admin rights. The folder is now locked to administrators. Your undo journal is carried over if an administrator wrote it; otherwise the old folder is set aside without being read.
* The launch command downloads the latest release instead of the `main` branch.
* Releases are published by GitHub Actions with `SHA256SUMS.txt` and a build attestation, after automatic checks for downloads, `Invoke-Expression` and antivirus exclusions.

## 1.1.0

* Registry tweaks really apply. 1.0 deleted registry values instead of writing them, so switches showed ON while nothing changed. If you used 1.0, press **RE-APPLY** on the Tweaks page.
* Tweaks with nothing to change on your PC show **N/A** and are not counted. Anything Windows blocks or later undoes is flagged with a one-click re-apply.
* Faster scan and background tasks, smooth scrolling in the tweak list.
* English / Español switch, the new OZ logo.

## 1.0.0

* First release.
