@echo off
title Optimizaciones de Ozzyhn ^| OZZYHN TWEAKS
rem Double-click launcher. Uses the local copy if it sits next to this file (works offline),
rem otherwise downloads the latest release from GitHub. It will ask for Administrator rights.
if exist "%~dp0ozzyhn.ps1" (
    powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0ozzyhn.ps1"
) else (
    powershell -NoProfile -ExecutionPolicy Bypass -Command "[Net.ServicePointManager]::SecurityProtocol=[Net.SecurityProtocolType]::Tls12; irm 'https://github.com/ozzyhntweaks/optimizaciones-de-ozzyhn/releases/latest/download/ozzyhn.ps1' | iex"
)
