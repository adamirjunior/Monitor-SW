# Gerador de detalhamento — módulos

O `DetalharSW.ps1` só lê os parâmetros, carrega os módulos e percorre a lista de arquivos.
Toda peça passa por **duas etapas**:

0. **Validar** (`Nucleo\Regras.ps1` → `ValidarPropriedades`): DESCRIÇÃO, ACABAMENTO e um processo preenchidos; senão avisa e não detalha.
1. **Classificar** (`Nucleo\Classificar.ps1` → `ClassificarPeca`): análise rápida com as propriedades
   (descrição, usinagem, processo) e a geometria (caixa, espessura, chapa metálica). Decide o **tipo**
   e grava no log: `Classificação: USINADA (usinagem preenchida, prismática) | caixa ...`.
2. **Detalhar pelo tipo**: cada tipo tem o seu arquivo em `Tipos\`.

## Classes do setor (ver `Detalhamento\Regras.html` e `REGRAS_DETALHAMENTO.txt`)

1.1 / 1.1.1 / 1.2 / 1.2.1 laser · 2.1 usinagem · 3.1 / 3.2 solda · 4.1 / 4.2 metalon, barras e cantoneiras.
A classe escolhe o fluxo abaixo (`$cls.Fluxo`).

## Fluxos (tipos de detalhamento)

| Tipo | Regra (a primeira que bate decide) | Onde está | Referência |
|---|---|---|---|
| `metalon` | descrição com METALON/METALOM | `Tipos\Metalon.ps1` | 02123721 |
| `chapa-dobrada` | chapa metálica com dobra | `Tipos\Peca.ps1` (fluxo padrão) + `Tipos\Chapa.ps1` (cotas, dobras) | — |
| `chapa-plana` | chapa fina (laser ou ≤ 6,5 mm) ou chapa metálica sem dobra | `Tipos\Peca.ps1` + `Tipos\Chapa.ps1` | — |
| `torneada` | duas medidas da caixa iguais | `Tipos\Peca.ps1` | — |
| `usinada` | usinagem preenchida e prismática | `Tipos\Peca.ps1` + `Nucleo\Cotas.ps1` | 02115187 |
| `usinada-tabela-furos` | usinada com `FurosParaTabela` furos ou mais | `Tipos\UsinadaTabelaFuros.ps1` | 02124106 |
| `generica` | nenhuma das anteriores | `Tipos\Peca.ps1` (cotas do modelo) | — |
| montagem de solda | arquivo .SLDASM | `Tipos\Solda.ps1` | 13011773 |

## Como pedir uma alteração (ao Claude ou a quem for mexer)

Diga **o tipo** e **o que muda**, por exemplo:
- "No tipo `usinada-tabela-furos`: vistas maiores, tabela no canto inferior direito com no máximo 100 x 90 mm."
- "Regra nova: descrição com EIXO → tipo `eixo` (vista única deitada, cotas de diâmetro)."

Assim a mudança fica só no arquivo daquele tipo e não afeta os outros.

## Criar um tipo novo

1. Em `Nucleo\Classificar.ps1`, acrescente a regra **antes** da que hoje pegaria a peça.
2. Crie `Tipos\<Tipo>.ps1` com a função `Detalhar<Tipo>`.
3. Ponha o arquivo na lista de módulos do `DetalharSW.ps1` (antes de `Tipos\Peca`).
4. Em `Tipos\Peca.ps1` (`DetalharPeca`), chame a função quando `$cls.Tipo` for o novo tipo.

## Funções comuns (`Nucleo\`)

| Arquivo | O que tem |
|---|---|
| `Config.ps1` | log, relatório, leitura do `detalhamento.ini` |
| `SwCom.ps1` | ponte COM com o SolidWorks (`X`, `XG`, `XS`, `K`) |
| `Utilidades.ps1` | caminhos, propriedades, abrir/fechar, vistas, escala, salvar |
| `Cotas.ps1` | modelo → folha, cotas totais, furos, raios, chamadas de furo |
| `Layout.ps1` | disposição das vistas, centralizar, anti-sobreposição |
| `Dxf.ps1` | DXF de corte e abertura no AutoCAD |
| `Carimbo.ps1` | desenhista no carimbo |
| `Fluxo.ps1` | exportar desenho existente e Gerar (botão do Monitor) |
