# Histórico de decisões — Monitor SW e gerador de detalhamento

Registro do que foi pedido, decidido e **rejeitado**, por área. O código mostra o *como*; este arquivo
guarda o *porquê*. Toda alteração acrescenta uma linha aqui (mais recente em cima, dentro de cada seção).
Formato: `- AAAA-MM-DD — o que mudou — motivo / pedido do usuário`. Itens **REJEITADO** não devem voltar.

---

## Gerador — regras gerais
- 2026-10-26 — Avisos vermelhos do desenho sempre em uma coluna (mesma borda esquerda, um embaixo do outro) no topo esquerdo da folha; novo aviso no 1.1.1 e 1.2.1: "Remover cotas desnecessárias para processo laser" — pedido do usuário. **PENDENTE testar.**
- 2026-10-26 — Pelo botão do Monitor valem as saídas que o usuário marcou (desenho/PDF/DXF); a regra "laser = desenho + PDF + DXF" só vale arrastando no DETALHAR.bat — teste da Peça2 gerou DXF sem marcar. Balões vermelhos no cantinho superior esquerdo da FOLHA (acima da área das vistas; AvisoPosicaoX/Y no ini). Texto de todas as cotas centralizado na linha de cota (CenterText) — cota 60 da Peça2 saiu deslocada. **PENDENTE testar.**
- 2026-10-26 — Regras do setor (REGRAS_DETALHAMENTO.txt) no gerador: classes 1.1/1.1.1/1.2/1.2.1 (laser), 2.1 (usinagem), 3.1/3.2 (solda), 4.1/4.2 (metalon, barras, cantoneiras); só detalha com DESCRIÇÃO + ACABAMENTO + um processo preenchidos (aviso e bloqueio); laser sai com desenho+PDF+DXF, demais desenho+PDF; tabela de furos com MAIS DE 8 furos; avisos em vermelho (acabamento/precisões no desenho de usinagem; sobremetal, espessura > 4,76 e diâmetro pequeno no DXF); DXF de rosca/rebaixo só com o pré-furo. Página Detalhamento/Regras.html mostra o que está pronto, parcial e pendente. **PENDENTE testar no SolidWorks.**
- 2026-10-26 — **CONFIRMADO pelo usuário**: BARRA CHATA com usinagem = 2.1, sem usinagem = 4.1 (outras barras com usinagem = 4.2); CHAPA na descrição = laser; o processo (TORNO CNC/FRESA CNC/ELETRO), não o material, decide usinagem; peça sem regra segue o fluxo antigo com aviso; balões vermelhos no canto superior esquerdo da área útil.
- PENDENTE (regras do setor) — ponto 0 CNC no laser com usinagem; cota em um furo do padrão repetido (laser/solda 3.2); ±0,1 em furos > 12 mm; balão de solda preso na face; vista principal pela face com mais detalhes; tabela de furos no 1.2.1.
- 2026-10-25 — Gerador dividido em módulos (`Modulos/Nucleo`, `Modulos/Tipos`) + `Classificar.ps1` decide o tipo ANTES de detalhar — pedidos de um tipo estavam afetando outros tipos; a especialidade da aplicação é analisar a peça (propriedades + geometria) e rodar o script certo para ela.
- 2026-10-21 — Gerado pelo Monitor: o desenho fica ABERTO no SolidWorks com zoom na folha inteira; PDF não abre nada; DXF abre no AutoCAD — para conferir na hora.
- 2026-10-21 — Janela do PowerShell do gerador abre minimizada.
- Antes de 2026-10-20 — Escala e área útil da folha: vistas dentro de AreaL..AreaR / AreaB..AreaT, escalas de 5:1 a 1:50; carimbo com o nome do desenhista (login do Monitor, legenda tipo "G. Dias").
- Antes de 2026-10-20 — PDF/DXF atuais são `<código>.PDF/.DXF` sem sufixo; arquivos com APR são ignorados/protegidos (não sobrescrever PDF quando existe APR).

## Tipo: usinada-tabela-furos (referência 02124106)
- 2026-10-21 — Tabela de furos achatada (texto, linhas e colunas menores, até ~100 x 90 mm, texto mínimo 1,5 mm) — 1º teste saiu tabela 90 x 122 mm e escala 1:7.5, vistas muito pequenas. **PENDENTE testar.**
- 2026-10-21 — Usinada com `FurosParaTabela` (6) furos ou mais na vista principal → principal + cima, baixo, esquerda, direita + isométrica, tabela de furos (template `TabelaFuros_ProEstamp.sldholtbt`, criado do 02124106) no canto inferior direito, origem no canto superior esquerdo; cotas totais, raio e furos das laterais.
- PENDENTE — vistas maiores e centralizadas aproveitando a folha (como a imagem de referência, ~1:1.5); cotas dos degraus (70 e 11,50 no exemplo) ainda não automáticas; alinhamento das cotas laterais.

## Tipo: usinada (referência 02115187)
- Antes de 2026-10-20 — Frontal = face maior + vista de baixo + isométrica; cotas totais (comprimento em cima, altura à esquerda), posição dos furos (simétricos: só entre extremos), um raio de cada tamanho, chamada de furo por diâmetro, espessura na vista de baixo.

