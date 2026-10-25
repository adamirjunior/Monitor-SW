# Monitor SW — instruções de trabalho

- Responder sempre em português (pt-BR).
- Código-fonte fica SÓ no GitHub (privado) e no PC do desenvolvedor. O servidor recebe só o que roda.

## Estrutura
- `Monitor.sln` + `src/Monitor.csproj` — abre no Visual Studio 2022 (.NET Framework 4.8, C# 5).
- `src/Nucleo/` — leitura do servidor, índice, gravação de propriedades no SolidWorks (Core, Indexer, SwWriter).
- `src/Interface/` — telas WinForms (Ui, Preview). Versão em `src/Interface/Ui.cs` (AssemblyVersion/AssemblyFileVersion) — subir a cada entrega.
- `src/Modulos/` — funções independentes (Conferencia, Xlsx, Email). Função nova = arquivo novo aqui.
- `src/Recursos/` — ícone e outros recursos.
- `Detalhamento/` — gerador `DetalharSW.ps1` (PowerShell 5.1 + API do SolidWorks 2016), .bat, ini e templates.
- `tools/testes/` — scripts de teste (nunca vão para o servidor).

## Compilar
- No PC: Visual Studio (Ctrl+Shift+B) ou `.\publicar.ps1` (Release em `out\Release\Monitor.exe`).
- Na nuvem (Claude): `/opt/pwsh/pwsh build.ps1` (Roslyn) -> `out/Monitor.exe`; compila todos os .cs de `src/`.
- Gerador: conferir sintaxe com `[System.Management.Automation.Language.Parser]::ParseFile` (0 erros).

## Publicar no servidor (X:\MonitorSW)
- `.\publicar.ps1` no PC: verifica o gerador, compila, assina (se houver certificado) e copia só:
  `Monitor_atualizacao.exe` (atualiza sozinho em ~20 s), `Detalhamento\DetalharSW.ps1`, .bat, LEIA-ME e
  ini/templates que ainda não existam lá. `.\publicar.ps1 -SoGerador` publica só o gerador.
- Entrega feita pelo Claude pelo PC conectado: pasta NOVA em /mnt/user-data/outputs + device_commit_files com
  expectedMtimeMs, só `Monitor_atualizacao.exe` e `Detalhamento\DetalharSW.ps1`. NUNCA enviar .cs ao servidor.
- Toda atualização também vai para o GitHub: `git add -A && git commit -m "<versão>: <o que mudou>" && git push`.
- Nunca versionar dados da empresa (tsv/csv do servidor, logs, índice, arquivos SolidWorks/PDF/DXF) nem o .exe.
