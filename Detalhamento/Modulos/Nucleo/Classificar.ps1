# Classificar.ps1 - análise rápida da peça ANTES de detalhar: decide a CLASSE (regras do setor) e o fluxo.
# Regras completas: Detalhamento\REGRAS_DETALHAMENTO.txt e Detalhamento\Regras.html
# Carregado pelo DetalharSW.ps1 (dot-source). Não rodar sozinho.
#
# Ordem (a primeira que bate decide):
#   4) PERFIS     descrição com METALON/METALOM/CANTONEIRA/BARRA  -> 4.1 sem usinagem | 4.2 com usinagem (Tipos\Metalon.ps1)
#                 exceção: BARRA CHATA com usinagem vai para 2.1 (usinada)
#   1) LASER      descrição com LASER/OXICORTE/CHAPA              -> 1.1 plana | 1.1.1 plana + usinagem
#                                                                    1.2 dobrada | 1.2.1 dobrada + usinagem
#   2) USINAGEM   TORNO CNC / FRESA CNC / ELETRO preenchido        -> 2.1 (prismática ou torneada; tabela de furos se > 8 furos)
#   -) SEM CLASSE nenhuma regra: fluxo padrão antigo + aviso no log
#   3) SOLDA      montagens (.SLDASM) -> Tipos\Solda.ps1 (3.1 sem usinagem | 3.2 com usinagem)
#
# Campos devolvidos: Classe (ex.: "1.1.1"), Grupo (laser/usinagem/perfil/sem-classe), Fluxo (metalon/chapa-plana/
# chapa-dobrada/usinada/torneada/generica), Usinagem (CNC), Furos (roscados/rebaixos), Laser, Plana, Redonda...

