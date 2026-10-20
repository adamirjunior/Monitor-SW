@echo off
chcp 65001 >nul
REM Arraste pecas (.SLDPRT), submontagens (.SLDASM) ou pastas sobre este arquivo
powershell -NoProfile -ExecutionPolicy Bypass -STA -File "%~dp0DetalharSW.ps1" -Modo detalhar %*
pause
