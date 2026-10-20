# Monitor SW

Monitor de detalhamento (SLDDRW / PDF / DXF) dos projetos SolidWorks 2016 e gerador automático de detalhamento.

- `src/` — aplicativo Monitor (C# 5 / .NET 4.5, WinForms). Compilar com `build.ps1` (Roslyn) ou `COMPILAR.bat` no servidor.
- `Detalhamento/DetalharSW.ps1` — gerador de detalhamento (PowerShell 5.1 + API do SolidWorks).
- `test/` — scripts de teste.

Dados de uso (marcações, conferência, histórico, usuários, índice) ficam só no servidor e não entram no repositório.
