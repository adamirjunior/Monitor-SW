# UsinadaTabelaFuros.ps1 - usinada com muitos furos: tabela de furos (padrão 02124106)
# Carregado pelo DetalharSW.ps1 (dot-source). Não rodar sozinho.

# ---------------------------------------------------------------- usinada com muitos furos: tabela de furos (padrão 02124106)
# vista principal + vistas de cima, de baixo, esquerda e direita + isométrica; tabela de furos (RÓTULO / LOC X / LOC Y / TAMANHO)
# no canto inferior direito, origem no canto superior esquerdo da principal; cotas totais, raio e furos das laterais
function TemplateTabelaFuros {
    $ini = C "TemplateTabelaFuros" ""
    if ($ini -and (Test-Path $ini)) { return $ini }
    $tpl = Join-Path $Pasta "TabelaFuros_ProEstamp.sldholtbt"
    if (Test-Path $tpl) { return $tpl }
    $ref = C "DesenhoReferenciaTabelaFuros" ""
    if (-not $ref -or -not (Test-Path $ref)) { $ref = Join-Path $Pasta "Referencia_TabelaFuros_02124106.SLDDRW" }
    if (-not (Test-Path $ref)) { Log "   (desenho de referência da tabela de furos não encontrado)" "DarkYellow"; return "" }
    $d = AbrirDoc $ref $DocDRW
    if (-not $d) { return "" }
    $tipo = K "swTableAnnotationType_e" @("swTableAnnotation_HoleChart") 1
    $salvou = $false
    try {
        $v = X $d "GetFirstView"
        while ($v -and -not $salvou) {
            $tas = $null; try { $tas = X $v "GetTableAnnotations" } catch { }
            foreach ($t in @($tas)) {
                if (-not $t) { continue }
                $tp = -1; try { $tp = [int](XG $t "Type") } catch { }
                if ($tp -eq $tipo) { try { $salvou = [bool](X $t "SaveAsTemplate" $tpl) } catch { Log "   (SaveAsTemplate tabela de furos: $($_.Exception.Message))" "DarkYellow" }; if ($salvou) { break } }
            }
            $v = X $v "GetNextView"
        }
    } catch { }
    Fechar $d
    if ($salvou -and (Test-Path $tpl)) { Log "   Template da tabela de furos criado a partir de $(Split-Path -Leaf $ref)" "Green"; return $tpl }
    Log "   (não consegui salvar o template da tabela de furos)" "DarkYellow"
    return ""
}
function SelecionarComMarca($dm, $v, $ent, [bool]$somar, [int]$marca) {
    try {
        $sd = X (XG $dm "SelectionManager") "CreateSelectData"
        XS $sd "View" $v; XS $sd "Mark" $marca
        if (X $ent "Select4" $somar $sd) { return $true }
    } catch { }
    return $false
}
function InserirTabelaFuros($dm, $front) {
    $tpl = TemplateTabelaFuros
    AtivarDesenho $dm | Out-Null
    $a = DadosXf $front
    # origem: canto superior esquerdo da peça na vista principal
    $pts = @(); foreach ($vx in (Entidades $front "swViewEntityType_Vertex" 2)) { try { $pts += ,@($vx, (Rot $a ([double[]](XD (X $vx "GetPoint"))))) } catch { } }
    if ($pts.Count -eq 0) { Log "   (tabela de furos: sem vértices na vista principal)" "DarkYellow"; return $null }
    $minX = ($pts | ForEach-Object { $_[1][0] } | Measure-Object -Minimum).Minimum
    $orig = @($pts | Where-Object { $_[1][0] -le $minX + 0.0002 } | Sort-Object { $_[1][1] })[-1]
    # face: a maior face plana virada para quem olha
    $face = $null; $areaMax = 0
    foreach ($f in (Entidades $front "swViewEntityType_Face" 3)) {
        try {
            $nrm = XD (XG $f "Normal"); if (-not $nrm) { continue }
            $z = $nrm[0] * $a[2] + $nrm[1] * $a[5] + $nrm[2] * $a[8]
            if ([math]::Abs($z) -lt 0.99) { continue }
            $ar = [double](X $f "GetArea"); if ($ar -gt $areaMax) { $areaMax = $ar; $face = $f }
        } catch { }
    }
    if (-not $face) { Log "   (tabela de furos: não achei a face da vista principal)" "DarkYellow"; return $null }
    $anc = $AnchorBR
    foreach ($mFace in 2, 4, 1) {
        X $dm "ClearSelection2" $true | Out-Null
        $okV = SelecionarComMarca $dm $front $orig[0] $false 1
        $okF = SelecionarComMarca $dm $front $face $true $mFace
        $ht = $null
        try { $ht = X $front "InsertHoleTable2" $false 0.2917 0.0345 $anc "1" $tpl } catch { Log "   [dbg] InsertHoleTable2 (marca $mFace): $($_.Exception.Message)" "DarkGray" }
        if ($ht) { Log "   Tabela de furos inserida$(if ($tpl) { ' (template ProEstamp)' } else { ' (template padrão)' })"; X $dm "ClearSelection2" $true | Out-Null; return $ht }
        Log "   [dbg] tabela de furos não saiu (vértice $okV, face $okF, marca $mFace)" "DarkGray"
    }
    X $dm "ClearSelection2" $true | Out-Null
    return $null
}
function TamanhoTabela($ht) {
    $t = $ht
    try { $null = XG $t "ColumnCount" } catch { try { $t = @(X $ht "GetTableAnnotations")[0] } catch { } }
    $w = 0.0; $h = 0.0
    try { $nc = [int](XG $t "ColumnCount"); for ($c = 0; $c -lt $nc; $c++) { $w += [double](X $t "GetColumnWidth" $c) } } catch { }
    try { $nr = [int](XG $t "RowCount"); for ($r = 0; $r -lt $nr; $r++) { $h += [double](X $t "GetRowHeight" $r) } } catch { }
    if ($w -le 0.01) { $w = 0.11 }; if ($h -le 0.005) { $h = 0.08 }
    return [pscustomobject]@{ w = $w; h = $h }
}
# deixa a tabela de furos mais "achatada" (como no 02124106): texto menor e linhas mais baixas,
# até caber na altura/largura máxima; devolve o tamanho final
function AchatarTabela($dm, $ht, $maxW, $maxH) {
    $t = $ht
    try { $null = XG $t "ColumnCount" } catch { try { $t = @(X $ht "GetTableAnnotations")[0] } catch { } }
    $tam = TamanhoTabela $t
    if ($tam.w -le $maxW -and $tam.h -le $maxH) { return $tam }
    $h0 = 0.0
    try { $tf = X $t "GetTextFormat"; $h0 = [double](XG $tf "CharHeight") } catch { }
    if ($h0 -le 0) { $h0 = 0.0025 }
    $alt = $h0
    for ($k = 0; $k -lt 6; $k++) {
        $fat = [math]::Min($maxH / $tam.h, $maxW / $tam.w)
        if ($fat -ge 0.99) { break }
        $alt = [math]::Max(0.0015, $alt * [math]::Max(0.6, $fat * 0.97))
        try { $tf = X $t "GetTextFormat"; XS $tf "CharHeight" $alt; X $t "SetTextFormat" $false $tf | Out-Null } catch { Log "   [dbg] SetTextFormat: $($_.Exception.Message)" "DarkGray" }
        # linhas e colunas acompanham o texto
        try { $nr = [int](XG $t "RowCount"); for ($r = 0; $r -lt $nr; $r++) { $hr = [double](X $t "GetRowHeight" $r); X $t "SetRowHeight" $r ($hr * $alt / [math]::Max($h0, 1e-6) * 1.02) 0 | Out-Null } } catch { }
        try { $nc = [int](XG $t "ColumnCount"); for ($c = 0; $c -lt $nc; $c++) { $wc = [double](X $t "GetColumnWidth" $c); X $t "SetColumnWidth" $c ($wc * [math]::Max($alt / $h0, 0.75)) 0 | Out-Null } } catch { }
        $h0 = $alt
        Rebuild $dm
        $tam = TamanhoTabela $t
        if ($alt -le 0.0015) { break }
    }
    Log ("   Tabela de furos achatada: texto {0:N1} mm, {1:N0} x {2:N0} mm" -f ($alt * 1000), ($tam.w * 1000), ($tam.h * 1000)) "DarkGray"
    return $tam
}
function DetalharUsinagemTabela($dm, $front, $caminho, $peca) {
    # projeções em volta da principal
    $proj = @()
    foreach ($p in @(@(0.26, 0.15), @(-0.10, 0.15), @(0.08, 0.30), @(0.08, 0.02))) {
        try { Selecionar $dm $front | Out-Null; $v = X $dm "CreateUnfoldedViewAt3" ([double]$p[0]) ([double]$p[1]) 0.0 $false; if ($v) { $proj += ,$v } } catch { }
    }
    $iso = IsoDaFrontal $dm $caminho $front 0.25 0.30
    Modo $front $DispHidden $true
    foreach ($v in $proj) { Modo $v $DispHidden $true }
    if ($iso) { Modo $iso $DispShaded $true }
    Rebuild $dm
    # quem é quem (pela posição em relação à principal)
    $of = Contorno $front; $fcx = ($of.x1 + $of.x2) / 2; $fcy = ($of.y1 + $of.y2) / 2
    $dir = $null; $esq = $null; $cima = $null; $baixo = $null
    foreach ($v in $proj) {
        $o = Contorno $v; $cx = ($o.x1 + $o.x2) / 2; $cy = ($o.y1 + $o.y2) / 2
        if ([math]::Abs($cy - $fcy) -lt [math]::Abs($cx - $fcx)) { if ($cx -gt $fcx) { $dir = $v } else { $esq = $v } } else { if ($cy -gt $fcy) { $cima = $v } else { $baixo = $v } }
    }
    $nomesV = @(); if ($dir) { $nomesV += "direita" }; if ($esq) { $nomesV += "esquerda" }; if ($cima) { $nomesV += "cima" }; if ($baixo) { $nomesV += "baixo" }
    $txtIso = ""; if ($iso) { $txtIso = " + isométrica" }
    Log ("   Vistas: principal + " + ($nomesV -join ", ") + $txtIso)

    # 1) tabela de furos no canto inferior direito
    $ht = InserirTabelaFuros $dm $front
    $tam = if ($ht) { TamanhoTabela $ht } else { [pscustomobject]@{ w = 0.0; h = 0.0 } }
    if ($ht) { Log ("   Tabela de furos (original): {0:N0} x {1:N0} mm" -f ($tam.w * 1000), ($tam.h * 1000)) "DarkGray"; $tam = AchatarTabela $dm $ht 0.100 0.090 }
    $mesa = [pscustomobject]@{ x1 = 0.2917 - $tam.w; y1 = 0.0345; x2 = 0.2917; y2 = 0.0345 + $tam.h }
    if ($ht) { Log ("   Tabela de furos: {0:N0} x {1:N0} mm" -f ($tam.w * 1000), ($tam.h * 1000)) }

    # 2) escala: a maior em que a "cruz" de vistas cabe sem encostar na tabela; isométrica no canto de cima à direita
    $g = 0.020; $mc = 0.014   # espaço entre vistas / margem para cotas
    $esc0 = 1.0; try { $esc0 = [double](XG $front "ScaleDecimal") } catch { }
    # ponto de partida: tamanho do conjunto (em medida real) pela escala atual, começando um pouco acima
    $wTot = (Contorno $front).w; $hTot = (Contorno $front).h
    if ($esq) { $wTot += (Contorno $esq).w }; if ($dir) { $wTot += (Contorno $dir).w }
    if ($cima) { $hTot += (Contorno $cima).h }; if ($baixo) { $hTot += (Contorno $baixo).h }
    $i0 = [math]::Max(0, (EscalaInicial ($wTot / $esc0 * 1.15) ($hTot / $esc0 * 1.15)) - 2)
    $ok = $false
    for ($i = $i0; $i -lt $Escalas.Count -and -not $ok; $i++) {
        DefinirEscala $dm $Escalas[$i][0] $Escalas[$i][1]
        $of = Contorno $front
        $wE = if ($esq) { (Contorno $esq).w } else { 0 }; $hC = if ($cima) { (Contorno $cima).h } else { 0 }
        $fx = $AreaL + $mc + $(if ($esq) { $wE + $g + $mc } else { 0 })
        $fy = $AreaT - 0.006 - $(if ($cima) { $hC + $g + $mc } else { 0 }) - $mc
        MoverPara $front $fx $fy; Rebuild $dm
        $of = Contorno $front
        if ($esq) { $o = Contorno $esq; MoverPara $esq ($of.x1 - $mc - $g - $o.w) $o.y2 }
        if ($dir) { $o = Contorno $dir; MoverPara $dir ($of.x2 + $g) $o.y2 }
        if ($cima) { $o = Contorno $cima; MoverPara $cima $o.x1 ($of.y2 + $mc + $g + $o.h) }
        if ($baixo) { $o = Contorno $baixo; MoverPara $baixo $o.x1 ($of.y1 - $g) }
        Rebuild $dm
        $os = @(@($front, $esq, $dir, $cima, $baixo) | Where-Object { $_ } | ForEach-Object { Contorno $_ })
        $cabe = $true
        foreach ($o in $os) {
            if ($o.x1 -lt $AreaL + 0.004 -or $o.x2 -gt $AreaR - 0.006 -or $o.y1 -lt $AreaB + 0.004 -or $o.y2 -gt $AreaT - 0.004) { $cabe = $false }
            if ($ht -and (Bate $o $mesa 0.010)) { $cabe = $false }
        }
        if (-not $cabe) { continue }
        # isométrica: maior que couber no canto livre de cima à direita (sem encostar nas vistas e na tabela)
        if ($iso) {
            $sheetEsc = [double]$Escalas[$i][0] / $Escalas[$i][1]
            try { XS $iso "UseSheetScale" $false } catch { try { XS $iso "UseSheetScale" 0 } catch { } }
            $isoOk = $false
            # REGRA 28/10: mesma escala da principal (1.0) quando couber
            foreach ($fi in 1.0, 0.8, 0.65, 0.5, 0.4, 0.3) {
                try { XS $iso "ScaleDecimal" ($sheetEsc * $fi) } catch { }
                Rebuild $dm
                $oi = Contorno $iso
                MoverPara $iso ($AreaR - 0.006 - $oi.w) ($AreaT - 0.006); Rebuild $dm
                $oi = Contorno $iso
                $bate = $false
                foreach ($o in $os) { if (Bate $oi $o 0.012) { $bate = $true } }
                if ($ht -and (Bate $oi $mesa 0.008)) { $bate = $true }
                if (-not $bate) { $isoOk = $true; break }
            }
            if (-not $isoOk) { continue }
        }
        $ok = $true
        Log "   Escala $($Escalas[$i][0]):$($Escalas[$i][1])"
    }
    if (-not $ok) { Log "   Aviso: as vistas não couberam perfeitamente; confira a disposição." "Yellow" }
    $script:isoAtual = $iso

    # 3) cotas: totais na principal + raio; espessura na direita; posição e chamada dos furos que aparecem nas laterais
    if ($InserirCotas) {
        $tgl = K "swUserPreferenceToggle_e" @("swInputDimValOnCreate") 10
        $antes = $null
        try { $antes = X $sw "GetUserPreferenceToggle" $tgl; X $sw "SetUserPreferenceToggle" $tgl $false | Out-Null } catch { }
        try {
            $script:xfCache = @{}; $script:xfModo = @{}
            $n = 0
            $n += CotaTotal $dm $front $true $true
            if (-not $laser) { try { $n += CotasRaios $dm $front } catch { } }   # laser: contorno já sai pronto, não cota raio
            if ($dir) { $n += CotaTotal $dm $dir $true $false }
            $nl = 0
            foreach ($v in @($cima, $esq, $baixo, $dir)) {
                if (-not $v) { continue }
                $fv = @(); try { $fv = FurosDaVista $v } catch { }
                if ($fv.Count -eq 0) { continue }
                try { $nl += CotasPosicaoFuros $dm $v } catch { }
                try { $nl += ChamadasFuro $dm $v } catch { }
            }
            Log "   Cotas: $n totais/raio + $nl de furos das vistas laterais (os da principal estão na tabela)"
            Rebuild $dm
            ResolverSobreposicoes $dm @($front, $esq, $dir, $cima, $baixo, $iso) @("furo") @($mesa)
        } catch { Log "   Aviso: cotas falharam ($($_.Exception.Message))" "Yellow" }
        finally { if ($null -ne $antes) { try { X $sw "SetUserPreferenceToggle" $tgl ([bool]$antes) | Out-Null } catch { } } }
    }
}
