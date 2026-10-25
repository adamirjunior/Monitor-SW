# Como desenvolver o Monitor SW no PC

## 1. Instalar (uma vez)
1. **Visual Studio 2022 Community** — carga de trabalho **"Desenvolvimento para desktop com .NET"**
   e, em Componentes individuais, **"Pacote de direcionamento do .NET Framework 4.5"** (ou 4.8).
2. **Git for Windows** (o Visual Studio já traz, mas o terminal fica melhor com ele).
3. **Visual Studio Code** + extensões **PowerShell** e **Claude Code** — para editar o gerador e pedir alterações ao Claude no próprio PC.

## 2. Pegar o código
Visual Studio > *Clonar um repositório* > `https://github.com/adamirjunior/Monitor-SW`
> pasta em `Documentos\Monitor-SW`. Abra `Monitor.sln`.

## 3. Dia a dia
| Ação | Onde |
|---|---|
| Rodar com depurador (parar em linha, ver variáveis) | F5 |
| Só compilar | Ctrl+Shift+B (erros na Lista de Erros) |
| Editar o gerador | VS Code, `Detalhamento\DetalharSW.ps1` |
| Pedir alteração ao Claude | VS Code > painel Claude Code (lê, edita, compila e corrige) |
| Salvar versão | Git > Confirmar e Enviar (commit + push) |
| Publicar no servidor | PowerShell na pasta: `.\publicar.ps1` |

Antes de publicar, suba a versão em `src\Interface\Ui.cs` (AssemblyVersion).
Se o PowerShell bloquear o script: `Set-ExecutionPolicy -Scope CurrentUser RemoteSigned`.

## 4. Segurança do servidor
- No servidor fica só: `Monitor.exe` / `Monitor_atualizacao.exe`, `config.ini`, dados (`*.tsv`, `*.csv`, `indice\`, logs)
  e `Detalhamento\` (DetalharSW.ps1, .bat, ini, templates, referências).
- Permissões (feito pelo administrador do Windows/TI) em `X:\MonitorSW`:
  usuários = **Ler e executar** + **Modificar** só nos arquivos de dados (tsv/csv/log/indice);
  `Monitor*.exe` e `Detalhamento\*.ps1` = só leitura para todos, escrita só para quem publica.
- Assinatura (opcional): com um certificado de assinatura de código instalado, o `publicar.ps1` assina sozinho
  o .exe e o .ps1; dá para exigir `AllSigned` nos PCs para o gerador só rodar se não foi alterado.
