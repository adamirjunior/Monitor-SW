# Cotas.ps1 - transformação modelo->folha, cotas totais, furos, raios (usado por vários tipos)
# Carregado pelo DetalharSW.ps1 (dot-source). Não rodar sozinho.

# ---------------------------------------------------------------- processo / cotas
function TemUsinagem($peca) {
    foreach ($p in $PropsUsinagem) { if ($p -and (Prop $peca $p).Trim() -ne "") { return $true } }
    return $false
}
$script:mu = $null
$script:xfCache = @{}
$script:xfModo = @{}
# transformação modelo -> folha calculada aqui (MathUtility pela ponte COM devolvia sempre o mesmo ponto)
function DadosXf($v) {
    $nomeV = [string](X $v "GetName2")
    if (-not $script:xfCache.ContainsKey($nomeV)) { $script:xfCache[$nomeV] = XD (XG (XG $v "ModelToViewTransform") "ArrayData") }
    return $script:xfCache[$nomeV]
}
function AplicarXf($a, [double[]]$p, [int]$modo) {
    $rx = $p[0] * $a[0] + $p[1] * $a[3] + $p[2] * $a[6]
    $ry = $p[0] * $a[1] + $p[1] * $a[4] + $p[2] * $a[7]
    switch ($modo) {
        0 { return @(($rx * $a[12] + $a[9]), ($ry * $a[12] + $a[10])) }       # escala depois gira, + translação
        1 { return @((($rx + $a[9]) * $a[12]), (($ry + $a[10]) * $a[12])) }   # (gira + translação) * escala
        2 { $rx = $p[0] * $a[0] + $p[1] * $a[1] + $p[2] * $a[2]; $ry = $p[0] * $a[3] + $p[1] * $a[4] + $p[2] * $a[5]; return @(($rx * $a[12] + $a[9]), ($ry * $a[12] + $a[10])) }
        3 { $rx = $p[0] * $a[0] + $p[1] * $a[1] + $p[2] * $a[2]; $ry = $p[0] * $a[3] + $p[1] * $a[4] + $p[2] * $a[5]; return @((($rx + $a[9]) * $a[12]), (($ry + $a[10]) * $a[12])) }
    }
}
# escolhe a fórmula que coloca os pontos dentro do contorno da vista
function EscolherModoXf($v, $pontosModelo) {
    $nomeV = [string](X $v "GetName2")
    if ($script:xfModo.ContainsKey($nomeV)) { return $script:xfModo[$nomeV] }
    $a = DadosXf $v; $o = Contorno $v; $melhor = 0; $melhorQtd = -1
    foreach ($m in 0, 1, 2, 3) {
        $dentro = 0
        foreach ($pm in $pontosModelo) { $q = AplicarXf $a $pm $m; if ($q[0] -ge $o.x1 - 0.002 -and $q[0] -le $o.x2 + 0.002 -and $q[1] -ge $o.y1 - 0.002 -and $q[1] -le $o.y2 + 0.002) { $dentro++ } }
        if ($dentro -gt $melhorQtd) { $melhorQtd = $dentro; $melhor = $m }
    }
    Log "   [dbg] $nomeV : fórmula $melhor ($melhorQtd de $($pontosModelo.Count) pontos dentro do contorno)" "DarkGray"
    $script:xfModo[$nomeV] = $melhor
    return $melhor
}
function Rot($a, [double[]]$p) {
    return @(($p[0] * $a[0] + $p[1] * $a[3] + $p[2] * $a[6]), ($p[0] * $a[1] + $p[1] * $a[4] + $p[2] * $a[7]))
}
function NaFolha($v, [double[]]$pt) {
    $nomeV = [string](X $v "GetName2")
    $m = if ($script:xfModo.ContainsKey($nomeV)) { $script:xfModo[$nomeV] } else { 0 }
    return AplicarXf (DadosXf $v) $pt $m
}
function Entidades($v, [string]$tipo, [int]$padrao) {
    $t = K "swViewEntityType_e" @($tipo) $padrao
    $r = X $v "GetVisibleEntities2" ([SwCom]::NullDisp()) $t
    if (-not $r) { return @() }
    return @($r)
}
function SelecionarEntidade($dm, $v, $ent, [bool]$somar) {
    try {
        $sd = X (XG $dm "SelectionManager") "CreateSelectData"
        XS $sd "View" $v
        if (X $ent "Select4" $somar $sd) { return $true }
    } catch { }
    try { if (X $v "SelectEntity" $ent $somar) { return $true } } catch { }
    return $false
}
# cota total horizontal (acima da vista) e/ou vertical (à esquerda) entre os vértices extremos
function QtdSelecionados($dm) { try { return [int](X (XG $dm "SelectionManager") "GetSelectedObjectCount2" -1) } catch { return 0 } }
function CotaEntre($dm, $v, $a, $b, $x, $y, [string]$nome) {
    $metodo = if ($nome -eq "horizontal") { "AddHorizontalDimension2" } else { "AddVerticalDimension2" }
    X $dm "ClearSelection2" $true | Out-Null
    $s1 = SelecionarEntidade $dm $v $a[0] $false; $s2 = SelecionarEntidade $dm $v $b[0] $true
    $q = QtdSelecionados $dm
    if ($q -ne 2) { Log "   (cota $nome de $(X $v 'GetName2') não feita: $q selecionado(s))" "DarkYellow"; return 0 }
    try { $d = X $dm $metodo ([double]$x) ([double]$y) 0.0; if ($d) { return 1 } } catch { Log "   ($metodo falhou: $($_.Exception.Message))" "DarkYellow" }
    Log "   (cota $nome de $(X $v 'GetName2'): o SolidWorks não criou)" "DarkYellow"
    return 0
}
function CotaTotal($dm, $v, [bool]$horiz, [bool]$vert, [double]$folgaH = 0) {
    $verts = Entidades $v "swViewEntityType_Vertex" 2
    if ($verts.Count -lt 2) { return (CotaTotalSemVertices $dm $v $horiz $vert) }
    $modelo = @(); $okVerts = @()
    foreach ($vx in $verts) { try { $modelo += ,([double[]](XD (X $vx "GetPoint"))); $okVerts += $vx } catch { } }
    if ($modelo.Count -lt 2) { return 0 }
    # para achar os extremos basta a rotação da vista (escala e translação não mudam a ordem)
    $a0 = DadosXf $v
    $pts = @()
    for ($k = 0; $k -lt $modelo.Count; $k++) { $pts += ,@($okVerts[$k], (Rot $a0 $modelo[$k])) }
    $o = Contorno $v; $n = 0
    # caixa real da peça na folha: o contorno da vista tem folga em volta; tamanho real = medida rotacionada x escala,
    # e a folga é igual dos dois lados (assim a cota fica a $DistCota da peça e não do contorno)
    $cx1 = $o.x1; $cx2 = $o.x2; $cy1 = $o.y1; $cy2 = $o.y2
    try {
        $esc = [double](XG $v "ScaleDecimal")
        $rx = @($pts | ForEach-Object { $_[1][0] }); $ry = @($pts | ForEach-Object { $_[1][1] })
        $w = (($rx | Measure-Object -Maximum).Maximum - ($rx | Measure-Object -Minimum).Minimum) * $esc
        $h = (($ry | Measure-Object -Maximum).Maximum - ($ry | Measure-Object -Minimum).Minimum) * $esc
        $fx = (($o.x2 - $o.x1) - $w) / 2; $fy = (($o.y2 - $o.y1) - $h) / 2
        if ($fx -gt 0 -and $fx -lt 0.05) { $cx1 = $o.x1 + $fx; $cx2 = $o.x2 - $fx }
        if ($fy -gt 0 -and $fy -lt 0.05) { $cy1 = $o.y1 + $fy; $cy2 = $o.y2 - $fy }
    } catch { }
    # extremo de verdade: só vértices a menos de 0,02 mm do extremo (com 0,2 mm pegava o fim do arco da dobra: 26,82 em vez de 27)
    $tol = 0.00002
    if ($horiz) {
        # extremos em X; entre vértices empatados usa o mais alto (linha de chamada curta até a cota em cima)
        $minX = ($pts | ForEach-Object { $_[1][0] } | Measure-Object -Minimum).Minimum
        $maxX = ($pts | ForEach-Object { $_[1][0] } | Measure-Object -Maximum).Maximum
        $a = @($pts | Where-Object { $_[1][0] -le $minX + $tol } | Sort-Object { $_[1][1] })[-1]
        $b = @($pts | Where-Object { $_[1][0] -ge $maxX - $tol } | Sort-Object { $_[1][1] })[-1]
        if ([math]::Abs($maxX - $minX) -gt 0.001) { $n += CotaEntre $dm $v $a $b (($cx1 + $cx2) / 2) ($cy2 + $DistCota + $folgaH) "horizontal" }
    }
    if ($vert) {
        # extremos em Y; entre vértices empatados usa o mais à esquerda (cota fica à esquerda)
        $minY = ($pts | ForEach-Object { $_[1][1] } | Measure-Object -Minimum).Minimum
        $maxY = ($pts | ForEach-Object { $_[1][1] } | Measure-Object -Maximum).Maximum
        $a = @($pts | Where-Object { $_[1][1] -le $minY + $tol } | Sort-Object { $_[1][0] })[0]
        $b = @($pts | Where-Object { $_[1][1] -ge $maxY - $tol } | Sort-Object { $_[1][0] })[0]
        if ([math]::Abs($maxY - $minY) -gt 0.001) { $n += CotaEntre $dm $v $a $b ($cx1 - $DistCota) (($cy1 + $cy2) / 2) "vertical" }
    }
    X $dm "ClearSelection2" $true | Out-Null
    if ($n -eq 0 -and ($horiz -or $vert)) { Log ("   (vista {0}: cota total não saiu - {1} vértice(s))" -f (X $v 'GetName2'), $verts.Count) "DarkYellow" }
    return $n
}
# peça redonda (arruela, disco, bucha vista de lado...): não tem cantos. Cota o diâmetro dos círculos
# e/ou a distância entre as linhas retas extremas (aresta de silhueta não tem vértice)
function CotaTotalSemVertices($dm, $v, [bool]$horiz, [bool]$vert) {
    $a = DadosXf $v; $o = Contorno $v; $n = 0
    $circ = @(); $lin = @()
    foreach ($e in (Entidades $v "swViewEntityType_Edge" 1)) {
        try {
            $c = X $e "GetCurve"
            if (X $c "IsCircle") {
                $sv = $null; try { $sv = X $e "GetStartVertex" } catch { }
                if ($sv) { continue }
                $cp = XD (XG $c "CircleParams")
                $eixo = Rot $a @($cp[3], $cp[4], $cp[5])
                if ([math]::Abs($eixo[0]) -gt 0.05 -or [math]::Abs($eixo[1]) -gt 0.05) { continue }
                $pc = Rot $a @($cp[0], $cp[1], $cp[2])
                $circ += ,@($e, [math]::Round($cp[6] * 2000, 3), ($pc[0] + $pc[1]))
            } elseif (X $c "IsLine") {
                $cpp = XD (X $e "GetCurveParams2")
                $p1 = Rot $a @($cpp[0], $cpp[1], $cpp[2]); $p2 = Rot $a @($cpp[3], $cpp[4], $cpp[5])
                if ([math]::Abs($p1[0] - $p2[0]) -lt 1e-6) { $lin += ,@($e, 0, $p1[0]) }
                elseif ([math]::Abs($p1[1] - $p2[1]) -lt 1e-6) { $lin += ,@($e, 1, $p1[1]) }
            }
        } catch { }
    }
    # diâmetros: um de cada tamanho (externo e furo)
    $feitos = @{}; $k = 0
    # de cada diâmetro, cota o círculo mais perto do canto superior direito (onde fica o texto): linha de chamada curta
    foreach ($ci in ($circ | Sort-Object { -$_[1] }, { -$_[2] })) {
        if ($feitos.ContainsKey($ci[1])) { continue }
        X $dm "ClearSelection2" $true | Out-Null
        if (-not (SelecionarEntidade $dm $v $ci[0] $false)) { continue }
        $tx = $o.x2 + 0.008 + $k * 0.004; $ty = $o.y2 + 0.006 + $k * 0.008
        $d = $null; try { $d = X $dm "AddDiameterDimension2" ([double]$tx) ([double]$ty) 0.0 } catch { }
        if ($d) { $feitos[$ci[1]] = 1; $n++; $k++ }
    }
    # linhas retas extremas (ex.: espessura da arruela vista de lado)
    foreach ($eixo in 0, 1) {
        if (($eixo -eq 0 -and -not $horiz) -or ($eixo -eq 1 -and -not $vert)) { continue }
        $ls = @($lin | Where-Object { $_[1] -eq $eixo } | Sort-Object { $_[2] })
        if ($ls.Count -lt 2) { continue }
        if ([math]::Abs($ls[-1][2] - $ls[0][2]) -lt 0.0005) { continue }
        if ($circ.Count -gt 0 -and $feitos.Count -gt 0) {
            # a medida já está no diâmetro? (vista de frente de peça redonda)
            $tam = [math]::Round([math]::Abs($ls[-1][2] - $ls[0][2]) * 1000, 3)
            if ($feitos.ContainsKey($tam)) { continue }
        }
        X $dm "ClearSelection2" $true | Out-Null
        SelecionarEntidade $dm $v $ls[0][0] $false | Out-Null; SelecionarEntidade $dm $v $ls[-1][0] $true | Out-Null
        if ((QtdSelecionados $dm) -ne 2) { continue }
        $d = $null
        try {
            if ($eixo -eq 0) { $d = X $dm "AddHorizontalDimension2" ([double](($o.x1 + $o.x2) / 2)) ([double]($o.y2 + $DistCota)) 0.0 }
            else { $d = X $dm "AddVerticalDimension2" ([double]($o.x1 - $DistCota)) ([double](($o.y1 + $o.y2) / 2)) 0.0 }
        } catch { }
        if ($d) { $n++ }
    }
    X $dm "ClearSelection2" $true | Out-Null
    if ($n -eq 0) { Log "   (vista $(X $v 'GetName2'): sem cantos nem círculos para cotar)" "DarkYellow" }
    else { Log "   (vista $(X $v 'GetName2'): peça sem cantos - $n cota(s) por diâmetro/linhas)" "DarkGray" }
    return $n
}
# chamada de furo (ex.: 2x Ø4,30 PASSANTE) - uma por diâmetro
function FuroDoAssistente($e) {
    # o recurso dono das faces vizinhas da aresta diz se o furo veio do Assistente de Furação
    try {
        $faces = X $e "GetTwoAdjacentFaces2"
        foreach ($f in @($faces)) {
            if (-not $f) { continue }
            $ft = X $f "GetFeature"
            if ($ft) { $t = [string](X $ft "GetTypeName2"); if ($t -match "(?i)HoleWzd|HoleSeries|AdvHole|CosmeticThread") { return $true } }
        }
    } catch { }
    return $false
}
function ChamadasFuro($dm, $v) {
    $edges = Entidades $v "swViewEntityType_Edge" 1
    $a = DadosXf $v
    $circ = @()
    foreach ($e in $edges) {
        try {
            $c = X $e "GetCurve"
            if (-not (X $c "IsCircle")) { continue }
            $sv = $null; try { $sv = X $e "GetStartVertex" } catch { }
            if ($sv) { continue }   # arco (raio/dobra), não furo
            $cp = XD (XG $c "CircleParams")
            $eixo = Rot $a @($cp[3], $cp[4], $cp[5])
            if ([math]::Abs($eixo[0]) -gt 0.05 -or [math]::Abs($eixo[1]) -gt 0.05) { continue }   # só furo visto de frente
            $diam = [math]::Round($cp[6] * 2000, 2)
            if ($diam -gt 40) { continue }
            $circ += ,@($e, $diam, (Rot $a @($cp[0], $cp[1], $cp[2])))
        } catch { }
    }
    # do menor para o maior; círculo concêntrico a um menor (escareado/rebaixo/rosca) não ganha chamada própria
    $circ = @($circ | Sort-Object { $_[1] })
    $mantidos = @(); $diams = @{}; $qtd = @{}
    foreach ($ci in $circ) {
        $conc = $false
        foreach ($m in $mantidos) { if ([math]::Abs($m[2][0] - $ci[2][0]) -lt 0.0003 -and [math]::Abs($m[2][1] - $ci[2][1]) -lt 0.0003) { $conc = $true; break } }
        if ($conc) { continue }
        $mantidos += ,$ci
        if (-not $diams.ContainsKey($ci[1])) { $diams[$ci[1]] = $ci[0] }
        $qtd[$ci[1]] = 1 + [int]$qtd[$ci[1]]
    }
    $o = Contorno $v; $n = 0
    $total = $diams.Count
    $abaixo = (($o.y1 - $AreaB) -gt 0.03)
    foreach ($d in ($diams.Keys | Sort-Object)) {
        try {
            X $dm "ClearSelection2" $true | Out-Null
            if (-not (SelecionarEntidade $dm $v $diams[$d] $false)) { Log "   (não consegui selecionar o furo Ø$d)" "DarkYellow"; continue }
            # chamadas lado a lado embaixo da vista (cada uma ocupa ~6 cm), ou empilhadas à direita com folga
            if ($abaixo) { $tx = [math]::Min($o.x1 + 0.03 + ($n * 0.065), $AreaR - 0.03); $ty = [math]::Max($o.y1 - 0.014, $AreaB + 0.016) }
            else { $tx = [math]::Min($o.x2 + 0.022, $AreaR - 0.05); $ty = $o.y2 - ($n * 0.020) }
            $hc = $null
            # furo do Assistente de Furação ganha a chamada do SolidWorks (tem quantidade/rosca/escareado);
            # furo feito por corte/extrusão vai direto como nota no padrão ProEstamp
            if (FuroDoAssistente $diams[$d]) { try { $hc = X $dm "AddHoleCallout2" $tx $ty 0.0 } catch { } }
            # furo feito por corte simples: o SolidWorks escreve "Ø8,50 THRU" sem quantidade.
            # Troca por uma nota com seta no padrão ProEstamp: "4 x Ø8,50 PASSANTE"
            # texto da chamada: IDisplayDimension.GetText(parte) — junta todas as partes para achar o THRU
            $txtHc = ""
            if ($hc) { foreach ($pt in @(1, 2, 3, 4, 5)) { try { $txtHc += " " + [string](X $hc "GetText" $pt) } catch { } } }
            $ehNota = $false
            if (-not $hc -or ($txtHc -match "(?i)THRU" -and $txtHc -notmatch "(?i)<NUM_INST>|<hw")) {
                # chamada de furo feito por corte: troca por nota com seta no padrão ProEstamp ("4 x Ø8,50 PASSANTE")
                try {
                    if ($hc) { X $dm "ClearSelection2" $true | Out-Null; $an = AnnOf $hc; $sel = $false; try { $sel = X $an "Select2" $false 0 } catch { }; if (-not $sel) { try { X $an "Select3" $false ([SwCom]::NullDisp()) | Out-Null } catch { } }; X $dm "EditDelete" | Out-Null }
                    X $dm "ClearSelection2" $true | Out-Null
                    SelecionarEntidade $dm $v $diams[$d] $false | Out-Null
                    $q = [int]$qtd[$d]
                    $texto = $(if ($q -gt 1) { "$q x " } else { "" }) + "<MOD-DIAM>" + ([double]$d).ToString("0.00") + " PASSANTE"
                    $nt = X $dm "InsertNote" $texto
                    if ($nt) { X (AnnOf $nt) "SetPosition" $tx $ty 0.0 | Out-Null; $hc = $nt; $ehNota = $true; Log "   (chamada do furo Ø$d escrita como nota: $texto)" "DarkGray" }
                } catch { Log "   (não consegui trocar a chamada do furo: $($_.Exception.Message))" "DarkYellow" }
            } elseif ($hc) { Log "   (texto da chamada: $($txtHc.Trim()))" "DarkGray" }
            if ($hc) {
                $n++; $script:chamadas += ,@($hc, $v)
                # padrão ProEstamp: "4 x Ø8,50 PASSANTE" (furo feito por corte sai "Ø8,50 THRU", sem quantidade)
                if (-not $ehNota) { try {
                    $txt = [string](X $hc "GetText" 1)
                    $novo = $txt -replace "(?i)\bTHRU ALL\b", "PASSANTE TOTAL" -replace "(?i)\bTHRU\b", "PASSANTE"
                    if ($qtd[$d] -gt 1 -and $novo -notmatch "^\s*(<NUM_INST>|\d+\s*[xX])") { $novo = "$($qtd[$d]) x " + $novo }
                    if ($novo -ne $txt) { X $hc "SetText" 1 $novo | Out-Null }
                } catch { } }
                Log "   Furo Ø${d} ($($qtd[$d])x): chamada inserida" "DarkGray"
            }
        } catch { }
    }
    X $dm "ClearSelection2" $true | Out-Null
    return $n
}
# ---------------------------------------------------------------- cotas de peça usinada (padrão ProEstamp, ex.: 02115187)
# totais (comprimento em cima, altura à esquerda, espessura na vista de baixo), posição dos furos, raios e chamada de furo
function CotasUsinagem($dm, $front, $top) {
    $tgl = K "swUserPreferenceToggle_e" @("swInputDimValOnCreate") 10
    $antes = $null
    try { $antes = X $sw "GetUserPreferenceToggle" $tgl; X $sw "SetUserPreferenceToggle" $tgl $false | Out-Null } catch { }
    try {
        $script:xfCache = @{}; $script:xfModo = @{}
        $n = 0
        if ($front) {
            $pm = @(); foreach ($vx in (Entidades $front "swViewEntityType_Vertex" 2)) { try { $pm += ,([double[]](XD (X $vx "GetPoint"))) } catch { } }
            if ($pm.Count -gt 0) { EscolherModoXf $front $pm | Out-Null }
        }
        if ($front) { $n += CotaTotal $dm $front $true $true }
        if ($top) { $n += CotaTotal $dm $top $false $true }
        $p = 0; $r = 0; $f = 0
        if ($front) {
            try { $p = CotasPosicaoFuros $dm $front } catch { Log "   (posição dos furos: $($_.Exception.Message))" "DarkYellow" }
            try { $r = CotasRaios $dm $front } catch { Log "   (raios: $($_.Exception.Message))" "DarkYellow" }
            try { $f = ChamadasFuro $dm $front } catch { Log "   (chamada de furo: $($_.Exception.Message))" "DarkYellow" }
        }
        Log "   Cotas de usinagem: $n totais + $p de posição de furo + $r raio(s) + $f chamada(s) de furo"
        Rebuild $dm
        ResolverSobreposicoes $dm @($front, $top, $script:isoAtual) @("furo")
    } finally { if ($null -ne $antes) { try { X $sw "SetUserPreferenceToggle" $tgl ([bool]$antes) | Out-Null } catch { } } }
}
# furos vistos de frente: [aresta, diâmetro mm, centro girado (x,y)] - só o menor de cada centro (rebaixo/escareado fica de fora)
function FurosDaVista($v) {
    $a = DadosXf $v
    $circ = @()
    foreach ($e in (Entidades $v "swViewEntityType_Edge" 1)) {
        try {
            $c = X $e "GetCurve"
            if (-not (X $c "IsCircle")) { continue }
            $sv = $null; try { $sv = X $e "GetStartVertex" } catch { }
            if ($sv) { continue }
            $cp = XD (XG $c "CircleParams")
            $eixo = Rot $a @($cp[3], $cp[4], $cp[5])
            if ([math]::Abs($eixo[0]) -gt 0.05 -or [math]::Abs($eixo[1]) -gt 0.05) { continue }
            $circ += ,@($e, [math]::Round($cp[6] * 2000, 2), (Rot $a @($cp[0], $cp[1], $cp[2])), [double[]]@($cp[0], $cp[1], $cp[2]))
        } catch { }
    }
    $circ = @($circ | Sort-Object { $_[1] })
    $res = @()
    foreach ($ci in $circ) {
        $conc = $false
        foreach ($m in $res) { if ([math]::Abs($m[2][0] - $ci[2][0]) -lt 0.0003 -and [math]::Abs($m[2][1] - $ci[2][1]) -lt 0.0003) { $conc = $true; break } }
        if (-not $conc) { $res += ,$ci }
    }
    return ,$res
}
# posição dos furos: se estão simétricos no eixo, cota só a distância entre os extremos; senão, cota cada posição a partir da borda.
# O texto da cota fica no meio da linha de cota (meio entre os dois pontos medidos, já na folha).
function MeioFolha($v, [double[]]$p1, [double[]]$p2) {
    $q1 = NaFolha $v $p1; $q2 = NaFolha $v $p2
    return @((($q1[0] + $q2[0]) / 2), (($q1[1] + $q2[1]) / 2))
}
function CotasPosicaoFuros($dm, $v) {
    $furos = FurosDaVista $v
    if ($furos.Count -eq 0) { return 0 }
    $a = DadosXf $v
    $pts = @()
    foreach ($vx in (Entidades $v "swViewEntityType_Vertex" 2)) { try { $pm = [double[]](XD (X $vx "GetPoint")); $pts += ,@($vx, (Rot $a $pm), $pm) } catch { } }
    if ($pts.Count -lt 2) { return 0 }
    EscolherModoXf $v @($pts | ForEach-Object { ,$_[2] }) | Out-Null
    # limites reais da peça (caixa do modelo girada como a vista); os vértices visíveis podem não chegar nos cantos arredondados
    $cb = $script:caixaPeca; $lim = @(@(1e9, -1e9), @(1e9, -1e9))
    if ($cb) {
        foreach ($cx in $cb[0], $cb[3]) { foreach ($cy in $cb[1], $cb[4]) { foreach ($cz in $cb[2], $cb[5]) {
            $r = Rot $a @($cx, $cy, $cz)
            for ($i = 0; $i -lt 2; $i++) { $lim[$i][0] = [math]::Min($lim[$i][0], $r[$i]); $lim[$i][1] = [math]::Max($lim[$i][1], $r[$i]) }
        } } }
    }
    $o = Contorno $v; $n = 0; $tol = 0.0002; $passo = 0.008
    foreach ($eixo in 0, 1) {
        $vals = @($pts | ForEach-Object { $_[1][$eixo] })
        $min = ($vals | Measure-Object -Minimum).Minimum; $max = ($vals | Measure-Object -Maximum).Maximum
        if ($cb) { $min = $lim[$eixo][0]; $max = $lim[$eixo][1] }
        $meio = ($min + $max) / 2
        $pos = @()
        foreach ($h in ($furos | Sort-Object { $_[2][$eixo] })) { if (-not ($pos | Where-Object { [math]::Abs($_[2][$eixo] - $h[2][$eixo]) -lt $tol })) { $pos += ,$h } }
        $sim = $true
        foreach ($h in $pos) { $esp = 2 * $meio - $h[2][$eixo]; if (-not ($pos | Where-Object { [math]::Abs($_[2][$eixo] - $esp) -lt 0.0003 })) { $sim = $false; break } }
        $nome = if ($eixo -eq 0) { "horizontal" } else { "vertical" }
        Log ("   [dbg] furos eixo {0}: posições {1} mm (peça {2:N1}..{3:N1}) simétrico={4}" -f $nome, (($pos | ForEach-Object { "{0:N1}" -f (($_[2][$eixo] - $min) * 1000) }) -join ", "), 0, (($max - $min) * 1000), $sim) "DarkGray"
        $metodo = if ($eixo -eq 0) { "AddHorizontalDimension2" } else { "AddVerticalDimension2" }
        $k = 0
        if ($sim) {
            if ($pos.Count -lt 2) { continue }   # furo(s) no centro: não precisa cota
            X $dm "ClearSelection2" $true | Out-Null
            SelecionarEntidade $dm $v $pos[0][0] $false | Out-Null; SelecionarEntidade $dm $v $pos[-1][0] $true | Out-Null
            if ((QtdSelecionados $dm) -ne 2) { continue }
            $mf = MeioFolha $v $pos[0][3] $pos[-1][3]
            if ($eixo -eq 0) { $x = $mf[0]; $y = $o.y2 + $DistCota + $passo } else { $x = $o.x2 + $DistCota; $y = $mf[1] }
            try { if (X $dm $metodo ([double]$x) ([double]$y) 0.0) { $n++ } } catch { }
        } else {
            # a partir da borda de menor coordenada (esquerda / baixo)
            $borda = @($pts | Sort-Object { $_[1][$eixo] })[0]
            foreach ($h in $pos) {
                X $dm "ClearSelection2" $true | Out-Null
                SelecionarEntidade $dm $v $borda[0] $false | Out-Null; SelecionarEntidade $dm $v $h[0] $true | Out-Null
                if ((QtdSelecionados $dm) -ne 2) { continue }
                $mf = MeioFolha $v $borda[2] $h[3]
                # horizontais em cima (além da cota total), verticais à direita; uma afastada da outra
                if ($eixo -eq 0) { $x = $mf[0]; $y = $o.y2 + $DistCota + ($k + 1) * $passo } else { $x = $o.x2 + $DistCota + $k * $passo; $y = $mf[1] }
                try { if (X $dm $metodo ([double]$x) ([double]$y) 0.0) { $n++; $k++ } } catch { }
            }
        }
    }
    X $dm "ClearSelection2" $true | Out-Null
    return $n
}
# um raio de cada tamanho nos cantos arredondados do contorno
function CotasRaios($dm, $v, [bool]$soMenor = $false) {
    $a = DadosXf $v; $o = Contorno $v; $n = 0
    $feitos = @{}
    $cx = ($o.x1 + $o.x2) / 2; $cy = ($o.y1 + $o.y2) / 2
    $arcos = @()
    foreach ($e in (Entidades $v "swViewEntityType_Edge" 1)) {
        try { $c0 = X $e "GetCurve"; if (X $c0 "IsCircle") { $arcos += ,@($e, [double]((XD (XG $c0 "CircleParams"))[6])) } } catch { }
    }
    $arcos = @($arcos | Sort-Object { $_[1] })   # do menor para o maior (raio interno da dobra primeiro)
    foreach ($ar in $arcos) {
        $e = $ar[0]
        if ($soMenor -and $n -gt 0) { break }
        try {
            $c = X $e "GetCurve"
            if (-not (X $c "IsCircle")) { continue }
            $sv = $null; try { $sv = X $e "GetStartVertex" } catch { }
            if (-not $sv) { continue }   # círculo inteiro = furo
            $cp = XD (XG $c "CircleParams")
            $eixo = Rot $a @($cp[3], $cp[4], $cp[5])
            if ([math]::Abs($eixo[0]) -gt 0.05 -or [math]::Abs($eixo[1]) -gt 0.05) { continue }
            $rmm = [math]::Round($cp[6] * 1000, 2)
            if ($rmm -lt 0.5 -or $feitos.ContainsKey($rmm)) { continue }
            # ponto do arco na folha (vértice inicial) para saber para que lado puxar a cota
            $pv = [double[]](XD (X $sv "GetPoint"))
            $q = NaFolha $v $pv
            $dx = $q[0] - $cx; $dy = $q[1] - $cy; $len = [math]::Sqrt($dx * $dx + $dy * $dy); if ($len -lt 1e-6) { $len = 1 }
            X $dm "ClearSelection2" $true | Out-Null
            if (-not (SelecionarEntidade $dm $v $e $false)) { continue }
            $tx = $q[0] + $dx / $len * 0.012; $ty = $q[1] + $dy / $len * 0.008
            # nunca fora da folha: no máximo um pouco além da vista
            $tx = [math]::Max($o.x1 - 0.015, [math]::Min($o.x2 + 0.015, $tx)); $ty = [math]::Max($o.y1 - 0.010, [math]::Min($o.y2 + 0.010, $ty))
            $d = $null; try { $d = X $dm "AddRadialDimension2" ([double]$tx) ([double]$ty) 0.0 } catch { }
            if ($d) { $feitos[$rmm] = 1; $n++ }
        } catch { }
    }
    X $dm "ClearSelection2" $true | Out-Null
    return $n
}