function ClassificarPeca($caminho, $peca) {
    $desc = [string](Prop $peca $PropDesc)
    $k = [ordered]@{
        Classe = ""; Grupo = "sem-classe"; Fluxo = "generica"; Motivo = ""; Descricao = $desc
        Laser = $false; Chapa = (TemChapa $peca); Usinagem = (TemUsinagemCnc $peca); UsinagemAntiga = (TemUsinagem $peca)
        Espessura = 0.0; X = 0.0; Y = 0.0; Z = 0.0; Maior = 0.0; Menor = 0.0; Caixa = $null
        Plana = $false; Dobrada = $false; Redonda = $false; UsinPrisma = $false
        Furos = $null; Avisos = @(); FazDxf = $false
    }
    # caixa da peça
    $b = XD (X $peca "GetPartBox" $true)
    $k.Caixa = $b
    $k.X = [math]::Abs($b[3] - $b[0]); $k.Y = [math]::Abs($b[4] - $b[1]); $k.Z = [math]::Abs($b[5] - $b[2])
    $k.Maior = [math]::Max($k.X, [math]::Max($k.Y, $k.Z))
    $k.Menor = [math]::Min($k.X, [math]::Min($k.Y, $k.Z))
    # espessura: do recurso de chapa metálica; senão do texto "ESP. x" da descrição
    try {
        $ft = X $peca "FirstFeature"
        while ($ft) {
            if ([string](X $ft "GetTypeName2") -eq "SheetMetal") { $df = X $ft "GetDefinition"; $k.Espessura = [double](XG $df "Thickness"); break }
            $ft = X $ft "GetNextFeature"
        }
    } catch { }
    if ($k.Espessura -le 0) {
        # mesma leitura da conferência (mm ou polegada: ESP. 3/16" = 4,76 mm; antes lia "3")
        # só em descrição de chapa (ESP./E= ou laser): "TREF RED 1/2\" X 17" não é espessura
        $eD = $null; if ($desc -match '(?i)ESP|\bE\s*=' -or (EhLaser $desc)) { try { $eD = EspessuraDaDescricao $desc } catch { } }
        if ($eD) { $k.Espessura = [double]$eD }
    }
    $mx = $k.Maior; $mn = $k.Menor
    $k.Furos = InfoFuros $peca
    if ($k.Espessura -le 0 -and $mn -lt 0.1 * $mx) { $k.Espessura = $mn }
    # descrição em polegada arredondada (3/16" = 4,7625) e o 3D com 4,8: vale a medida do 3D (as cotas procuram a espessura real)
    elseif ($k.Espessura -gt 0 -and [math]::Abs($mn - $k.Espessura) -le 0.00011 -and [math]::Abs($mn - $k.Espessura) -gt 0.000001) { $k.Espessura = $mn }

    $pPerfil = TemPalavra $desc $PalavrasPerfil
    $pBarraUsin = TemPalavra $desc $PalavrasBarraUsin
    $pLaser = TemPalavra $desc $PalavrasLaser
    $u = $k.Usinagem
    $k.Redonda = (([math]::Abs($k.Y - $k.Z) -lt 0.01 * $mx) -or ([math]::Abs($k.X - $k.Z) -lt 0.01 * $mx) -or ([math]::Abs($k.X - $k.Y) -lt 0.01 * $mx))

    if ($pPerfil -and -not ($pBarraUsin -and $u)) {
        # 4) metalons, barras e cantoneiras: mesma lógica de quebras e cotas do metalon (padrão 02123721)
        $k.Grupo = "perfil"; $k.Fluxo = "metalon"; $k.Classe = $(if ($u) { "4.2" } else { "4.1" })
        $k.Motivo = "descrição com $pPerfil" + $(if ($u) { " + usinagem" } else { "" })
    } elseif ($pLaser) {
        # 1) laser: plana ou dobrada pela geometria; com usinagem CNC usa a tratativa de usinada
        $k.Grupo = "laser"; $k.Laser = $true; $k.FazDxf = $true
        $plana = ($mn -lt 0.1 * $mx) -or ($mn -le 0.0065)
        if ($k.Chapa -and $k.Espessura -gt 0) { $plana = ($mn -le $k.Espessura * 1.1 + 0.0001) }
        # sem chapa metálica e a menor medida = espessura da descrição: chapa GROSSA plana cortada no laser
        # (ex.: 02115197, ESP 5/8" = 15,88 x 40 x 47,25 - era tratada como dobrada)
        elseif (-not $k.Chapa -and $k.Espessura -gt 0 -and [math]::Abs($mn - $k.Espessura) -le [math]::Max(0.0005, 0.05 * $k.Espessura)) { $plana = $true }
        $k.Plana = $plana; $k.Dobrada = -not $plana
        if ($plana) { $k.Classe = $(if ($u) { "1.1.1" } else { "1.1" }); $k.Fluxo = $(if ($u) { "usinada" } else { "chapa-plana" }) }
        else { $k.Classe = $(if ($u) { "1.2.1" } else { "1.2" }); $k.Fluxo = "chapa-dobrada" }
        $k.Motivo = "descrição com $pLaser, " + $(if ($plana) { "plana" } else { "dobrada" }) + $(if ($u) { " + usinagem" } else { "" })
        if ($k.Fluxo -eq "usinada") { $k.UsinPrisma = $true; $k.Plana = $false }
    } elseif ($u) {
        # 2) usinagem
        $k.Grupo = "usinagem"; $k.Classe = "2.1"
        $k.Fluxo = $(if ($k.Redonda) { "torneada" } else { "usinada" })
        $k.UsinPrisma = -not $k.Redonda
        $mat = TemPalavra $desc $PalavrasUsinagem
        $k.Motivo = "TORNO CNC / FRESA CNC / ELETRO preenchido" + $(if ($mat) { ", material $mat" } else { "" })
    } else {
        # sem classe: fluxo antigo (chapa fina / torneada / genérica)
        $plana = ($mn -lt 0.1 * $mx) -and ($mn -le 0.0065)
        if ($k.Chapa -and $k.Espessura -gt 0) { $plana = ($mn -le $k.Espessura * 1.1 + 0.0001) }
        $k.Plana = $plana
        $k.UsinPrisma = $k.UsinagemAntiga -and -not $k.Redonda -and -not $plana
        $k.Fluxo = $(if ($k.Chapa -and -not $plana) { "chapa-dobrada" } elseif ($plana) { "chapa-plana" } elseif ($k.Redonda) { "torneada" } elseif ($k.UsinPrisma) { "usinada" } else { "generica" })
        $k.Motivo = "nenhuma regra do setor bateu (sem LASER/CHAPA/OXICORTE, sem TORNO CNC/FRESA CNC/ELETRO, não é perfil)"
        Log "   Aviso: peça sem classe nas regras do setor; detalhando pelo fluxo padrão ($($k.Fluxo))." "Yellow"
    }
    if ($k.Redonda -and $k.Fluxo -ne "torneada" -and $k.Grupo -ne "perfil" -and -not $k.Laser) { $k.UsinPrisma = $false }

    # avisos em vermelho do DESENHO
    if ($u) { $k.Avisos += "Adicionar acabamento nas faces e precisões necessárias" }
    if ($k.Classe -eq "1.1.1" -or $k.Classe -eq "1.2.1") { $k.Avisos += "Remover cotas desnecessárias para processo laser" }

    $f = $k.Furos
    Log ("   Classificação: {0} {1} ({2}) | fluxo {3} | caixa {4:N1} x {5:N1} x {6:N1} mm | esp. {7:N2} mm | furos: {8} roscado(s), {9} rebaixo(s), {10} simples" -f `
        $k.Classe, $k.Grupo.ToUpper(), $k.Motivo, $k.Fluxo, ($k.X * 1000), ($k.Y * 1000), ($k.Z * 1000), ($k.Espessura * 1000), $f.Roscados, $f.Rebaixos, $f.Simples) "Cyan"
    return [pscustomobject]$k
}

# montagem de solda: 3.1 sem usinagem | 3.2 com usinagem
function ClassificarMontagem($caminho, $asm) {
    $desc = [string](Prop $asm $PropDesc)
    $cod = Codigo $caminho
    $porNome = $false; foreach ($p in $PrefixosSolda) { if ($p -and $cod.StartsWith($p)) { $porNome = $true } }
    $porDesc = TemPalavra $desc $PalavrasSolda
    $u = TemUsinagemCnc $asm
    $classe = $(if ($u) { "3.2" } else { "3.1" })
    $motivo = $(if ($porNome) { "código $cod" } elseif ($porDesc) { "descrição com $porDesc" } elseif (EhPastaSolda $caminho) { "pasta de solda" } else { "montagem fora das regras de solda" })
    Log ("   Classificação: {0} SOLDA ({1}){2}" -f $classe, $motivo, $(if ($u) { " + usinagem" } else { "" })) "Cyan"
    return [pscustomobject]@{ Classe = $classe; Usinagem = $u; Motivo = $motivo; EhSolda = ($porNome -or [bool]$porDesc -or (EhPastaSolda $caminho)) }
}