## Tipo: metalon (referência 02123721 — "perfeito, usar como referência")
- Antes de 2026-10-20 — Descrição com METALON/METALOM → vista lateral com linhas de quebra (a cada dois furos), perfil e isométrica mostrando a face com furos para frente.
- Cotas dos furos encadeadas a partir da extremidade mais próxima (~23 mm), alinhadas na mesma reta, pares por quebra; gabaritos de furação 250/500/1000; escala para aproveitar o espaço, cotas centralizadas; legenda posicionada antes dos balões.
- Quebras: `InsertBreak` com coordenadas "modelo x escala a partir do centro" (InsertBreak2 não existe; InsertBreakVertical fazia linha errada).

## Tipo: chapa (plana / dobrada / laser)
- 2026-10-26 — Cota do raio de dobra a 45° saiu ESPELHADA (para dentro da dobra, cruzando a aba): direção agora pela soma centro->pontas do arco (GetCurveParams2), bissetriz do lado de fora; o parâmetro médio da curva caía do lado errado. **PENDENTE testar.**
- 2026-10-26 — Cota do raio de dobra ainda saía pela ponta do arco (quase horizontal): agora a direção vem do ponto do MEIO do arco (curva avaliada no parâmetro médio) → ~45° numa dobra de 90°. **PENDENTE testar.**
- 2026-10-26 — Raio de dobra TESTADO (R10 ok). Cota do raio passa a sair no meio da dobra, entre as duas faces (chamada na bissetriz do arco, texto além do arco externo) — pedido do usuário com imagem. **PENDENTE testar.**
- 2026-10-26 — 1.2: cota o RAIO DE DOBRA (arco interno que tem um arco concêntrico com raio + espessura) na vista de perfil da dobra; antes cotava o raio do rasgo (R4,17) na lateral — pedido do usuário. **PENDENTE testar.**
- Antes de 2026-10-20 — Chapa plana: principal olha na direção da espessura (face maior) mesmo se não desenhada no plano frontal; principal + lateral + baixo mostrando a espessura.
- Chapa dobrada: planificada, espessura e raio.
- **REJEITADO** — cotas das linhas de dobra ("gerou muita informação"): removidas.
- DXF de laser: escala 1:1 (corrigido "4950"/1:5 com DIMLFAC=1), cotas totais com ±0,1, sem marcas de centro, tudo na camada 0 cor 7.

## Tipo: torneada / redonda
- Antes de 2026-10-20 — Duas medidas iguais → sem vista superior (repetiria a frontal); arruela/disco sem vértices → cota pelos círculos/silhueta.

## Montagem de solda (referência 13011773)
- 2026-10-20 — Uma isométrica + lista de peças pelo template `ListaSolda_ProEstamp.sldbomtbt` (criado do 13011773); balões com o CÓDIGO da peça, um por peça diferente (IgnoreMultiple); desenho ativo antes dos balões.
- **REJEITADO** — balões numéricos 1, 2, 3... ("não quero o balão numérico, só os textos").
- **REJEITADO** — balão por cópia de peça repetida (gerava numeração). Se um dia quiser, só como texto manual por cópia, em mudança separada.
- Layout de balões em escadinha/fileiras: várias tentativas; ficou a versão aprovada (commit b4c2400) — "ficou bom aparentemente".

## DXF / AutoCAD
- 2026-10-26 — Enquadramento (duplo clique no scroll) em TODO DXF gerado: AutoCAD recém-aberto agora espera o próprio arquivo carregar e dá REGEN + ZOOM E duas vezes; AutoCAD já aberto também repete o zoom. Raio de dobra a 45° pelo lado de fora: TESTADO. **PENDENTE testar o DXF.**
- 2026-10-21 — DXF grava a extensão real ($EXTMIN/$EXTMAX e vista *Active) para abrir enquadrado; abre no AutoCAD JÁ ABERTO (não abre outro), substitui se o arquivo já estiver aberto, REGEN + ZOOM E. Usuário confirmou: "deu certo".

## Monitor SW (programa)
- 2026-10-25 — 2.10: Opções › Tema (Escuro / Claro), escolha por usuário em `%LOCALAPPDATA%\MonitorSW\tema.txt`; ao trocar, o Monitor reinicia para aplicar — pedido do usuário (tema claro e escuro).
- 2026-10-25 — 2.9.0: projeto do Visual Studio (`Monitor.sln`, .NET 4.8), código em `src/Nucleo`, `src/Interface`, `src/Modulos`; `publicar.ps1`. Servidor `X:\MonitorSW` só com o que roda (sem código-fonte); fonte no GitHub privado e em `Documentos\Monitor-SW`.
- 2026-10-21 — 2.8.6: gerador minimizado. 2.8.5: erro inesperado não derruba o Monitor, grava `erros.log`.
- 2026-10-20 — 2.8.4: trocar/abrir montagem limpa a busca que escondia os itens.
- Antes de 2026-10-20 — Login de usuários (`usuarios.tsv`, senha com hash), "Conferido por <Nome>", Histórico por item e Histórico geral (menu Opções), busca no servidor com colunas ao vivo, avisos (toast próprio) no PC dos colegas, botão Conferência, exportação de lista para Excel, Gerar detalhamento (desenho/PDF/DXF), PENDENTE automático, raiz por PC, assinatura geométrica (salvar sem mudança não marca alteração).
- **REJEITADO / adiado** — envio de e-mail ("esquece o e-mail por enquanto"); "Marcar como revisado" removido.
