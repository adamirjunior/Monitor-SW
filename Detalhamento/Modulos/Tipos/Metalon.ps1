# Metalon.ps1 - METALON / METALOM (padrão 02123721): quebras, cotas encadeadas, isométrica dos furos
# Carregado pelo DetalharSW.ps1 (dot-source). Não rodar sozinho.

# ---------------------------------------------------------------- METALON (tubo retangular/quadrado) - padrão ProEstamp, ex.: 02123721
# vista lateral comprida embaixo (com QUEBRAS entre os furos para aumentar a escala), cota total em cima,
# cotas em cadeia da posição dos furos, altura do furo à esquerda, chamada "14 x Ø9,50 PASSANTE",
# vista de topo do perfil à direita (largura, altura e parede) e isométrica grande em cima
$script:gapQuebra = 0.006
$script:mq = @{ on = $false }
function EhMetalon($desc) { return ([string]$desc -match '(?i)METAL[OÃ][NM]') }
function ApagarVista($dm, $v) { try { Selecionar $dm $v | Out-Null; X $dm "EditDelete" | Out-Null } catch { } }
# limites da peça no plano da vista (caixa do modelo girada): [[umin,umax],[vmin,vmax]]
function LimitesNaVista($v) {
    $a = DadosXf $v; $cb = $script:caixaPeca; $lim = @(@(1e9, -1e9), @(1e9, -1e9))
    foreach ($cx in $cb[0], $cb[3]) { foreach ($cy in $cb[1], $cb[4]) { foreach ($cz in $cb[2], $cb[5]) {
        $r = Rot $a @($cx, $cy, $cz)
        for ($i = 0; $i -lt 2; $i++) { $lim[$i][0] = [math]::Min($lim[$i][0], $r[$i]); $lim[$i][1] = [math]::Max($lim[$i][1], $r[$i]) }
    } } }
    return ,$lim
}
function DesfazerQuebras($dm, $v) {
    try { Selecionar $dm $v | Out-Null; X $dm "UnBreakView" | Out-Null } catch { }
    $bls = $null; try { $bls = X $v "GetBreakLines" } catch { }
    foreach ($bl in @($bls)) {
        if (-not $bl) { continue }
        try { X $dm "ClearSelection2" $true | Out-Null } catch { }
        $sel = $false
        try { $sel = X $bl "Select" $false } catch { }
        if (-not $sel) { try { $sel = X $bl "Select2" $false 0 } catch { } }
        try { X $dm "EditDelete" | Out-Null } catch { }
    }
    Rebuild $dm
}
# insere as quebras (pares u1,u2 no eixo horizontal da vista, em metros do modelo).
# Cria as linhas (InsertBreak2/InsertBreak; se não der, InsertBreakVertical na vista selecionada), depois
# acerta a posição com IBreakLine.SetPosition testando o sistema de coordenadas e confere pela largura da vista.
function LinhasQuebra($v) {
    $r = $null; try { $r = X $v "GetBreakLines" } catch { }
    $res = @(); foreach ($x in @($r)) { if ($x) { $res += ,$x } }
    return ,$res
}
function PosConv($conv, $u, $esc, $xc, $uc, $px) {
    switch ($conv) {
        0 { return $u }
        1 { return $u * $esc }
        2 { return $xc + ($u - $uc) * $esc }
        3 { return $xc + ($u - $uc) * $esc - $px }
        4 { return ($u - $uc) }
        5 { return ($u - $uc) * $esc }
    }
}
function QuebrarVista($dm, $v, $cortes, $lim) {
    $nb = [int]($cortes.Count / 2)
    if ($nb -lt 1) { return $false }
    $ori = K "swBreakLineOrientation_e" @("swBreakLineVertical") 0
    $est = K "swBreakLineStyle_e" @("swBreakLine_ZigZag") 1
    $pg = K "swUserPreferenceDoubleValue_e" @("swDetailingBreakLineGap") -1
    if ($pg -ge 0) { try { X (XG $dm "Extension") "SetUserPreferenceDouble" $pg 0 $script:gapQuebra | Out-Null } catch { } }
    $esc = 1.0; try { $esc = [double](XG $v "ScaleDecimal") } catch { }
    $o = Contorno $v; $p = PosVista $v
    $uc = ($lim[0][0] + $lim[0][1]) / 2; $xc = ($o.x1 + $o.x2) / 2
    $w0 = $o.w
    $rem = 0.0; for ($i = 0; $i -lt $nb; $i++) { $rem += $cortes[2 * $i + 1] - $cortes[2 * $i] }
    $nomes = @("modelo", "modelo x escala", "folha", "folha relativa à vista", "modelo a partir do centro", "modelo x escala a partir do centro")
    # o InsertBreak devolve vazio quando a posição cai fora da vista: o sistema certo é o que aceita TODAS as quebras
    foreach ($cv in 5, 4, 1, 0, 2, 3) {
        $criadas = 0
        for ($i = 0; $i -lt $nb; $i++) {
            $p1 = PosConv $cv ([double]$cortes[2 * $i]) $esc $xc $uc $p[0]; $p2 = PosConv $cv ([double]$cortes[2 * $i + 1]) $esc $xc $uc $p[0]
            $bl = $null; try { $bl = X $v "InsertBreak" ([int]$ori) ([double]$p1) ([double]$p2) ([int]$est) } catch { }
            if ($bl) { $criadas++ }
        }
        Log "   [dbg] quebras ($($nomes[$cv])): $criadas de $nb aceitas" "DarkGray"
        if ($criadas -lt $nb) { if ($criadas -gt 0) { DesfazerQuebras $dm $v }; continue }
        Selecionar $dm $v | Out-Null
        try { X $dm "BreakView" | Out-Null } catch { Log "   [dbg] BreakView: $($_.Exception.Message)" "DarkGray" }
        Rebuild $dm
        $w1 = (Contorno $v).w
        $nl = (LinhasQuebra $v).Count
        Log ("   [dbg] quebras ({0}): {1} linha(s) na vista; contorno {2:N1} -> {3:N1} mm (esperado ~{4:N1})" -f $nomes[$cv], $nl, ($w0 * 1000), ($w1 * 1000), (($w0 - $esc * $rem + $nb * $script:gapQuebra) * 1000)) "DarkGray"
        $script:mq = @{ on = $true; nb = $nb; rem = $rem; L = ($lim[0][1] - $lim[0][0]); alt = ($lim[1][1] - $lim[1][0]); encolhe = ($w1 -lt $w0 - 0.3 * $esc * $rem) }
        if (-not $script:mq.encolhe) { Log "   [dbg] o contorno da vista não mudou com a quebra; uso a largura calculada" "DarkGray" }
        Log "   Vista principal quebrada em $nb ponto(s) (padrão de metalon)" "DarkGray"
        return $true
    }
    Log "   Aviso: o SolidWorks não aceitou as quebras do metalon; vista inteira (escala menor)." "Yellow"
    return $false
}
# contorno da principal do metalon: se o SolidWorks não atualizar o contorno depois da quebra, calcula a largura (centrada)
function ContornoM($v) {
    $o = Contorno $v
    if (-not $script:mq.on -or $script:mq.encolhe) { return $o }
    $esc = 1.0; try { $esc = [double](XG $v "ScaleDecimal") } catch { }
    $pad = [math]::Max(0.0, ($o.h - $script:mq.alt * $esc) / 2)
    if ($o.w -lt 0.85 * (2 * $pad + $script:mq.L * $esc)) { return $o }   # o SolidWorks já devolve o contorno quebrado
    $wb = 2 * $pad + ($script:mq.L - $script:mq.rem) * $esc + $script:mq.nb * $script:gapQuebra
    $xc = ($o.x1 + $o.x2) / 2
    return [pscustomobject]@{ x1 = $xc - $wb / 2; y1 = $o.y1; x2 = $xc + $wb / 2; y2 = $o.y2; w = $wb; h = $o.h }
}
# onde cortar: nos vãos grandes entre furos (e no meio, se não tiver furo), deixando um pedaço de cada lado
function CortesMetalon($us, $uMin, $uMax, $alt) {
    # regra ProEstamp: furos aos pares ao longo do metalon; uma quebra a cada dois furos
    # (entre o 2º e o 3º, entre o 4º e o 5º...), deixando um pedaço do tubo de cada lado
    $cortes = @()
    $keep = [math]::Max(0.015, 0.4 * $alt)
    if ($us.Count -eq 0) {
        $keep = [math]::Max(0.080, 1.5 * $alt)
        if (($uMax - $uMin) -gt 2 * $keep + $alt) { $cortes = @(($uMin + $keep), ($uMax - $keep)) }
        return ,$cortes
    }
    for ($i = 1; $i + 1 -lt $us.Count; $i += 2) {
        $a = [math]::Min([double]$us[$i], [double]$us[$i + 1]); $b = [math]::Max([double]$us[$i], [double]$us[$i + 1])
        $k = $keep
        if (($b - $a - 2 * $k) -lt 0.3 * $alt) { $k = ($b - $a - 0.3 * $alt) / 2 }
        if ($k -lt 0.008) { continue }   # furos muito perto: não cabe quebra
        $cortes += ,@(($a + $k), ($b - $k))
    }
    # pares em ordem crescente, achatados (u1,u2,u1,u2...)
    $res = @(); foreach ($c in ($cortes | Sort-Object { $_[0] })) { $res += $c[0]; $res += $c[1] }
    return ,$res
}
# posição na folha (x) de um ponto u do modelo, descontando os pedaços removidos pelas quebras
function XFolhaQuebrada($u, $cortes, $X0, $esc, $uMin, $g) {
    $x = $X0 + ($u - $uMin) * $esc
    for ($i = 0; $i -lt $cortes.Count / 2; $i++) {
        $c1 = $cortes[2 * $i]; $c2 = $cortes[2 * $i + 1]
        if ($u -ge $c2) { $x -= ($c2 - $c1) * $esc; $x += $g }
    }
    return $x
}
function LayoutMetalon($dm, $front, $end, $dx) {
    # MoverPara usa o contorno do SolidWorks; desloca pela diferença para o contorno calculado
    $oc = ContornoM $front; $or = Contorno $front
    MoverPara $front ($AreaL + 0.016 + $dx + ($or.x1 - $oc.x1)) ($AreaB + 0.030 + $or.h)
    Rebuild $dm
    $of = ContornoM $front
    if ($end) {
        $oe = Contorno $end
        MoverPara $end ($of.x2 + 0.038) ((($of.y1 + $of.y2) / 2) + $oe.h / 2)
        Rebuild $dm
        $oe = Contorno $end
        $dir = $oe.x2
    } else { $dir = $of.x2 }
    return ($dir -le $AreaR - 0.008 -and $of.y2 + $script:alturaCotasMetalon + 0.010 -le $AreaT - 0.004)
}
# em que lado (min/max) do eixo k da peça estão os furos: conta as faces cilíndricas pequenas com eixo k
function LadosFuros($peca, [int]$k) {
    $cb = $script:caixaPeca; $mid = ($cb[$k] + $cb[$k + 3]) / 2
    $nMin = 0; $nMax = 0
    $bodies = $null; try { $bodies = X $peca "GetBodies2" 0 $true } catch { }
    foreach ($b in @($bodies)) {
        if (-not $b) { continue }
        $f = $null; try { $f = X $b "GetFirstFace" } catch { }
        $guarda = 0
        while ($f -and $guarda -lt 5000) {
            $guarda++
            try {
                $sf = X $f "GetSurface"
                if (X $sf "IsCylinder") {
                    $cp = XD (XG $sf "CylinderParams")
                    if ([math]::Abs($cp[3 + $k]) -gt 0.99 -and $cp[6] -lt 0.02) {
                        $bx = XD (X $f "GetBox"); $t = ($bx[$k] + $bx[$k + 3]) / 2
                        if ($t -gt $mid) { $nMax++ } else { $nMin++ }
                    }
                }
            } catch { }
            try { $f = X $f "GetNextFace" } catch { $f = $null }
        }
    }
    return ,@($nMin, $nMax)
}
# cria na peça uma vista nomeada isométrica olhando para o lado dos furos; devolve o nome (ou $null = usar a isométrica padrão)
function IsoDosFuros($peca, $dm, [int]$k) {
    $lados = LadosFuros $peca $k
    $eixos = @("X", "Y", "Z")
    Log "   [dbg] furos no eixo $($eixos[$k]): $($lados[0]) face(s) do lado negativo, $($lados[1]) do lado positivo" "DarkGray"
    if ($lados[1] -gt 0 -or $lados[0] -eq 0) { return $null }   # a isométrica padrão (+X +Y +Z) já mostra os furos
    $d = @(1.0, 1.0, 1.0); $d[$k] = -1.0
    $tituloDrw = Titulo $dm
    try {
        try { X $sw "ActivateDoc" (Titulo $peca) | Out-Null } catch { }
        $mv = XG $peca "ActiveView"
        if (-not $mv) { Log "   (peça sem janela: isométrica padrão)" "DarkGray"; return $null }
        X $peca "ShowNamedView2" "*Isometric" 7 | Out-Null
        $A = XD (XG (XG $mv "Orientation3") "ArrayData")
        # matriz de orientação para a direção d (z da tela = d; "para cima" = Y do modelo)
        function MatrizVista([double[]]$dir) {
            $l = [math]::Sqrt($dir[0] * $dir[0] + $dir[1] * $dir[1] + $dir[2] * $dir[2]); $z = @(($dir[0] / $l), ($dir[1] / $l), ($dir[2] / $l))
            $up = @(0.0, 1.0, 0.0); if ([math]::Abs($z[1]) -gt 0.99) { $up = @(0.0, 0.0, -1.0) }
            $x = @(($up[1] * $z[2] - $up[2] * $z[1]), ($up[2] * $z[0] - $up[0] * $z[2]), ($up[0] * $z[1] - $up[1] * $z[0]))
            $lx = [math]::Sqrt($x[0] * $x[0] + $x[1] * $x[1] + $x[2] * $x[2]); $x = @(($x[0] / $lx), ($x[1] / $lx), ($x[2] / $lx))
            $y = @(($z[1] * $x[2] - $z[2] * $x[1]), ($z[2] * $x[0] - $z[0] * $x[2]), ($z[0] * $x[1] - $z[1] * $x[0]))
            return ,@($x, $y, $z)
        }
        $m0 = MatrizVista @(1.0, 1.0, 1.0)
        $col = @($m0[0][0], $m0[1][0], $m0[2][0], $m0[0][1], $m0[1][1], $m0[2][1], $m0[0][2], $m0[1][2], $m0[2][2])
        $lin = @($m0[0][0], $m0[0][1], $m0[0][2], $m0[1][0], $m0[1][1], $m0[1][2], $m0[2][0], $m0[2][1], $m0[2][2])
        $eC = 0.0; $eL = 0.0; for ($i = 0; $i -lt 9; $i++) { $eC += [math]::Abs($A[$i] - $col[$i]); $eL += [math]::Abs($A[$i] - $lin[$i]) }
        Log ("   [dbg] orientação da isométrica padrão confere: colunas {0:N3} / linhas {1:N3}" -f $eC, $eL) "DarkGray"
        if ([math]::Min($eC, $eL) -gt 0.05) { Log "   (orientação da isométrica não reconhecida: isométrica padrão)" "DarkGray"; return $null }
        $m = MatrizVista $d
        $arr = if ($eC -le $eL) { @($m[0][0], $m[1][0], $m[2][0], $m[0][1], $m[1][1], $m[2][1], $m[0][2], $m[1][2], $m[2][2]) } else { @($m[0][0], $m[0][1], $m[0][2], $m[1][0], $m[1][1], $m[1][2], $m[2][0], $m[2][1], $m[2][2]) }
        $arr += @($A[9], $A[10], $A[11], $A[12], $A[13], $A[14], $A[15])
        $mu = X $sw "GetMathUtility"
        $tr = X $mu "CreateTransform" ([double[]]$arr)
        XS $mv "Orientation3" $tr
        try { X $peca "GraphicsRedraw2" | Out-Null } catch { }
        $B = XD (XG (XG $mv "Orientation3") "ArrayData")
        $eB = 0.0; for ($i = 0; $i -lt 9; $i++) { $eB += [math]::Abs($B[$i] - $arr[$i]) }
        if ($eB -gt 0.05) { Log "   (não consegui girar a vista da peça: isométrica padrão)" "DarkGray"; return $null }
        $nome = "ISO FUROS"
        try { X $peca "DeleteNamedView" $nome | Out-Null } catch { }
        X $peca "NameView" $nome | Out-Null
        Log "   Isométrica virada para o lado dos furos (eixo $($eixos[$k]) negativo)" "DarkGray"
        return $nome
    } finally { try { X $sw "ActivateDoc" $tituloDrw | Out-Null } catch { } }
}
function DetalharMetalon($caminho, $peca, $X, $Y, $Z, $desc) {
    $mx = [math]::Max($X, [math]::Max($Y, $Z))
    # vistas que mostram o comprimento (olham perpendicular ao eixo comprido)
    # as 4 faces compridas (os furos podem estar só de um lado do tubo: a vista do lado oposto não mostra nada)
    if ($X -ge $Y -and $X -ge $Z) { $cands = @(@("*Frontal", "*Front"), @("*Superior", "*Top"), @("*Posterior", "*Back"), @("*Inferior", "*Bottom")) }
    elseif ($Y -ge $Z) { $cands = @(@("*Frontal", "*Front"), @("*Esquerda", "*Left"), @("*Posterior", "*Back"), @("*Direita", "*Right")) }
    else { $cands = @(@("*Superior", "*Top"), @("*Esquerda", "*Left"), @("*Inferior", "*Bottom"), @("*Direita", "*Right")) }
    # espessura da parede pela descrição quando não tem "ESP": 30X70X2MM X 3388MM (3º número pequeno = parede)
    if ($script:espessura -le 0) {
        $mP = [regex]::Match([string]$desc, "(?i)(\d+(?:[\.,]\d+)?)\s*X\s*(\d+(?:[\.,]\d+)?)\s*X\s*(\d+(?:[\.,]\d+)?)")
        if ($mP.Success) { $t3 = [double]($mP.Groups[3].Value.Replace(",", ".")); if ($t3 -gt 0 -and $t3 -lt 12) { $script:espessura = $t3 / 1000; Log ("   Parede do metalon pela descrição: {0} mm" -f $t3) "DarkGray" } }
    }
    $dm = NovoDesenho
    $i0 = EscalaInicial ($mx * 1.2) ($mx * 0.5)
    DefinirEscala $dm $Escalas[$i0][0] $Escalas[$i0][1]
    # a principal é a face onde os furos aparecem de frente (empate: a que mostra o lado maior do perfil)
    $front = $null; $nMelhor = -1; $hMelhor = 0
    foreach ($nm in $cands) {
        $v = VistaModelo $dm $caminho $nm 0.15 0.12
        if (-not $v) { continue }
        Deitar $dm $v
        $script:xfCache = @{}; $script:xfModo = @{}
        Rebuild $dm
        $nf = 0; try { $fv = FurosDaVista $v; $nf = $fv.Count } catch { }
        $lim = LimitesNaVista $v; $h = $lim[1][1] - $lim[1][0]
        Log ("   [dbg] metalon: vista {0} mostra {1} furo(s), perfil {2:N1} mm" -f $nm[0], $nf, ($h * 1000)) "DarkGray"
        if ($nf -gt $nMelhor -or ($nf -eq $nMelhor -and $h -gt $hMelhor + 0.0005)) {
            if ($front) { ApagarVista $dm $front }
            $front = $v; $nMelhor = $nf; $hMelhor = $h
            $script:eixoFuros = if ($nm[0] -like "*Frontal" -or $nm[0] -like "*Posterior") { 2 } elseif ($nm[0] -like "*Superior" -or $nm[0] -like "*Inferior") { 1 } else { 0 }
        } else { ApagarVista $dm $v }
    }
    if (-not $front) { throw "não consegui criar a vista principal do metalon" }
    if ($nMelhor -le 0) {
        # nenhuma vista mostrou furo: diz no log se o 3D tem furos (faces cilíndricas pequenas) e em que eixo
        $tx = @(); foreach ($k in 0, 1, 2) { try { $l = LadosFuros $peca $k; $tx += ("{0}: {1}/{2}" -f @("X", "Y", "Z")[$k], $l[0], $l[1]) } catch { } }
        Log ("   Aviso: nenhuma vista mostrou furos. Faces de furo no 3D por eixo (lado -/+): " + ($tx -join "  ")) "Yellow"
    }
    $script:xfCache = @{}; $script:xfModo = @{}
    $script:mq = @{ on = $false }
    $end = $null
    try { Selecionar $dm $front | Out-Null; $end = X $dm "CreateUnfoldedViewAt3" 0.27 0.12 0.0 $false } catch { Log "   (vista do perfil falhou: $($_.Exception.Message))" "DarkYellow" }
    # isométrica olhando para a face que tem os furos (se os furos estão só do lado "de trás", inverte o lado da vista)
    $iso = $null
    $nomeIso = $null
    if ($nMelhor -gt 0) { try { $nomeIso = IsoDosFuros $peca $dm ([int]$script:eixoFuros) } catch { Log "   (isométrica dos furos: $($_.Exception.Message))" "DarkYellow" } }
    if ($nomeIso) { $iso = VistaModelo $dm $caminho @($nomeIso) 0.15 0.17 }
    if (-not $iso) { $iso = VistaModelo $dm $caminho @("*Isométrica", "*Isometric") 0.15 0.17 }
    Modo $front $DispHidden $true
    if ($end) { Modo $end $DispHidden $true }
    if ($iso) { Modo $iso $DispShaded $true }
    Rebuild $dm
    Log ("   Metalon: vista lateral comprida + perfil" + $(if ($end) { " ok" } else { " FALHOU" }) + " + isométrica" + $(if ($iso) { " ok" } else { " FALHOU" }))

    # furos e quebras
    $lim = LimitesNaVista $front
    $uMin = $lim[0][0]; $uMax = $lim[0][1]; $alt = $lim[1][1] - $lim[1][0]
    $furos = FurosDaVista $front
    $us = @(); foreach ($h in ($furos | Sort-Object { $_[2][0] })) { if (-not ($us | Where-Object { [math]::Abs($_ - $h[2][0]) -lt 0.0002 })) { $us += $h[2][0] } }
    # ponta de referência: a que fica com o 1º furo mais perto de 23 mm (padrão ProEstamp); os pares de furos contam a partir dela
    $script:metalonDir = $false
    if ($us.Count -gt 0) { $script:metalonDir = ([math]::Abs(($uMax - $us[$us.Count - 1]) - 0.023) -lt [math]::Abs(($us[0] - $uMin) - 0.023)) }
    $usRef = if ($script:metalonDir) { @($us | Sort-Object -Descending) } else { $us }
    $cortes = CortesMetalon $usRef $uMin $uMax $alt
    # cotas dos furos empilhadas acima da vista (todas a partir da mesma ponta) + comprimento total no topo
    # cotas dos furos todas na mesma linha; acima delas o comprimento total (e, se precisar, a distância dentro de um par diferente)
    $script:passoCotasMetalon = 0.0075
    $script:alturaCotasMetalon = $DistCota + 2 * $script:passoCotasMetalon + 0.006
    Log ("   [dbg] metalon: {0} furo(s) em {1} posição(ões) ao longo do comprimento; {2} quebra(s) planejada(s)" -f $furos.Count, $us.Count, [int]($cortes.Count / 2)) "DarkGray"
    $quebrada = $false
    if ($cortes.Count -ge 2) { $quebrada = QuebrarVista $dm $front $cortes $lim }
    if (-not $quebrada) { $cortes = @() }
    $rem = 0.0; for ($i = 0; $i -lt $cortes.Count / 2; $i++) { $rem += $cortes[2 * $i + 1] - $cortes[2 * $i] }

    # escala: a maior em que a principal (quebrada) + o perfil cabem na largura; a isométrica ocupa o espaço de cima
    $sAtual = [double]$Escalas[$i0][0] / $Escalas[$i0][1]
    try { $sAtual = [double](XG $front "ScaleDecimal") } catch { }
    # largura necessária = folgas + comprimento que sobra depois das quebras x escala + vãos das quebras + perfil
    $oF = Contorno $front; $padF = [math]::Max(0.0, ($oF.h - $alt * $sAtual) / 2)
    $nbq = [int]($cortes.Count / 2); $remq = 0.0; for ($i = 0; $i -lt $nbq; $i++) { $remq += $cortes[2 * $i + 1] - $cortes[2 * $i] }
    $profW = 0.0; $padE = 0.0
    if ($end) { $oE = Contorno $end; $profW = [math]::Min($lim[1][1] - $lim[1][0], $oE.w / $sAtual); $padE = [math]::Max(0.0, ($oE.h - $alt * $sAtual) / 2); $profW = [math]::Max(0.0, ($oE.w - 2 * $padE) / $sAtual) }
    $livre = ($AreaR - 0.008) - ($AreaL + 0.016) - 2 * $padF - $nbq * $script:gapQuebra - $(if ($end) { 2 * $padE + 0.038 } else { 0 })
    $sEst = $livre / [math]::Max(($uMax - $uMin) - $remq + $profW, 0.001)
    Log ("   [dbg] metalon: comprimento visível {0:N0} mm; escala estimada 1:{1:N1}" -f ((($uMax - $uMin) - $remq) * 1000), (1 / [math]::Max($sEst, 1e-6))) "DarkGray"
    $iE = $Escalas.Count - 1
    for ($i = 0; $i -lt $Escalas.Count; $i++) { if (($Escalas[$i][0] / $Escalas[$i][1]) -le $sEst * 1.02) { $iE = $i; break } }
    $ok = $false
    for ($i = $iE; $i -lt $Escalas.Count -and -not $ok; $i++) {
        DefinirEscala $dm $Escalas[$i][0] $Escalas[$i][1]
        if (LayoutMetalon $dm $front $end 0) { $ok = $true; $sAtual = [double]$Escalas[$i][0] / $Escalas[$i][1]; Log "   Escala $($Escalas[$i][0]):$($Escalas[$i][1]) (metalon$(if ($quebrada) { ' com quebras' }))" }
    }
    if (-not $ok) { Log "   Aviso: as vistas do metalon não couberam perfeitamente; confira a disposição." "Yellow" }
    # centraliza o conjunto principal + perfil na largura
    $of = ContornoM $front; $dirX = if ($end) { (Contorno $end).x2 } else { $of.x2 }
    $sobra = ($AreaR - 0.008) - $dirX
    if ($sobra -gt 0.004) { LayoutMetalon $dm $front $end ($sobra / 2) | Out-Null }
    $cr = Contorno $front; $cm = ContornoM $front
    Log ("   [dbg] principal: contorno SolidWorks x {0:N1}..{1:N1} mm; calculado {2:N1}..{3:N1} mm" -f ($cr.x1 * 1000), ($cr.x2 * 1000), ($cm.x1 * 1000), ($cm.x2 * 1000)) "DarkGray"

    # isométrica: o maior possível no espaço acima das cotas
    if ($iso) {
        try {
            $of = Contorno $front; $topo = $of.y2
            if ($end) { $topo = [math]::Max($topo, (Contorno $end).y2) }
            $y1 = (Contorno $front).y2 + $script:alturaCotasMetalon + 0.006; if ($end) { $y1 = [math]::Max($y1, (Contorno $end).y2 + 0.020) }; $y2 = $AreaT - 0.004
            $wD = ($AreaR - $AreaL) - 0.020; $hD = [math]::Max($y2 - $y1, 0.025)
            try { XS $iso "UseSheetScale" $false } catch { try { XS $iso "UseSheetScale" 0 } catch { } }
            $si = $sAtual * 0.5; try { XS $iso "ScaleDecimal" $si } catch { }
            Rebuild $dm
            $oi = Contorno $iso
            $f = [math]::Min($wD / [math]::Max($oi.w, 0.001), $hD / [math]::Max($oi.h, 0.001)) * 0.95
            $si = [math]::Min($si * $f, $sAtual)
            XS $iso "ScaleDecimal" $si; Rebuild $dm
            $oi = Contorno $iso
            MoverPara $iso ((($AreaL + $AreaR) / 2) - $oi.w / 2) $y2
            Rebuild $dm
        } catch { Log "   (isométrica do metalon: $($_.Exception.Message))" "DarkYellow" }
    }
    $script:isoAtual = $iso

    if ($InserirCotas) {
        $tgl = K "swUserPreferenceToggle_e" @("swInputDimValOnCreate") 10
        $antes = $null
        try { $antes = X $sw "GetUserPreferenceToggle" $tgl; X $sw "SetUserPreferenceToggle" $tgl $false | Out-Null } catch { }
        try { CotasMetalon $dm $front $end $cortes $quebrada } catch { Log "   Aviso: cotas do metalon falharam ($($_.Exception.Message))" "Yellow" }
        finally { if ($null -ne $antes) { try { X $sw "SetUserPreferenceToggle" $tgl ([bool]$antes) | Out-Null } catch { } } }
    }
    return $dm
}
function CentroTexto($dd) {
    if (-not $dd) { return }
    try { XS $dd "CenterText" $true } catch { }
}
# põe o texto de cada cota no meio das suas linhas de chamada e todas na mesma altura.
# Os pontos medidos vêm da própria cota (IDimension.ReferencePoints, já na folha e já considerando as quebras).
function PontosCota($dd) {
    try {
        $dim = X $dd "GetDimension2" 0
        $rp = XG $dim "ReferencePoints"
        $res = @()
        foreach ($mp in @($rp)) { if ($mp) { $res += ,([double[]](XD (XG $mp "ArrayData"))) } }
        return ,$res
    } catch { return ,@() }
}
function AlinharCotas($dm, $linha, $y, [bool]$pontaDireita) {
    $ok = 0; $dbg = $true
    foreach ($it in $linha) {
        $dd = $it[0]; $daPonta = [bool]$it[1]
        # posição na folha dos dois pontos medidos, calculada com as quebras (o contorno da vista já vem quebrado)
        $xa = [double]$it[2]; $xb = [double]$it[3]
        if ($dbg) { Log ("   [dbg] 1ª cota: pontos em x = {0:N1} e {1:N1} mm" -f ($xa * 1000), ($xb * 1000)) "DarkGray"; $dbg = $false }
        $x = ($xa + $xb) / 2
        $vao = [math]::Abs($xb - $xa)
        # cota curta (ex.: 23 da ponta): texto do lado de fora, na direção da ponta
        if ($vao -lt 0.009 -and $daPonta) {
            $ext = if ($pontaDireita) { [math]::Max($xa, $xb) + 0.006 } else { [math]::Min($xa, $xb) - 0.006 }
            $x = $ext
        }
        try { $an = X $dd "GetAnnotation"; X $an "SetPosition" ([double]$x) ([double]$y) 0.0 | Out-Null; $ok++ } catch { }
    }
    Log "   Cotas dos furos alinhadas/centralizadas: $ok de $($linha.Count)" "DarkGray"
}
function CotasMetalon($dm, $front, $end, $cortes, $quebrada) {
    $script:xfCache = @{}; $script:xfModo = @{}
    $a = DadosXf $front
    $lim = LimitesNaVista $front
    $uMin = $lim[0][0]; $uMax = $lim[0][1]; $vMin = $lim[1][0]; $vMax = $lim[1][1]
    $esc = [double](XG $front "ScaleDecimal")
    $o = ContornoM $front
    # folga do contorno (igual nos 4 lados) e tamanho do vão de cada quebra, na folha
    $pad = [math]::Max(0.0, ($o.h - ($vMax - $vMin) * $esc) / 2)
    $nb = [int]($cortes.Count / 2); $rem = 0.0; for ($i = 0; $i -lt $nb; $i++) { $rem += $cortes[2 * $i + 1] - $cortes[2 * $i] }
    $g = 0.0; if ($nb -gt 0) { $g = [math]::Max(0.0, ($o.w - 2 * $pad - (($uMax - $uMin) - $rem) * $esc) / $nb) }
    if ($nb -gt 0 -and ($g -le 0 -or $g -gt 0.03)) { $g = $script:gapQuebra }
    $X0 = $o.x1 + $pad
    $topoPeca = $o.y2 - $pad; $esqPeca = $o.x1 + $pad
    # vértices (cantos das pontas do tubo)
    $pts = @()
    foreach ($vx in (Entidades $front "swViewEntityType_Vertex" 3)) { try { $pm = [double[]](XD (X $vx "GetPoint")); $pts += ,@($vx, (Rot $a $pm)) } catch { } }
    $n = 0; $tol = 0.0003
    if ($pts.Count -ge 2) {
        $minU = ($pts | ForEach-Object { $_[1][0] } | Measure-Object -Minimum).Minimum
        $maxU = ($pts | ForEach-Object { $_[1][0] } | Measure-Object -Maximum).Maximum
        $esqAlto = @($pts | Where-Object { $_[1][0] -le $minU + $tol } | Sort-Object { $_[1][1] })[-1]
        $esqBaixo = @($pts | Where-Object { $_[1][0] -le $minU + $tol } | Sort-Object { $_[1][1] })[0]
        $dirAlto = @($pts | Where-Object { $_[1][0] -ge $maxU - $tol } | Sort-Object { $_[1][1] })[-1]
        $furos = FurosDaVista $front
        $pos = @()
        foreach ($h in ($furos | Sort-Object { $_[2][0] })) { if (-not ($pos | Where-Object { [math]::Abs($_[2][0] - $h[2][0]) -lt 0.0002 })) { $pos += ,$h } }
        $passo = [double]$script:passoCotasMetalon; if ($passo -le 0) { $passo = 0.0075 }
        $usaDir = [bool]$script:metalonDir
        if ($pos.Count -gt 0) { Log ("   [dbg] metalon: 1º furo a {0:N1} mm da ponta esquerda e {1:N1} mm da direita; referência = ponta {2}" -f (($pos[0][2][0] - $minU) * 1000), (($maxU - $pos[$pos.Count - 1][2][0]) * 1000), $(if ($usaDir) { "direita" } else { "esquerda" })) "DarkGray" }
        $refE = if ($usaDir) { $dirAlto[0] } else { $esqAlto[0] }
        $refU = if ($usaDir) { $maxU } else { $minU }
        $ordem = if ($usaDir) { @($pos | Sort-Object { -$_[2][0] }) } else { @($pos) }
        # padrão ProEstamp (gabarito de furação 250/500/1000): ponta -> 1º furo, 1º -> 2º (o par),
        # e depois do 2º furo de um par ao 2º furo do par seguinte; tudo numa linha só
        $alvos = @()
        if ($ordem.Count -ge 1) { $alvos += 0 }
        if ($ordem.Count -ge 2) { $alvos += 1 }
        for ($t = 3; $t -lt $ordem.Count; $t += 2) { $alvos += $t }
        if ($ordem.Count -gt 2 -and ($alvos -notcontains ($ordem.Count - 1))) { $alvos += ($ordem.Count - 1) }
        $yLinha = $topoPeca + $DistCota
        $linha = @()
        $nc = 0; $antE = $refE; $antU = $refU
        foreach ($t in $alvos) {
            $h = $ordem[$t]
            X $dm "ClearSelection2" $true | Out-Null
            SelecionarEntidade $dm $front $antE $false | Out-Null; SelecionarEntidade $dm $front $h[0] $true | Out-Null
            if ((QtdSelecionados $dm) -eq 2) {
                $xa = XFolhaQuebrada $antU $cortes $X0 $esc $uMin $g; $xb = XFolhaQuebrada $h[2][0] $cortes $X0 $esc $uMin $g
                try { $dd = X $dm "AddHorizontalDimension2" ([double](($xa + $xb) / 2)) ([double]$yLinha) 0.0; if ($dd) { $n++; $nc++; CentroTexto $dd; $linha += ,@($dd, ($nc -eq 1), $xa, $xb) } } catch { }
            }
            $antE = $h[0]; $antU = $h[2][0]
        }
        AlinharCotas $dm $linha $yLinha $usaDir
        # par com distância diferente do 1º par: cota a distância dentro dele numa 2ª linha
        $nPar = 0; $yPar = $yLinha + $passo
        if ($ordem.Count -ge 2) {
            $d0 = [math]::Abs($ordem[1][2][0] - $ordem[0][2][0])
            for ($t = 2; $t + 1 -lt $ordem.Count; $t += 2) {
                $dk = [math]::Abs($ordem[$t + 1][2][0] - $ordem[$t][2][0])
                if ([math]::Abs($dk - $d0) -lt 0.0003) { continue }
                X $dm "ClearSelection2" $true | Out-Null
                SelecionarEntidade $dm $front $ordem[$t][0] $false | Out-Null; SelecionarEntidade $dm $front $ordem[$t + 1][0] $true | Out-Null
                if ((QtdSelecionados $dm) -ne 2) { continue }
                $xa = XFolhaQuebrada $ordem[$t][2][0] $cortes $X0 $esc $uMin $g; $xb = XFolhaQuebrada $ordem[$t + 1][2][0] $cortes $X0 $esc $uMin $g
                try { $dd = X $dm "AddHorizontalDimension2" ([double](($xa + $xb) / 2)) ([double]$yPar) 0.0; if ($dd) { $n++; $nPar++; CentroTexto $dd } } catch { }
            }
        }
        # comprimento total acima
        $yTot = $yLinha + $(if ($nc -gt 0) { $passo } else { 0 }) + $(if ($nPar -gt 0) { $passo } else { 0 })
        X $dm "ClearSelection2" $true | Out-Null
        SelecionarEntidade $dm $front $esqAlto[0] $false | Out-Null; SelecionarEntidade $dm $front $dirAlto[0] $true | Out-Null
        if ((QtdSelecionados $dm) -eq 2) { try { $dd = X $dm "AddHorizontalDimension2" ([double](($o.x1 + $o.x2) / 2)) ([double]$yTot) 0.0; if ($dd) { $n++; CentroTexto $dd } } catch { } }
        # altura do(s) furo(s): na ponta de referência, a partir da aresta (de baixo ou de cima) mais perto do furo
        $dirBaixo = @($pts | Where-Object { $_[1][0] -ge $maxU - $tol } | Sort-Object { $_[1][1] })[0]
        $xPonta = if ($usaDir) { (XFolhaQuebrada $maxU $cortes $X0 $esc $uMin $g) } else { $esqPeca }
        $vs = @()
        foreach ($h in ($furos | Sort-Object { $_[2][1] })) { if (-not ($vs | Where-Object { [math]::Abs($_[2][1] - $h[2][1]) -lt 0.0002 })) { $vs += ,$h } }
        $k = 0
        foreach ($h in $vs) {
            X $dm "ClearSelection2" $true | Out-Null
            $deBaixo = (($h[2][1] - $vMin) -le ($vMax - $h[2][1]))
            $vtx = if ($usaDir) { if ($deBaixo) { $dirBaixo } else { $dirAlto } } else { if ($deBaixo) { $esqBaixo } else { $esqAlto } }
            SelecionarEntidade $dm $front $vtx[0] $false | Out-Null; SelecionarEntidade $dm $front $h[0] $true | Out-Null
            if ((QtdSelecionados $dm) -ne 2) { continue }
            $yb = $o.y1 + $pad; $yt = $o.y2 - $pad; $yh = $yb + ($h[2][1] - $vMin) * $esc
            $yRef = if ($deBaixo) { $yb } else { $yt }
            $xc = if ($usaDir) { $xPonta + $DistCota + $k * 0.008 } else { $xPonta - $DistCota - $k * 0.008 }
            try { $dd = X $dm "AddVerticalDimension2" ([double]$xc) ([double](($yRef + $yh) / 2)) 0.0; if ($dd) { $n++; $k++; CentroTexto $dd } } catch { }
        }
        Log "   Cotas do metalon: comprimento + $nc na linha dos furos (ponta, par e passo entre pares)$(if ($nPar) { " + $nPar de par diferente" }) + $k altura(s) de furo"
    } else { $n += CotaTotal $dm $front $true $false }
    X $dm "ClearSelection2" $true | Out-Null
    # chamada de furo embaixo à esquerda ("14 x Ø9,50 PASSANTE")
    $f = 0; try { $f = ChamadasFuro $dm $front } catch { Log "   (chamada de furo: $($_.Exception.Message))" "DarkYellow" }
    # perfil: largura (em cima), altura (à esquerda) e parede (embaixo)
    if ($end) {
        $ne = 0
        try { $ne = CotaTotal $dm $end $true $true } catch { }
        $ep = 0; try { $ep = CotaEspessura $dm @($end) } catch { }
        Log "   Perfil do metalon: $ne cota(s) + $(if ($ep) { 'parede' } else { 'SEM parede (espessura não achada)' })"
    }
    Log "   Chamada(s) de furo: $f"
    Rebuild $dm
    ResolverSobreposicoes $dm @($front, $end, $script:isoAtual) @("furo")
}
