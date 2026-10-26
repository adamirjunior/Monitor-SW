# Chapa.ps1 - chapa plana/dobrada e laser: cotas de laser, espessura, dobras, abas
# Carregado pelo DetalharSW.ps1 (dot-source). Não rodar sozinho.

function CotasLaser($dm, $front, $left, $top, $flat) {
    $tgl = K "swUserPreferenceToggle_e" @("swInputDimValOnCreate") 10
    $antes = $null
    try { $antes = X $sw "GetUserPreferenceToggle" $tgl; X $sw "SetUserPreferenceToggle" $tgl $false | Out-Null } catch { }
    try { CotasLaserInterno $dm $front $left $top $flat } finally { if ($null -ne $antes) { try { X $sw "SetUserPreferenceToggle" $tgl ([bool]$antes) | Out-Null } catch { } } }
}
# caixa real da peça na folha (o contorno da vista tem folga igual dos dois lados)
function CaixaReal($v) {
    $o = Contorno $v
    $r = [pscustomobject]@{ x1 = $o.x1; x2 = $o.x2; y1 = $o.y1; y2 = $o.y2 }
    try {
        $a = DadosXf $v; $esc = [double](XG $v "ScaleDecimal")
        $rx = @(); $ry = @()
        foreach ($vx in (Entidades $v "swViewEntityType_Vertex" 2)) { try { $q = Rot $a ([double[]](XD (X $vx "GetPoint"))); $rx += $q[0]; $ry += $q[1] } catch { } }
        if ($rx.Count -ge 2) {
            $w = (($rx | Measure-Object -Maximum).Maximum - ($rx | Measure-Object -Minimum).Minimum) * $esc
            $h = (($ry | Measure-Object -Maximum).Maximum - ($ry | Measure-Object -Minimum).Minimum) * $esc
            $fx = (($o.x2 - $o.x1) - $w) / 2; $fy = (($o.y2 - $o.y1) - $h) / 2
            if ($fx -gt 0 -and $fx -lt 0.05) { $r.x1 = $o.x1 + $fx; $r.x2 = $o.x2 - $fx }
            if ($fy -gt 0 -and $fy -lt 0.05) { $r.y1 = $o.y1 + $fy; $r.y2 = $o.y2 - $fy }
        }
    } catch { }
    return $r
}
function ValorCota($dd) { try { return [math]::Abs([double](XG (X $dd "GetDimension2" 0) "SystemValue")) } catch { return -1 } }
function ApagarCota($dm, $dd) {
    try { X $dm "ClearSelection2" $true | Out-Null; $an = X $dd "GetAnnotation"; $ok = $false; try { $ok = X $an "Select2" $false 0 } catch { }; if (-not $ok) { try { X $an "Select3" $false ([SwCom]::NullDisp()) | Out-Null } catch { } }; X $dm "EditDelete" | Out-Null } catch { }
}
# cota da ESPESSURA da chapa: procura duas arestas retas paralelas separadas pela espessura (aba vista de lado)
function CotaEspessura($dm, $vistas, $xVert = $null, $yHoriz = $null) {
    $T = [double]$script:espessura
    if ($T -le 0) { return 0 }
    foreach ($v in @($vistas)) {
        if (-not $v) { continue }
        try {
            $a = DadosXf $v
            $lin = @()
            foreach ($e in (Entidades $v "swViewEntityType_Edge" 1)) {
                try {
                    $c = X $e "GetCurve"; if (-not (X $c "IsLine")) { continue }
                    $p1 = Rot $a ([double[]](XD (X (X $e "GetStartVertex") "GetPoint"))); $p2 = Rot $a ([double[]](XD (X (X $e "GetEndVertex") "GetPoint")))
                    if ([math]::Abs($p1[0] - $p2[0]) -lt 1e-6) { $lin += ,@($e, "v", $p1[0], [math]::Min($p1[1], $p2[1]), [math]::Max($p1[1], $p2[1])) }
                    elseif ([math]::Abs($p1[1] - $p2[1]) -lt 1e-6) { $lin += ,@($e, "h", $p1[1], [math]::Min($p1[0], $p2[0]), [math]::Max($p1[0], $p2[0])) }
                } catch { }
            }
            # par de linhas paralelas na distância da espessura, de preferência numa EXTREMIDADE da peça
            # (no lado onde a cota fica: direita para cota vertical, embaixo para horizontal; à esquerda quando alinha com a principal),
            # assim a cota nunca puxa linha de chamada pelo meio da peça (ex.: 02204262)
            # extremos da vista (todas as linhas retas): uma ponta LIVRE da chapa encosta num deles
            $xsA = @(); $ysA = @()
            foreach ($L in $lin) { if ($L[1] -eq "h") { $xsA += $L[3], $L[4]; $ysA += $L[2] } else { $xsA += $L[2]; $ysA += $L[3], $L[4] } }
            $minX = ($xsA | Measure-Object -Minimum).Minimum; $maxX = ($xsA | Measure-Object -Maximum).Maximum
            $minY = ($ysA | Measure-Object -Minimum).Minimum; $maxY = ($ysA | Measure-Object -Maximum).Maximum
            $best = $null; $bestNota = -1.0; $lado = ""
            for ($i = 0; $i -lt $lin.Count; $i++) { for ($j = $i + 1; $j -lt $lin.Count; $j++) {
                $A = $lin[$i]; $B = $lin[$j]
                if ($A[1] -ne $B[1]) { continue }
                if ([math]::Abs([math]::Abs($A[2] - $B[2]) - $T) -gt 0.00003) { continue }
                $ini = [math]::Max($A[3], $B[3]); $fim = [math]::Min($A[4], $B[4]); $ov = $fim - $ini
                if ($ov -le 0) { continue }
                # ponta livre: as duas linhas terminam juntas no extremo da peça (lado preferido primeiro)
                $ld = ""; $bonus = 0.0
                if ($A[1] -eq "h") {
                    $dir = ([math]::Abs($A[4] - $maxX) -lt 0.0001 -and [math]::Abs($B[4] - $maxX) -lt 0.0001)
                    $esq = ([math]::Abs($A[3] - $minX) -lt 0.0001 -and [math]::Abs($B[3] - $minX) -lt 0.0001)
                    if ($null -ne $xVert) { if ($esq) { $ld = "esq"; $bonus = 1000 } elseif ($dir) { $ld = "dir"; $bonus = 900 } }
                    else { if ($dir) { $ld = "dir"; $bonus = 1000 } elseif ($esq) { $ld = "esq"; $bonus = 900 } }
                } else {
                    $baixo = ([math]::Abs($A[3] - $minY) -lt 0.0001 -and [math]::Abs($B[3] - $minY) -lt 0.0001)
                    $cima = ([math]::Abs($A[4] - $maxY) -lt 0.0001 -and [math]::Abs($B[4] - $maxY) -lt 0.0001)
                    if ($baixo) { $ld = "baixo"; $bonus = 1000 } elseif ($cima) { $ld = "cima"; $bonus = 900 }
                }
                # quem chama já disse a direção da cota (DXF: em cima, junto da cota horizontal; 1.1: à esquerda): esse tipo de par vem primeiro
                if (($null -ne $yHoriz -and $A[1] -eq "v") -or ($null -ne $xVert -and $A[1] -eq "h")) { $bonus += 2000 }
                $nota = $ov + $bonus
                if ($nota -gt $bestNota) { $bestNota = $nota; $best = @($A, $B); $lado = $ld }
            } }
            if (-not $best) { continue }
            X $dm "ClearSelection2" $true | Out-Null
            SelecionarEntidade $dm $v $best[0][0] $false | Out-Null; SelecionarEntidade $dm $v $best[1][0] $true | Out-Null
            if ((QtdSelecionados $dm) -ne 2) { continue }
            $o = Contorno $v
            # texto da cota junto da ponta da chapa (e não no meio da vista)
            $cr = CaixaReal $v; $escV = 1.0; try { $escV = [double](XG $v "ScaleDecimal") } catch { }
            $meio = ([double]$best[0][2] + [double]$best[1][2]) / 2
            $yPonta = [double]($cr.y1 + ($meio - $minY) * $escV); $xPonta = [double]($cr.x1 + ($meio - $minX) * $escV)
            if ($yPonta -lt $o.y1 -or $yPonta -gt $o.y2) { $yPonta = ($o.y1 + $o.y2) / 2 }
            if ($xPonta -lt $o.x1 -or $xPonta -gt $o.x2) { $xPonta = ($o.x1 + $o.x2) / 2 }
            $dd = $null
            if ($best[0][1] -eq "v") {
                # horizontal: na mesma reta da cota horizontal da vista principal (ex.: DXF, junto do 390 em cima), quando informada
                $yc = if ($null -ne $yHoriz) { [double]$yHoriz } elseif ($lado -eq "cima") { [double]($o.y2 + $DistCota) } else { [double]($o.y1 - $DistCota) }
                $dd = X $dm "AddHorizontalDimension2" $xPonta $yc 0.0
            }
            else {
                # vertical: na mesma reta da cota vertical da vista principal (ex.: 290 à esquerda), quando informada
                $xc = if ($null -ne $xVert) { [double]$xVert } elseif ($lado -eq "esq") { [double]($o.x1 - $DistCota) } else { [double]($o.x2 + $DistCota) }
                $dd = X $dm "AddVerticalDimension2" $xc $yPonta 0.0
            }
            X $dm "ClearSelection2" $true | Out-Null
            if ($dd) { $script:vistaPerfil = $v; Log ("   Cota da espessura ({0:N2} mm) na vista {1}" -f ($T * 1000), (X $v "GetName2")) "DarkGray"; return 1 }
        } catch { }
    }
    Log "   (não achei onde cotar a espessura da chapa)" "DarkYellow"
    return 0
}
# planificada no mesmo sentido da vista principal: as dobras do lado em que aparecem na principal
# (a planificada sai do SolidWorks virada; ex.: 02204262 com as dobras à direita na principal e à esquerda na planificada)
function AlinharPlanificada($dm, $front, $flat) {
    if (-not $front -or -not $flat) { return }
    try {
        $pm = @(); foreach ($vx in (Entidades $front "swViewEntityType_Vertex" 2)) { try { $pm += ,([double[]](XD (X $vx "GetPoint"))) } catch { } }
        if ($pm.Count -gt 0) { EscolherModoXf $front $pm | Out-Null }
        $xs = @()
        foreach ($e in (Entidades $front "swViewEntityType_Edge" 1)) {
            try {
                $c = X $e "GetCurve"; if (-not (X $c "IsCircle")) { continue }
                if (-not (X $e "GetStartVertex")) { continue }   # círculo inteiro = furo, não dobra
                $cp = [double[]](XD (XG $c "CircleParams")); $q = NaFolha $front @($cp[0], $cp[1], $cp[2]); $xs += $q[0]
            } catch { }
        }
        $xn = @()
        foreach ($nt in @(X $flat "GetNotes")) {
            if (-not $nt) { continue }
            if ([string](X $nt "GetText") -notmatch "(?i)PARA (CIMA|BAIXO)") { continue }
            try { $xn += [double](XD (X (X $nt "GetAnnotation") "GetPosition"))[0] } catch { }
        }
        if ($xs.Count -eq 0 -or $xn.Count -eq 0) { return }
        $of = Contorno $front; $ol = Contorno $flat
        $ladoF = (($xs | Measure-Object -Average).Average - ($of.x1 + $of.x2) / 2) / [math]::Max(0.001, $of.w)
        $ladoP = (($xn | Measure-Object -Average).Average - ($ol.x1 + $ol.x2) / 2) / [math]::Max(0.001, $ol.w)
        # só quando as dobras estão claramente de lados opostos (dobra no meio da peça não importa)
        if ([math]::Abs($ladoF) -gt 0.1 -and [math]::Abs($ladoP) -gt 0.1 -and ($ladoF * $ladoP) -lt 0) {
            $ang = 0.0; try { $ang = [double](XG $flat "Angle") } catch { }
            XS $flat "Angle" ($ang + [math]::PI); Rebuild $dm
            Log "   Planificada girada 180° (dobras do mesmo lado da vista principal)" "DarkGray"
        }
    } catch { Log "   (alinhar planificada: $($_.Exception.Message))" "DarkYellow" }
    $script:xfCache = @{}; $script:xfModo = @{}
}
# chapa dobrada: cota de cada linha de dobra até a extremidade MAIS PRÓXIMA (o operador mede depois de dobrar).
# A direção de cada linha vem da nota "PARA CIMA/BAIXO" presa a ela (a nota fica no sentido da linha, na folha);
# a linha é a entidade em que a nota está presa. Cria a cota até os dois lados e deixa só a menor.
function AnexosDaNota($an) {
    foreach ($m in "GetAttachedEntities3", "GetAttachedEntities2", "GetAttachedEntities") {
        try { $r = X $an $m; if ($r) { $l = @($r) | Where-Object { $_ }; if ($l.Count -gt 0) { return ,$l } } } catch { }
    }
    return ,@()
}
function CotasLinhasDobra($dm, $v) {
    if (-not $v) { return 0 }
    $a = DadosXf $v; $esc = 1.0; try { $esc = [double](XG $v "ScaleDecimal") } catch { }
    $pts = @()
    foreach ($vx in (Entidades $v "swViewEntityType_Vertex" 2)) { try { $pts += ,@($vx, (Rot $a ([double[]](XD (X $vx "GetPoint"))))) } catch { } }
    if ($pts.Count -lt 2) { return 0 }
    # linhas de dobra da vista (para quando a nota não disser a qual linha está presa)
    $bls = @(); try { $bls = @(X $v "GetBendLines") | Where-Object { $_ } } catch { }
    $itens = @()
    foreach ($nt in @(X $v "GetNotes")) {
        if (-not $nt) { continue }
        $t = [string](X $nt "GetText")
        if ($t -notmatch "(?i)PARA (CIMA|BAIXO)") { continue }
        $an = X $nt "GetAnnotation"
        $ang = 0.0; try { $ang = [double](XG $nt "Angle") } catch { }
        $vertical = ([math]::Abs([math]::Sin($ang)) -gt 0.7)
        $linha = $null
        foreach ($e in (AnexosDaNota $an)) { $linha = $e; break }
        if (-not $linha) { Log "   [dbg] nota de dobra sem linha presa: usando a lista de linhas de dobra" "DarkGray" }
        $itens += ,@($linha, $vertical)
    }
    if ($itens.Count -eq 0 -and $bls.Count -eq 0) { return 0 }
    # nota sem entidade presa: usa as linhas de dobra na mesma ordem
    for ($i = 0; $i -lt $itens.Count; $i++) { if (-not $itens[$i][0] -and $i -lt $bls.Count) { $itens[$i][0] = $bls[$i] } }
    $cr = CaixaReal $v; $o = Contorno $v
    $n = 0; $kH = 0; $kV = 0; $passo = 0.008
    foreach ($it in $itens) {
        $bl = $it[0]; $vertical = $it[1]
        if (-not $bl) { continue }
        try {
            $eixo = if ($vertical) { 0 } else { 1 }        # linha em pé -> cota horizontal (eixo X da folha)
            $ord = @($pts | Sort-Object { $_[1][$eixo] })
            $ext = @($ord[0], $ord[-1])
            $metodo = if ($vertical) { "AddHorizontalDimension2" } else { "AddVerticalDimension2" }
            $res = @()
            foreach ($lado in 0, 1) {
                X $dm "ClearSelection2" $true | Out-Null
                if (-not (SelecionarEntidade $dm $v $bl $false)) { continue }
                SelecionarEntidade $dm $v $ext[$lado][0] $true | Out-Null
                if ((QtdSelecionados $dm) -ne 2) { continue }
                $dd = $null
                try {
                    if ($vertical) { $dd = X $dm $metodo ([double](($o.x1 + $o.x2) / 2)) ([double]($o.y1 - $DistCota - $kH * $passo)) 0.0 }
                    else { $dd = X $dm $metodo ([double]($o.x2 + $DistCota + $kV * $passo)) ([double](($o.y1 + $o.y2) / 2)) 0.0 }
                } catch { }
                if ($dd) { $res += ,@($dd, (ValorCota $dd), $lado) }
            }
            X $dm "ClearSelection2" $true | Out-Null
            $bons = @($res | Where-Object { $_[1] -gt 0.0001 } | Sort-Object { $_[1] })
            foreach ($r in $res) { if ($bons.Count -eq 0 -or $r[0] -ne $bons[0][0]) { ApagarCota $dm $r[0] } }   # fica só a da extremidade mais próxima
            if ($bons.Count -eq 0) { continue }
            $fica = $bons[0]; $val = $fica[1] * $esc
            try {
                $an2 = X $fica[0] "GetAnnotation"
                if ($vertical) {
                    $tx = if ($fica[2] -eq 0) { $cr.x1 + $val / 2 } else { $cr.x2 - $val / 2 }
                    X $an2 "SetPosition" ([double]$tx) ([double]($o.y1 - $DistCota - $kH * $passo)) 0.0 | Out-Null; $kH++
                } else {
                    $ty = if ($fica[2] -eq 0) { $cr.y1 + $val / 2 } else { $cr.y2 - $val / 2 }
                    X $an2 "SetPosition" ([double]($o.x2 + $DistCota + $kV * $passo)) ([double]$ty) 0.0 | Out-Null; $kV++
                }
            } catch { }
            Log ("   Linha de dobra {0}: {1:N2} mm até a extremidade mais próxima" -f $(if ($vertical) { "em pé" } else { "deitada" }), ($fica[1] * 1000)) "DarkGray"
            $n++
        } catch { Log "   (cota da linha de dobra: $($_.Exception.Message))" "DarkYellow" }
    }
    X $dm "ClearSelection2" $true | Out-Null
    return $n
}
# chapa dobrada, vista de perfil (onde aparece a espessura): cota de cada aba (distância entre as faces externas),
# para conferir com paquímetro depois de dobrar. Só quando há mais de 2 faces na direção (2 faces = cota total).
function CotasAbas($dm, $v) {
    if (-not $v) { return 0 }
    $T = [double]$script:espessura; if ($T -le 0) { return 0 }
    $a = DadosXf $v; $o = Contorno $v; $cr = CaixaReal $v; $n = 0
    $esc = 1.0; try { $esc = [double](XG $v "ScaleDecimal") } catch { }
    $lin = @()
    foreach ($e in (Entidades $v "swViewEntityType_Edge" 1)) {
        try {
            $c = X $e "GetCurve"; if (-not (X $c "IsLine")) { continue }
            $p1 = Rot $a ([double[]](XD (X (X $e "GetStartVertex") "GetPoint"))); $p2 = Rot $a ([double[]](XD (X (X $e "GetEndVertex") "GetPoint")))
            if ([math]::Abs($p1[0] - $p2[0]) -lt 1e-6) { $lin += ,@($e, 0, $p1[0], [math]::Abs($p1[1] - $p2[1])) }
            elseif ([math]::Abs($p1[1] - $p2[1]) -lt 1e-6) { $lin += ,@($e, 1, $p1[1], [math]::Abs($p1[0] - $p2[0])) }
        } catch { }
    }
    foreach ($eixo in 0, 1) {
        # posições distintas (a mais longa de cada posição); descarta a face interna de cada aba (a que fica a 1 espessura de outra, para dentro)
        $pos = @()
        foreach ($l in (@($lin | Where-Object { $_[1] -eq $eixo }) | Sort-Object { -$_[3] })) { if (-not ($pos | Where-Object { [math]::Abs($_[2] - $l[2]) -lt 0.00005 })) { $pos += ,$l } }
        $pos = @($pos | Sort-Object { $_[2] })
        if ($pos.Count -lt 2) { continue }
        $min = $pos[0][2]; $max = $pos[-1][2]
        $ext = @()
        foreach ($p in $pos) {
            $par = $pos | Where-Object { [math]::Abs([math]::Abs($_[2] - $p[2]) - $T) -lt 0.00003 } | Select-Object -First 1
            if ($par) { $interna = if ([math]::Abs($p[2] - $min) -lt [math]::Abs($p[2] - $max)) { $p[2] -gt $par[2] } else { $p[2] -lt $par[2] }; if ($interna -and $p[2] -ne $min -and $p[2] -ne $max) { continue } }
            $ext += ,$p
        }
        if ($ext.Count -lt 3) { continue }   # só 2 faces: a cota total já mostra
        $k = 0
        for ($i = 0; $i -lt $ext.Count - 1; $i++) {
            $A = $ext[$i]; $B = $ext[$i + 1]
            if ([math]::Abs($B[2] - $A[2]) -lt $T * 1.5) { continue }   # é a própria espessura
            X $dm "ClearSelection2" $true | Out-Null
            SelecionarEntidade $dm $v $A[0] $false | Out-Null; SelecionarEntidade $dm $v $B[0] $true | Out-Null
            if ((QtdSelecionados $dm) -ne 2) { continue }
            $meio = (($A[2] + $B[2]) / 2 - $min) * $esc
            $dd = $null
            try {
                if ($eixo -eq 0) { $dd = X $dm "AddHorizontalDimension2" ([double]($cr.x1 + $meio)) ([double]($o.y1 - $DistCota - 0.008)) 0.0 }
                else { $dd = X $dm "AddVerticalDimension2" ([double]($o.x2 + $DistCota + 0.008)) ([double]($cr.y1 + $meio)) 0.0 }
            } catch { }
            if ($dd) { $n++; $k++ }
        }
    }
    X $dm "ClearSelection2" $true | Out-Null
    if ($n -gt 0) { Log "   $n cota(s) de aba (distância entre dobras) na vista de perfil" "DarkGray" }
    return $n
}
# notas "PARA CIMA/BAIXO 90° R..." do mesmo tamanho das cotas e centralizadas entre as extremidades da peça
function AjustarNotasDobra($dm, $v) {
    if (-not $v) { return }
    try {
        $alt = 0.0
        try {
            foreach ($an in @(X $v "GetAnnotations")) { if ($an -and [int](X $an "GetType") -eq $AnnDim) { $alt = [double](XG (X $an "GetTextFormat" 0) "CharHeight"); break } }
        } catch { }
        if ($alt -le 0) { $alt = 0.0025 }
        $alt = $alt * 0.8   # um pouco menor que o número das cotas
        $cr = CaixaReal $v; $m = 0
        foreach ($nt in @(X $v "GetNotes")) {
            if (-not $nt) { continue }
            $t = [string](X $nt "GetText")
            if ($t -notmatch "(?i)PARA (CIMA|BAIXO)") { continue }
            $an = X $nt "GetAnnotation"
            try { $tf = X $an "GetTextFormat" 0; XS $tf "CharHeight" $alt; X $an "SetTextFormat" 0 $false $tf | Out-Null } catch { }
            Rebuild $dm
            $ang = 0.0; try { $ang = [double](XG $nt "Angle") } catch { }
            $empe = ([math]::Abs([math]::Sin($ang)) -gt 0.7)
            $ex = XD (X $nt "GetExtent"); $p = XD (X $an "GetPosition")
            if (-not $ex -or -not $p) { continue }
            $mx = ($ex[0] + $ex[3]) / 2; $my = ($ex[1] + $ex[4]) / 2
            if ($empe) { $dyy = (($cr.y1 + $cr.y2) / 2) - $my; X $an "SetPosition" $p[0] ($p[1] + $dyy) 0.0 | Out-Null }
            else { $dxx = (($cr.x1 + $cr.x2) / 2) - $mx; X $an "SetPosition" ($p[0] + $dxx) $p[1] 0.0 | Out-Null }
            $m++
        }
        if ($m -gt 0) { Log ("   $m nota(s) de dobra com {0:N1} mm e centralizadas na peça" -f ($alt * 1000)) "DarkGray" }
    } catch { Log "   (notas de dobra: $($_.Exception.Message))" "DarkYellow" }
}
function CotasLaserInterno($dm, $front, $left, $top, $flat) {
    $n = 0
    if ($front) { $n += CotaTotal $dm $front $true $true }
    if ($left) { $n += CotaTotal $dm $left $true $false }
    # vista de baixo: na chapa plana leva comprimento + espessura; nas outras, só a profundidade (se não houver lateral)
    # chapa plana: a vista de baixo mostra a ESPESSURA (duas linhas paralelas na distância da espessura)
    if ($script:planaAtual -and ($top -or $left)) { $xAl = $null; try { $xAl = (CaixaReal $front).x1 - $DistCota } catch { }; $ne = CotaEspessura $dm @($top, $left) $xAl; if ($ne -eq 0 -and $top) { $ne = CotaTotal $dm $top $false $true }; $n += $ne }
    elseif ($top -and -not $left) { $n += CotaTotal $dm $top $false $true }
    if ($flat) { $n += CotaTotal $dm $flat $true $true }
    # chapa dobrada: espessura + linha de dobra até a extremidade mais próxima + notas de dobra harmonizadas
    if ($flat) {
        $script:vistaPerfil = $null
        # 1) RAIO DE DOBRA (não raio de furo/rasgo): na vista que mostra a dobra de perfil
        $nr = 0; $vistaRaio = $null
        foreach ($vv in @($top, $left, $front)) {
            if (-not $vv -or $nr -gt 0) { continue }
            try {
                $pm = @(); foreach ($vx in (Entidades $vv "swViewEntityType_Vertex" 2)) { try { $pm += ,([double[]](XD (X $vx "GetPoint"))) } catch { } }
                if ($pm.Count -gt 0) { EscolherModoXf $vv $pm | Out-Null }
                $nr = CotaRaioDobra $dm $vv
                if ($nr -gt 0) { $vistaRaio = $vv }
            } catch { }
        }
        if ($nr -gt 0) { Log "   $nr raio(s) de dobra cotado(s)" "DarkGray" }
        $n += $nr
        # 2) ESPESSURA na MESMA vista do raio de dobra (se não der lá, tenta as outras)
        $ordem = @($vistaRaio) + @(@($front, $left, $top) | Where-Object { $_ -and $_ -ne $vistaRaio })
        $n += CotaEspessura $dm @($ordem | Where-Object { $_ })
        # 3) linha de dobra até a aresta mais próxima (na planificada) - pedido do usuário em 26/10
        try { $nl = CotasLinhasDobra $dm $flat; $n += $nl; if ($nl -gt 0) { Log "   $nl cota(s) de linha de dobra até a aresta mais próxima" "DarkGray" } } catch { Log "   (linha de dobra: $($_.Exception.Message))" "DarkYellow" }

        Rebuild $dm
        AjustarNotasDobra $dm $flat
    }
    # peça de laser: furos saem do DXF, não leva chamada de furo (só peças usinadas, que usam as cotas do modelo)
    Log "   Cotas de laser/dobra: $n cotas (sem chamada de furo)"
    Rebuild $dm
    ResolverSobreposicoes $dm @($front, $left, $top, $flat, $script:isoAtual) @("dobra", "furo")
}


