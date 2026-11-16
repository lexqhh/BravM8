@echo off
title FlyMedia
set "FLYMEDIA_BAT=%~f0"
set "FLYMEDIA_REPO=__REPO__"
powershell -NoProfile -ExecutionPolicy Bypass -Command "$ErrorActionPreference='Stop'; [Net.ServicePointManager]::SecurityProtocol='Tls12'; $p=Join-Path $env:TEMP 'flymedia-update.ps1'; try { (New-Object Net.WebClient).DownloadFile('https://github.com/'+$env:FLYMEDIA_REPO+'/releases/latest/download/update.ps1',$p) } catch { Write-Host 'Impossible de joindre le serveur de mise a jour. Verifie ta connexion internet.' -ForegroundColor Red; exit 1 }; & $p"
if errorlevel 1 pause
