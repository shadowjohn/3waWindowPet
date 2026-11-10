@echo off
start "" /min powershell.exe -NoProfile -STA -ExecutionPolicy Bypass -File "%~dp0pet.ps1"
