# Layout.ps1 - disposição das vistas, centralizar, anti-sobreposição de textos
# Carregado pelo DetalharSW.ps1 (dot-source). Não rodar sozinho.

function Centralizar($dm, $vistas, $baseMin) {
    $vs = @($vistas | Where-Object { $_ })
    if ($vs.Count -eq 0) { return }
    $os = @($vs | ForEach-Object { Contorno $_ })
    $x1 = ($os | ForEach-Object { $_.x1 } | Measure-Object -Minimum).Minimum
    $x2 = ($os | ForEach-Object { $_.x2 } | Measure-Object -Maximum).Maximum
    $y1 = ($os | ForEach-Object { $_.y1 } | Measure-Object -Minimum).Minimum
    $y2 = ($os | ForEach-Object { $_.y2 } | Measure-Object -Maximum).Maximum
    $dx = (($AreaL + $AreaR) / 2) - (($x1 + $x2) / 2)
    $dy = (($baseMin + $AreaT) / 2) - (($y1 + $y2) / 2)
    # não deixa encostar nas bordas (folga mínima de 1 cm)
    $dx = [math]::Max([math]::Min($dx, $AreaR - $x2), $AreaL - $x1)
    $dy = [math]::Max([math]::Min($dy, $AreaT - $y2), $baseMin - $y1)
    if ([math]::Abs($dx) -lt 0.002 -and [math]::Abs($dy) -lt 0.002) { return }
    $antes = @{}
    foreach ($v in $vs) { $antes[[string](X $v "GetName2")] = PosVista $v }
    foreach ($v in $vs) {
        $p0 = $antes[[string](X $v "GetName2")]; $pa = PosVista $v
        $alvoX = $p0[0] + $dx; $alvoY = $p0[1] + $dy
        if ([math]::Abs($pa[0] - $alvoX) -gt 0.0005 -or [math]::Abs($pa[1] - $alvoY) -gt 0.0005) { DefinirPosicao $v $alvoX $alvoY }
    }
    Rebuild $dm
    Log ("   Vistas centralizadas na folha (deslocamento {0:N0} x {1:N0} mm)" -f ($dx * 1000), ($dy * 1000)) "DarkGray"
}
# ---------------------------------------------------------------- anti-sobreposição de textos
# Lê o retângulo real de cada nota (chamadas de furo, notas de dobra, balões) e afasta as que
# encostam em outra nota ou em outra vista. Vale para todos os desenhos.
function AnnOf($n) { try { $a = X $n "GetAnnotation"; if ($a) { return $a } } catch { }; return $n }
function RetNota($n) {
    try { $e = XD (X $n "GetExtent"); if ($e -and $e.Count -ge 5) { return [pscustomobject]@{ x1 = [math]::Min($e[0], $e[3]); y1 = [math]::Min($e[1], $e[4]); x2 = [math]::Max($e[0], $e[3]); y2 = [math]::Max($e[1], $e[4]) } } } catch { }
    # chamada de furo não informa o tamanho: estima pelo texto (≈ 2 mm por caractere x 4,5 mm por linha) a partir da posição
    try {
        $p = XD (X (AnnOf $n) "GetPosition")
        $t = ""; try { $t = [string](X $n "GetText") } catch { }
        $linhas = 3; $larg = 0.058
        if ($t) { $ls = @($t -split "`n"); $linhas = [math]::Max(1, $ls.Count); $larg = [math]::Min(0.09, [math]::Max(0.03, (($ls | Measure-Object -Property Length -Maximum).Maximum) * 0.0019)) }
        return [pscustomobject]@{ x1 = $p[0] - 0.004; y1 = $p[1] - $linhas * 0.0048 - 0.001; x2 = $p[0] + $larg; y2 = $p[1] + 0.001 }
    } catch { }
    return $null
}
function Bate($a, $b, $folga) { return -not ($a.x2 + $folga -le $b.x1 -or $b.x2 + $folga -le $a.x1 -or $a.y2 + $folga -le $b.y1 -or $b.y2 + $folga -le $a.y1) }
function MoverNota($n, $dx, $dy) {
    $an = AnnOf $n; $p = XD (X $an "GetPosition")
    X $an "SetPosition" ($p[0] + $dx) ($p[1] + $dy) 0.0 | Out-Null
}
function TipoNota($n) {
    try { if (X $n "IsBomBalloon") { return "balao" } } catch { }
    $t = ""; try { $t = [string](X $n "GetText") } catch { }
    if ($t -match "(?i)PARA (CIMA|BAIXO)") { return "dobra" }
    if ($t -match "(?i)PASSANTE|MOD-DIAM|Ø|<HOLE|x\s*<") { return "furo" }
    return "outra"
}
function ResolverSobreposicoes($dm, $vistas, [string[]]$tiposMoveis, $extras = @()) {
    $vs = @($vistas | Where-Object { $_ })
    $notas = @()
    foreach ($v in $vs) {
        try { foreach ($n in @(X $v "GetNotes")) { if ($n) { $tp = TipoNota $n; if ($tp -eq "furo" -and $script:chamadas.Count -gt 0) { $tp = "outra" }; $notas += ,@($n, $v, $tp) } } } catch { }
    }
    if ($tiposMoveis -contains "furo") { foreach ($c in $script:chamadas) { $notas += ,@($c[0], $c[1], "furo") } }
    $cont = @{}; foreach ($it in $notas) { $cont[$it[2]] = 1 + [int]$cont[$it[2]] }
    Log ("   [dbg] textos encontrados: " + (($cont.Keys | ForEach-Object { "$_=$($cont[$_])" }) -join ", ")) "DarkGray"
    if ($notas.Count -eq 0) { return }
    $limite = [pscustomobject]@{ x1 = $AreaL - 0.008; y1 = $AreaB - 0.004; x2 = $AreaR + 0.003; y2 = $AreaT + 0.008 }
    $fixos = @($extras | Where-Object { $_ })      # retângulos já ocupados (ex.: lista de materiais)
    $fixosTexto = @()
    $moveis = @()
    foreach ($it in $notas) { if ($tiposMoveis -contains $it[2]) { $moveis += ,$it } else { $r = RetNota $it[0]; if ($r) { $fixos += $r; $fixosTexto += $r } } }
    $moveis = @($moveis | Sort-Object { [array]::IndexOf($tiposMoveis, $_[2]) })   # notas de dobra antes das chamadas de furo
    $outl = @{}; foreach ($v in $vs) { $outl[[string](X $v "GetName2")] = Contorno $v }
    # faixas das cotas totais (acima e à esquerda de cada vista com cota) também são ocupadas
    foreach ($v in $vs) {
        try { $nd = 0; $dd = X $v "GetFirstDisplayDimension5"; while ($dd -and $nd -lt 50) { $nd++; $dd = X $dd "GetNext5" } } catch { $nd = 1 }
        if ($nd -gt 0) {
            $o = Contorno $v
            $fixos += [pscustomobject]@{ x1 = $o.x1; y1 = $o.y2; x2 = $o.x2; y2 = $o.y2 + 0.013 }
            $fixos += [pscustomobject]@{ x1 = $o.x1 - 0.013; y1 = $o.y1; x2 = $o.x1; y2 = $o.y2 }
        }
    }
    $mov = 0
    # passos de deslocamento: para cima/baixo primeiro (balões e notas), depois para os lados
    $passos = @(@(0, 1), @(0, -1), @(1, 0), @(-1, 0), @(1, 1), @(-1, 1), @(1, -1), @(-1, -1))
    foreach ($it in $moveis) {
        $n = $it[0]; $minha = [string](X $it[1] "GetName2")
        $r = RetNota $n; if (-not $r) { Log "   [dbg] sem retângulo para um texto do tipo $($it[2])" "DarkGray"; continue }
        # nota de dobra só desvia de outros textos e anda pouco (tem que ficar junto da linha de dobra)
        $obst = @(); if ($it[2] -eq "dobra") { $obst += $fixosTexto } else { $obst += $fixos }   # sempre lista (1 item só virava objeto solto e o += quebrava)
        $maxDist = if ($it[2] -eq "dobra") { 3 } else { 8 }
        if ($it[2] -ne "dobra") { foreach ($k in $outl.Keys) { $obst += $outl[$k] } }   # chamada de furo e balão também não cobrem a própria vista
        $folga = if ($it[2] -eq "furo") { 0.003 } else { 0.0015 }
        $colide = { param($q) foreach ($o in $obst) { if (Bate $q $o $folga) { return $true } }; return (-not ($q.x1 -ge $limite.x1 -and $q.x2 -le $limite.x2 -and $q.y1 -ge $limite.y1 -and $q.y2 -le $limite.y2)) }
        if (& $colide $r) {
            $w = $r.x2 - $r.x1; $h = $r.y2 - $r.y1
            $achou = $false
            for ($dist = 1; $dist -le $maxDist -and -not $achou; $dist++) {
                foreach ($ps in $passos) {
                    $dx = $ps[0] * $dist * ([math]::Max($w * 0.5, 0.006)); $dy = $ps[1] * $dist * ($h + 0.002)
                    $q = [pscustomobject]@{ x1 = $r.x1 + $dx; y1 = $r.y1 + $dy; x2 = $r.x2 + $dx; y2 = $r.y2 + $dy }
                    if (-not (& $colide $q)) { MoverNota $n $dx $dy; $r = RetNota $n; if (-not $r) { $r = $q }; $mov++; $achou = $true; break }
                }
            }
        }
        $fixos += $r; $fixosTexto += $r
    }
    if ($mov -gt 0) { Log "   $mov texto(s) afastado(s) para não encostar ($($tiposMoveis -join ', '))" "DarkGray" }
}

