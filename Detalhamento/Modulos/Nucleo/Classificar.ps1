# Classificar.ps1 - análise rápida da peça ANTES de detalhar: decide o TIPO e qual módulo de Tipos\ detalha.
# Carregado pelo DetalharSW.ps1 (dot-source). Não rodar sozinho.
#
# Ordem das regras (a primeira que bate decide):
#   1. metalon          descrição contém METALON / METALOM                       -> Tipos\Metalon.ps1
#   2. chapa-dobrada    tem chapa metálica (planificado) e a caixa é maior que a espessura -> Tipos\Peca.ps1 (fluxo padrão + planificada)
#   3. chapa-plana      chapa fina: menor medida < 10% da maior e (laser ou <= 6,5 mm), ou chapa metálica sem dobra
#   4. torneada         duas medidas da caixa iguais (peça de revolução)          -> fluxo padrão, sem vista superior
#   5. usinada          tem propriedade de usinagem preenchida e é prismática     -> fluxo padrão de usinada;
#                       com FurosParaTabela furos ou mais na vista principal       -> Tipos\UsinadaTabelaFuros.ps1
#   6. generica         nenhuma das anteriores                                   -> fluxo padrão com cotas do modelo
#
# Para criar um tipo novo: acrescente a regra aqui (antes da que hoje pegaria a peça), crie Tipos\<Tipo>.ps1
# com a função Detalhar<Tipo>, ponha o arquivo na lista de módulos do DetalharSW.ps1 e chame-a em DetalharPeca.

function ClassificarPeca($caminho, $peca) {
    $desc = [string](Prop $peca $PropDesc)
    $k = [ordered]@{
        Tipo = "generica"; Motivo = ""; Descricao = $desc
        Laser = (EhLaser $desc); Chapa = (TemChapa $peca); Usinagem = (TemUsinagem $peca)
        Espessura = 0.0; X = 0.0; Y = 0.0; Z = 0.0; Maior = 0.0; Menor = 0.0; Caixa = $null
        Plana = $false; Redonda = $false; UsinPrisma = $false
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
        $mEsp = [regex]::Match($desc, "(?i)ESP\.?\s*([0-9]+(?:[\.,][0-9]+)?)")
        if ($mEsp.Success) { $k.Espessura = [double]($mEsp.Groups[1].Value.Replace(",", ".")) / 1000 }
    }
    $mx = $k.Maior; $mn = $k.Menor
    # chapa plana: a principal olha na direção da espessura; chapa metálica só é plana se a menor medida for a espessura
    $k.Plana = ($mn -lt 0.1 * $mx) -and ($k.Laser -or $mn -le 0.0065)
    if ($k.Chapa -and $k.Espessura -gt 0) { $k.Plana = ($mn -le $k.Espessura * 1.1 + 0.0001) }
    $k.Redonda = (-not $k.Laser) -and (([math]::Abs($k.Y - $k.Z) -lt 0.01 * $mx) -or ([math]::Abs($k.X - $k.Z) -lt 0.01 * $mx))
    $k.UsinPrisma = $k.Usinagem -and -not $k.Laser -and -not $k.Redonda -and -not $k.Plana

    # ---- regras (a primeira que bate decide)
    if (EhMetalon $desc) { $k.Tipo = "metalon"; $k.Motivo = "descrição com METALON" }
    elseif ($k.Chapa -and -not $k.Plana) { $k.Tipo = "chapa-dobrada"; $k.Motivo = "chapa metálica com dobra" }
    elseif ($k.Plana) { $k.Tipo = "chapa-plana"; $k.Motivo = $(if ($k.Chapa) { "chapa metálica sem dobra" } elseif ($k.Laser) { "chapa fina de laser" } else { "chapa fina (<= 6,5 mm)" }) }
    elseif ($k.Redonda) { $k.Tipo = "torneada"; $k.Motivo = "peça de revolução (duas medidas iguais)" }
    elseif ($k.UsinPrisma) { $k.Tipo = "usinada"; $k.Motivo = "usinagem preenchida, prismática" }
    else { $k.Tipo = "generica"; $k.Motivo = "nenhuma regra específica" }

    Log ("   Classificação: {0} ({1}) | caixa {2:N1} x {3:N1} x {4:N1} mm | laser: {5} | chapa metálica: {6} | usinagem: {7}" -f `
        $k.Tipo.ToUpper(), $k.Motivo, ($k.X * 1000), ($k.Y * 1000), ($k.Z * 1000), $k.Laser, $k.Chapa, $k.Usinagem) "Cyan"
    return [pscustomobject]$k
}