# centraliza o conjunto de vistas na área útil (com folga para as cotas em volta)
# afasta notas de dobra que ficaram uma em cima da outra (considera texto deitado ou em pé)
function EspalharNotasDobra($dm, $v) {
    if (-not $v) { return }
    try {
        $notas = @(X $v "GetNotes") | Where-Object { $_ }
        $itens = @()
        foreach ($n in $notas) {
            $t = [string](X $n "GetText")
            if ($t -notmatch "(?i)PARA (CIMA|BAIXO)") { continue }
            $an = X $n "GetAnnotation"; $p = XD (X $an "GetPosition")
            $ang = 0.0; try { $ang = [double](XG $n "Angle") } catch { }
            $empe = ([math]::Abs([math]::Sin($ang)) -gt 0.7)
            $L = 0.045; $H = 0.0045
            $w = if ($empe) { $H } else { $L }; $h = if ($empe) { $L } else { $H }
            $itens += ,@($an, $p, $w, $h, $empe)
        }
        $mov = 0
        for ($i = 1; $i -lt $itens.Count; $i++) {
            for ($k = 0; $k -lt $i; $k++) {
                $a = $itens[$k]; $b = $itens[$i]
                $sobre = ([math]::Abs($a[1][0] - $b[1][0]) -lt ($a[2] + $b[2]) / 2) -and ([math]::Abs($a[1][1] - $b[1][1]) -lt ($a[3] + $b[3]) / 2)
                if ($sobre) {
                    if ($b[4]) { $nx = $b[1][0]; $ny = $a[1][1] - $b[3] - 0.004 } else { $nx = $a[1][0] + $b[2] + 0.004; $ny = $b[1][1] }
                    X $b[0] "SetPosition" $nx $ny 0.0 | Out-Null
                    $itens[$i][1] = @($nx, $ny, 0.0); $mov++
                }
            }
        }
        if ($mov -gt 0) { Log "   $mov nota(s) de dobra afastada(s)" "DarkGray" }
    } catch { Log "   (não consegui afastar as notas de dobra: $($_.Exception.Message))" "DarkYellow" }
}