# ---------------------------------------------------------------- layout peça
function LayoutPeca($dm, $front, $left, $top, $iso, $flat) {
    $m = $script:MargemCotas
    MoverPara $front ($AreaL + $m) ($AreaT - $m)
    $of = Contorno $front
    if ($left) { MoverPara $left ($of.x2 + $Gap) ($AreaT - $m) }
    if ($top) { MoverPara $top ($AreaL + $m) ($of.y1 - $Gap) }
    if ($iso) { $oi = Contorno $iso; MoverPara $iso ($AreaR - $m - $oi.w) ($AreaT - $m) }
    if ($flat) {
        $of = Contorno $front
        $ref = if ($top) { Contorno $top } else { $of }
        $baseX = [math]::Max($ref.x2, $of.x2) + $Gap
        $topoY = if ($top) { $ref.y2 } else { $of.y1 - $Gap }
        if ($left) { $topoY = [math]::Min($topoY, (Contorno $left).y1 - $Gap) }
        $op = Contorno $flat
        if ($iso) { $oi = Contorno $iso; if ($baseX + $op.w -gt $oi.x1) { $topoY = [math]::Min($topoY, $oi.y1 - $Gap) } }
        MoverPara $flat $baseX $topoY
    }
    Rebuild $dm
    $os = @(@($front, $left, $top, $iso, $flat) | Where-Object { $_ } | ForEach-Object { Contorno $_ })
    foreach ($x in $os) { if (-not (DentroDaArea $x $AreaB)) { return $false } }
    for ($i = 0; $i -lt $os.Count; $i++) { for ($j = $i + 1; $j -lt $os.Count; $j++) { if (Sobrepoe $os[$i] $os[$j]) { return $false } } }
    return $true
}

