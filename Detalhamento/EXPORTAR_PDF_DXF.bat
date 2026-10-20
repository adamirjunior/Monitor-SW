@echo off
chcp 65001 >nul
REM Arraste desenhos (.SLDDRW), pecas ou pastas sobre este arquivo para gerar PDF (e DXF se for laser)
powershell -NoProfile -ExecutionPolicy Bypass -STA -File "%~dp0DetalharSW.ps1" -Modo exportar %*
pause