# raio de dobra: arco (não círculo inteiro) visto de perfil que tem outro arco CONCÊNTRICO com raio = raio + espessura
# (raio interno e externo da dobra). Arcos de rasgos e furos não têm esse par e ficam de fora. Cota o raio interno.
function CotaRaioDobra($dm, $v) {
    $esp = [double]$script:espessura
    if ($esp -le 0) { return 0 }
    $a = DadosXf $v; $o = Contorno $v
    $cx = ($o.x1 + $o.x2) / 2; $cy = ($o.y1 + $o.y2) / 2
    $arcos = @()
    foreach ($e in (Entidades $v "swViewEntityType_Edge" 1)) {
        try {
            $c = X $e "GetCurve"; if (-not (X $c "IsCircle")) { continue }
            $sv = $null; try { $sv = X $e "GetStartVertex" } catch { }
            if (-not $sv) { continue }   # círculo inteiro = furo
            $cp = [double[]](XD (XG $c "CircleParams"))
            $eixo = Rot $a @($cp[3], $cp[4], $cp[5])
            if ([math]::Abs($eixo[0]) -gt 0.05 -or [math]::Abs($eixo[1]) -gt 0.05) { continue }   # só arco visto de perfil
            $arcos += ,@($e, $cp, $sv)
        } catch { }
    }
    $n = 0; $feitos = @{}
    foreach ($ar in ($arcos | Sort-Object { $_[1][6] })) {
        $cp = $ar[1]; $r = $cp[6]
        $par = $arcos | Where-Object {
            $q = $_[1]
            ([math]::Abs($q[6] - ($r + $esp)) -lt 0.0002) -and
            ([math]::Sqrt([math]::Pow($q[0] - $cp[0], 2) + [math]::Pow($q[1] - $cp[1], 2) + [math]::Pow($q[2] - $cp[2], 2)) -lt 0.002)
        } | Select-Object -First 1
        if (-not $par) { continue }
        $rmm = [math]::Round($r * 1000, 2)
        if ($feitos.ContainsKey($rmm)) { continue }
        try {
            # cota no MEIO da dobra, entre as duas faces: linha de chamada na bissetriz do arco (do centro para fora,
            # passando pelo meio do arco), texto além do arco externo
            $q0 = NaFolha $v ([double[]]@($cp[0], $cp[1], $cp[2]))
            $qs = NaFolha $v ([double[]](XD (X $ar[2] "GetPoint")))
            # direção da chamada = bissetriz do lado DE FORA da dobra: soma dos vetores centro->ponta inicial e
            # centro->ponta final do arco (pontas lidas da própria aresta). O parâmetro médio da curva podia cair
            # do outro lado (cota saía espelhada para dentro da dobra).
            $qm = $null
            try {
                $gp = [double[]](XD (X $ar[0] "GetCurveParams2"))
                $qa = NaFolha $v ([double[]]@($gp[0], $gp[1], $gp[2])); $qb = NaFolha $v ([double[]]@($gp[3], $gp[4], $gp[5]))
                $qm = @(($q0[0] + ($qa[0] - $q0[0]) + ($qb[0] - $q0[0])), ($q0[1] + ($qa[1] - $q0[1]) + ($qb[1] - $q0[1])))
            } catch { Log "   (pontas do arco: $($_.Exception.Message))" "DarkYellow" }
            if (-not $qm) { $qm = $qs }
            $ux = $qm[0] - $q0[0]; $uy = $qm[1] - $q0[1]
            Log ("   (raio de dobra: direção da chamada {0:N0}°)" -f ([math]::Atan2($uy, $ux) * 180 / [math]::PI)) "DarkGray"
            $lu = [math]::Sqrt($ux * $ux + $uy * $uy)
            if ($lu -lt 1e-7) { $ux = $qs[0] - $cx; $uy = $qs[1] - $cy; $lu = [math]::Sqrt($ux * $ux + $uy * $uy); if ($lu -lt 1e-7) { $lu = 1 } }
            $rFolha = [math]::Sqrt([math]::Pow($qs[0] - $q0[0], 2) + [math]::Pow($qs[1] - $q0[1], 2))
            $escV = 1.0; try { $escV = [double](XG $v "ScaleDecimal") } catch { }
            $dist = $rFolha + $esp * $escV + 0.010
            X $dm "ClearSelection2" $true | Out-Null
            if (-not (SelecionarEntidade $dm $v $ar[0] $false)) { continue }
            $tx = $q0[0] + $ux / $lu * $dist; $ty = $q0[1] + $uy / $lu * $dist
            $tx = [math]::Max($o.x1 - 0.015, [math]::Min($o.x2 + 0.015, $tx)); $ty = [math]::Max($o.y1 - 0.012, [math]::Min($o.y2 + 0.012, $ty))
            $d = $null; try { $d = X $dm "AddRadialDimension2" ([double]$tx) ([double]$ty) 0.0 } catch { }
            if ($d) { $feitos[$rmm] = 1; $n++; Log ("   Raio de dobra R{0} cotado na vista {1}" -f $rmm, (X $v "GetName2")) "DarkGray" }
        } catch { }
    }
    X $dm "ClearSelection2" $true | Out-Null
    return $n
}