# peça longa: frontal, superior e planificada uma embaixo da outra; lateral à direita da frontal; isométrica embaixo à direita
function LayoutPecaLonga($dm, $front, $left, $top, $iso, $flat) {
    $m = $script:MargemCotas
    MoverPara $front ($AreaL + $m) ($AreaT - $m)
    $of = Contorno $front
    if ($left) { MoverPara $left ($of.x2 + $Gap * 0.6) ($AreaT - $m) }
    $y = $of.y1 - $Gap
    if ($left) { $y = [math]::Min($y, (Contorno $left).y1 - $Gap) }
    if ($top) { MoverPara $top ($AreaL + $m) $y; $y = (Contorno $top).y1 - $Gap }
    if ($flat) { MoverPara $flat ($AreaL + $m) $y; $y = (Contorno $flat).y1 - $Gap }
    if ($iso) { $oi = Contorno $iso; MoverPara $iso ($AreaR - $m - $oi.w) ($AreaB + $m + $oi.h + 0.002) }
    Rebuild $dm
    return (ConfereLayout @($front, $left, $top, $iso, $flat))
}
function ConfereLayout($vistas) {
    $vs = @($vistas | Where-Object { $_ })
    $os = @($vs | ForEach-Object { Contorno $_ })
    for ($i = 0; $i -lt $os.Count; $i++) {
        $x = $os[$i]
        if (-not (DentroDaArea $x $AreaB)) { Log ("   [dbg] {0} fora da área: ({1:N3};{2:N3})-({3:N3};{4:N3})" -f (X $vs[$i] "GetName2"), $x.x1, $x.y1, $x.x2, $x.y2) "DarkGray"; return $false }
    }
    for ($i = 0; $i -lt $os.Count; $i++) { for ($j = $i + 1; $j -lt $os.Count; $j++) { if (Sobrepoe $os[$i] $os[$j]) { Log "   [dbg] $(X $vs[$i] 'GetName2') sobrepõe $(X $vs[$j] 'GetName2')" "DarkGray"; return $false } } }
    return $true
}
