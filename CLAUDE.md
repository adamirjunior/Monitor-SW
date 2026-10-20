# Monitor SW — instruções de trabalho

- Responder sempre em português (pt-BR).
- Monitor: C# 5 / .NET 4.5 WinForms em `src/`. Compilar com `/opt/pwsh/pwsh build.ps1` (Roslyn) -> `out/Monitor.exe`.
  Versão em `src/Ui.cs` (AssemblyVersion / AssemblyFileVersion) — subir a cada entrega.
- Gerador: `Detalhamento/DetalharSW.ps1` (PowerShell 5.1 + API do SolidWorks 2016). Conferir sintaxe com
  `[System.Management.Automation.Language.Parser]::ParseFile`.
- Entrega no servidor da ProEstamp (pelo PC conectado): copiar para uma pasta NOVA em /mnt/user-data/outputs e enviar
  - `X:\MonitorSW\Monitor_atualizacao.exe` (atualiza sozinho em ~20 s)
  - `X:\MonitorSW\codigo-fonte\*.cs`
  - `X:\MonitorSW\Detalhamento\DetalharSW.ps1` (com expectedMtimeMs; conferir o tamanho depois)
- Toda atualização entregue também vai para o GitHub: `git add -A && git commit -m "<versão>: <o que mudou>" && git push`.
- Nunca versionar dados da empresa (tsv/csv do servidor, logs, índice, arquivos SolidWorks/PDF/DXF) nem o .exe.
