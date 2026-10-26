# Monitor SW — instruções de trabalho

- Responder sempre em português (pt-BR).
- Código-fonte fica SÓ no GitHub (privado) e no PC do desenvolvedor. O servidor recebe só o que roda.

## Estrutura
- `Monitor.sln` + `src/Monitor.csproj` — abre no Visual Studio 2022 (.NET Framework 4.8, C# 5).
- `src/Nucleo/` — leitura do servidor, índice, gravação de propriedades no SolidWorks (Core, Indexer, SwWriter).
- `src/Interface/` — telas WinForms (Ui, Preview). Versão em `src/Interface/Ui.cs` (AssemblyVersion/AssemblyFileVersion) — subir a cada entrega.
- `src/Modulos/` — funções independentes (Conferencia, Xlsx, Email). Função nova = arquivo novo aqui.
- `src/Recursos/` — ícone e outros recursos.
- `Detalhamento/` — gerador (PowerShell 5.1 + API do SolidWorks 2016), .bat, ini e templates.
  - `DetalharSW.ps1` só carrega os módulos e percorre os arquivos.
  - `Modulos/Nucleo/` — funções comuns; `Classificar.ps1` decide o TIPO da peça antes de detalhar.
  - `Modulos/Tipos/` — um arquivo por tipo (Metalon, Chapa, UsinadaTabelaFuros, Solda, Peca = roteador/fluxo padrão).
  - Regra de ouro: alteração pedida para um tipo mexe SÓ no arquivo daquele tipo. Se precisar mudar algo
    de `Nucleo/`, avisar que afeta todos os tipos. Ver `Detalhamento/Modulos/LEIA-ME.md`.
- `tools/testes/` — scripts de teste (nunca vão para o servidor).

## Compilar
- No PC: Visual Studio (Ctrl+Shift+B) ou `.\publicar.ps1` (Release em `out\Release\Monitor.exe`).
- Na nuvem (Claude): `/opt/pwsh/pwsh build.ps1` (Roslyn) -> `out/Monitor.exe`; compila todos os .cs de `src/`.
- Gerador: conferir sintaxe de `DetalharSW.ps1` e de todos os `Modulos/**/*.ps1` com `[System.Management.Automation.Language.Parser]::ParseFile` (0 erros). Arquivos .ps1 em UTF-8 COM BOM (PowerShell 5.1).

## Publicar no servidor (X:\MonitorSW)
- `.\publicar.ps1` no PC: verifica o gerador, compila, assina (se houver certificado) e copia só:
  `Monitor_atualizacao.exe` (atualiza sozinho em ~20 s), `Detalhamento\DetalharSW.ps1` + `Detalhamento\Modulos\`, .bat, LEIA-ME e
  ini/templates que ainda não existam lá. `.\publicar.ps1 -SoGerador` publica só o gerador.
- Publicação preferida: no PC, `git pull` em `Documentos\Monitor-SW` e `.\publicar.ps1` (ou `-SoGerador`).
  NUNCA enviar .cs, .csproj, .sln, CLAUDE.md ou scripts de build ao servidor.
- Toda atualização também vai para o GitHub: `git add -A && git commit -m "<versão>: <o que mudou>" && git push`.
- Nunca versionar dados da empresa (tsv/csv do servidor, logs, índice, arquivos SolidWorks/PDF/DXF) nem o .exe.

## Histórico (memória comum entre as sessões)
- Antes de alterar algo, ler `HISTORICO.md` (decisões e itens REJEITADO que não podem voltar).
- TODA alteração termina, nesta ordem: (1) linha nova em `HISTORICO.md` na seção do tipo/área
  (`- AAAA-MM-DD — o que mudou — motivo / pedido do usuário`; se o usuário recusar algo, registrar como **REJEITADO**;
  se ficar algo por testar, marcar **PENDENTE**), (2) commit com mensagem clara, (3) `git push`,
  (4) publicar no servidor para o usuário ver: `powershell -ExecutionPolicy Bypass -File .\publicar.ps1 -SemAssinar`
  (só o gerador mudou: acrescentar `-SoGerador`). O Monitor aberto troca sozinho para a versão nova em ~20 s.
  Só pular a publicação se o usuário pedir para testar antes.
- Sem push a outra sessão do Claude (claude.ai ou outro PC) não fica sabendo da mudança.
- Mudança no gerador também atualiza `Detalhamento/Regras.html` (painel de acompanhamento): ajuste a situação da regra
  em `REGRAS` (ok = testado, teste = aguardando teste, part, pend, rej) e acrescente a alteração no topo de `ALTERACOES`.
  Quando o usuário confirmar um teste, troque `teste` por `ok`. O publicar.ps1 copia a página para o servidor.