# texto de TODAS as cotas do desenho no centro da linha de cota (entre as linhas de chamada)
function CentralizarTextosCotas($dm) {
    $n = 0
    try {
        $v = X (X $dm "GetFirstView") "GetNextView"
        while ($v) {
            $dd = $null; try { $dd = X $v "GetFirstDisplayDimension5" } catch { }
            $g = 0
            while ($dd -and $g -lt 200) { $g++; try { XS $dd "CenterText" $true; $n++ } catch { }; $dd = X $dd "GetNext5" }
            $v = X $v "GetNextView"
        }
    } catch { Log "   (não consegui centralizar o texto das cotas: $($_.Exception.Message))" "DarkYellow" }
    if ($n -gt 0) { Rebuild $dm; Log "   Texto de $n cota(s) centralizado na linha de cota" "DarkGray" }
}

# ---------------------------------------------------------------- oblongos (rasgos) vistos de frente
# par de arcos de meia-volta com o mesmo raio e centros diferentes = oblongo. Devolve @(arco1, arco2, raio, centro1, centro2)
function OblongosDaVista($v) {
    $a = DadosXf $v
    $arcos = @()
    foreach ($e in (Entidades $v "swViewEntityType_Edge" 1)) {
        try {
            $c = X $e "GetCurve"; if (-not (X $c "IsCircle")) { continue }
            $gp = [double[]](XD (X $e "GetCurveParams2"))
            $cp = [double[]](XD (XG $c "CircleParams"))
            $eixo = Rot $a @($cp[3], $cp[4], $cp[5])
            if ([math]::Abs($eixo[0]) -gt 0.05 -or [math]::Abs($eixo[1]) -gt 0.05) { continue }   # visto de frente
            $corda = [math]::Sqrt([math]::Pow($gp[0] - $gp[3], 2) + [math]::Pow($gp[1] - $gp[4], 2) + [math]::Pow($gp[2] - $gp[5], 2))
            if ([math]::Abs($corda - 2 * $cp[6]) -gt 0.0002) { continue }   # meia-volta: as pontas ficam a 2R
            $arcos += ,@($e, $cp)
        } catch { }
    }
    $res = @(); $usado = @{}
    for ($i = 0; $i -lt $arcos.Count; $i++) {
        if ($usado[$i]) { continue }
        for ($j = $i + 1; $j -lt $arcos.Count; $j++) {
            if ($usado[$j]) { continue }
            $p = $arcos[$i][1]; $q = $arcos[$j][1]
            $d = [math]::Sqrt([math]::Pow($p[0] - $q[0], 2) + [math]::Pow($p[1] - $q[1], 2) + [math]::Pow($p[2] - $q[2], 2))
            if ([math]::Abs($p[6] - $q[6]) -lt 0.00002 -and $d -gt 0.0003) {
                $res += ,@($arcos[$i][0], $arcos[$j][0], $p[6], [double[]]@($p[0], $p[1], $p[2]), [double[]]@($q[0], $q[1], $q[2]))
                $usado[$i] = $true; $usado[$j] = $true; break
            }
        }
    }
    return ,$res
}
# oblongo: raio (largura), distância entre centros (comprimento) e posição do 1º centro a partir das bordas da vista
function CotasOblongo($dm, $v) {
    if (-not $v) { return 0 }
    $pm = @(); $vts = @()
    foreach ($vx in (Entidades $v "swViewEntityType_Vertex" 2)) { try { $pt = [double[]](XD (X $vx "GetPoint")); $pm += ,$pt; $vts += ,@($vx, $pt) } catch { } }
    if ($pm.Count -gt 0) { EscolherModoXf $v $pm | Out-Null }
    $obl = OblongosDaVista $v
    if ($obl.Count -eq 0) { return 0 }
    $o = Contorno $v; $n = 0
    $vf = @($vts | ForEach-Object { ,@($_[0], (NaFolha $v $_[1])) })
    foreach ($ob in $obl) {
        $c1 = NaFolha $v $ob[3]; $c2 = NaFolha $v $ob[4]
        $horiz = [math]::Abs($c2[0] - $c1[0]) -ge [math]::Abs($c2[1] - $c1[1])
        # 1) raio do oblongo (largura = 2R), puxado para fora do lado do 1º arco
        try {
            X $dm "ClearSelection2" $true | Out-Null
            if (SelecionarEntidade $dm $v $ob[0] $false) {
                $ux = $c1[0] - $c2[0]; $uy = $c1[1] - $c2[1]; $lu = [math]::Sqrt($ux * $ux + $uy * $uy); if ($lu -lt 1e-7) { $lu = 1 }
                $tx = $c1[0] + $ux / $lu * 0.010; $ty = $c1[1] + $uy / $lu * 0.010 + 0.004
                if (X $dm "AddRadialDimension2" ([double]$tx) ([double]$ty) 0.0) { $n++ }
            }
        } catch { }
        # 2) comprimento: centro a centro
        try {
            X $dm "ClearSelection2" $true | Out-Null
            SelecionarEntidade $dm $v $ob[0] $false | Out-Null; SelecionarEntidade $dm $v $ob[1] $true | Out-Null
            if ((QtdSelecionados $dm) -eq 2) {
                if ($horiz) { $r = X $dm "AddHorizontalDimension2" ([double](($c1[0] + $c2[0]) / 2)) ([double]([math]::Max($c1[1], $c2[1]) + 0.008)) 0.0 }
                else { $r = X $dm "AddVerticalDimension2" ([double]([math]::Max($c1[0], $c2[0]) + 0.008)) ([double](($c1[1] + $c2[1]) / 2)) 0.0 }
                if ($r) { $n++ }
            }
        } catch { }
        # 3) posição: do canto inferior esquerdo da vista até o centro do arco mais à esquerda/baixo
        $cb = if (($c1[0] + $c1[1]) -le ($c2[0] + $c2[1])) { @($ob[0], $c1) } else { @($ob[1], $c2) }
        foreach ($eixo in 0, 1) {
            $borda = @($vf | Sort-Object { $_[1][$eixo] })[0]
            if (-not $borda) { continue }
            try {
                X $dm "ClearSelection2" $true | Out-Null
                SelecionarEntidade $dm $v $borda[0] $false | Out-Null; SelecionarEntidade $dm $v $cb[0] $true | Out-Null
                if ((QtdSelecionados $dm) -ne 2) { continue }
                if ($eixo -eq 0) { $r = X $dm "AddHorizontalDimension2" ([double](($borda[1][0] + $cb[1][0]) / 2)) ([double]($o.y1 - $DistCota)) 0.0 }
                else { $r = X $dm "AddVerticalDimension2" ([double]($o.x1 - $DistCota)) ([double](($borda[1][1] + $cb[1][1]) / 2)) 0.0 }
                if ($r) { $n++ }
            } catch { }
        }
        Log ("   Oblongo R{0:N2} na vista {1}: raio, centro a centro e posição" -f ($ob[2] * 1000), (X $v "GetName2")) "DarkGray"
    }
    X $dm "ClearSelection2" $true | Out-Null
    return $n
}
