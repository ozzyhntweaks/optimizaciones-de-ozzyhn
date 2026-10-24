@echo off
title Optimizaciones de Ozzyhn ^| OZZYHN TWEAKS
rem Double-click launcher. It runs the latest release from GitHub, so you always get the newest fixes.
rem If GitHub cannot be reached, it runs the ozzyhn.ps1 next to this file instead (offline use).
rem The app asks for Administrator rights by itself.
set "OZ_LOCAL=%~dp0ozzyhn.ps1"
powershell -NoProfile -ExecutionPolicy Bypass -Command "[Net.ServicePointManager]::SecurityProtocol=[Net.SecurityProtocolType]::Tls12; $s = $null; try { $s = Invoke-RestMethod -Uri 'https://github.com/ozzyhntweaks/optimizaciones-de-ozzyhn/releases/latest/download/ozzyhn.ps1' -TimeoutSec 20 -ErrorAction Stop } catch { }; if ($s -is [string] -and $s.Contains('Start-Ozzyhn')) { Invoke-Expression $s } elseif (Test-Path -LiteralPath $env:OZ_LOCAL) { Write-Host 'GitHub not reachable: running the local copy. / Sin conexion con GitHub: usando la copia local.' -ForegroundColor Yellow; & $env:OZ_LOCAL } else { Write-Host 'Could not download the app. Check your internet connection. / No se pudo descargar la app. Revisa tu conexion.' -ForegroundColor Red; Read-Host 'Press Enter to close / Presiona Enter para cerrar' }"
