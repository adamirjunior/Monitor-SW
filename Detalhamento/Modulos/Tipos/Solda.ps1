# Solda.ps1 - submontagem de solda: isométrica, lista de peças, balões (padrão 13011773)
# Carregado pelo DetalharSW.ps1 (dot-source). Não rodar sozinho.

# ---------------------------------------------------------------- submontagem de solda
# template da lista de materiais de solda: o configurado no .ini; senão um salvo na pasta do gerador;
# senão cria agora a partir do desenho de referência (13011773 na mesma pasta da montagem, ou DesenhoReferenciaSolda no .ini)
# ---------------------------------------------------------------- forma da vista (solda)
# contorno convexo (na folha) da caixa da montagem projetada na vista: aproxima a forma real da isométrica
function HullVista($v, $b) {
    $a = DadosXf $v
    $esc = 1.0; try { $esc = [double](XG $v "ScaleDecimal") } catch { }
    $pts = @()
    foreach ($cx in $b[0], $b[3]) { foreach ($cy in $b[1], $b[4]) { foreach ($cz in $b[2], $b[5]) { $pts += ,(Rot $a @($cx, $cy, $cz)) } } }
    $rx = @($pts | ForEach-Object { $_[0] }); $ry = @($pts | ForEach-Object { $_[1] })
    $rcx = (($rx | Measure-Object -Minimum).Minimum + ($rx | Measure-Object -Maximum).Maximum) / 2
    $rcy = (($ry | Measure-Object -Minimum).Minimum + ($ry | Measure-Object -Maximum).Maximum) / 2
    $o = Contorno $v; $ocx = ($o.x1 + $o.x2) / 2; $ocy = ($o.y1 + $o.y2) / 2
    $sp = @(); foreach ($p in $pts) { $sp += ,@(($ocx + ($p[0] - $rcx) * $esc), ($ocy + ($p[1] - $rcy) * $esc)) }
    # casco convexo (monotone chain)
    $sp = @($sp | Sort-Object { $_[0] }, { $_[1] })
    $cross = { param($o1, $a1, $b1) (($a1[0] - $o1[0]) * ($b1[1] - $o1[1])) - (($a1[1] - $o1[1]) * ($b1[0] - $o1[0])) }
    $lo = New-Object System.Collections.ArrayList; $up = New-Object System.Collections.ArrayList
    foreach ($p in $sp) { while ($lo.Count -ge 2 -and (& $cross $lo[$lo.Count - 2] $lo[$lo.Count - 1] $p) -le 0) { $lo.RemoveAt($lo.Count - 1) }; [void]$lo.Add($p) }
    for ($k = $sp.Count - 1; $k -ge 0; $k--) { $p = $sp[$k]; while ($up.Count -ge 2 -and (& $cross $up[$up.Count - 2] $up[$up.Count - 1] $p) -le 0) { $up.RemoveAt($up.Count - 1) }; [void]$up.Add($p) }
    $h = @(); for ($k = 0; $k -lt $lo.Count - 1; $k++) { $h += ,$lo[$k] }; for ($k = 0; $k -lt $up.Count - 1; $k++) { $h += ,$up[$k] }
    return ,$h
}
function DistPontoRet($x, $y, $r) {
    $dx = [math]::Max([math]::Max([double]($r.x1 - $x), 0.0), [double]($x - $r.x2)); $dy = [math]::Max([math]::Max([double]($r.y1 - $y), 0.0), [double]($y - $r.y2))
    return [math]::Sqrt($dx * $dx + $dy * $dy)
}
function DentroPoligono($x, $y, $h) {
    $sinal = 0
    for ($k = 0; $k -lt $h.Count; $k++) {
        $p = $h[$k]; $q = $h[($k + 1) % $h.Count]
        $c = (($q[0] - $p[0]) * ($y - $p[1])) - (($q[1] - $p[1]) * ($x - $p[0]))
        if ([math]::Abs($c) -lt 1e-12) { continue }
        $sg = [math]::Sign($c); if ($sinal -eq 0) { $sinal = $sg } elseif ($sg -ne $sinal) { return $false }
    }
    return $true
}
function DistSeg($px, $py, $ax, $ay, $bx, $by) {
    $vx = $bx - $ax; $vy = $by - $ay; $l2 = $vx * $vx + $vy * $vy
    $t = 0.0; if ($l2 -gt 0) { $t = [math]::Max(0.0, [math]::Min(1.0, [double]((($px - $ax) * $vx + ($py - $ay) * $vy) / $l2))) }
    $qx = $ax + $t * $vx - $px; $qy = $ay + $t * $vy - $py
    return [math]::Sqrt($qx * $qx + $qy * $qy)
}
# distância entre o casco (deslocado de dx,dy) e um retângulo; negativa = encosta/invade
function DistHullRet($h, $dx, $dy, $r) {
    $m = 1e9
    foreach ($p in $h) { $d = DistPontoRet ($p[0] + $dx) ($p[1] + $dy) $r; if ($d -le 0) { return -1 }; if ($d -lt $m) { $m = $d } }
    $cant = @(@($r.x1, $r.y1), @($r.x2, $r.y1), @($r.x2, $r.y2), @($r.x1, $r.y2))
    $hs = @(); foreach ($p in $h) { $hs += ,@(($p[0] + $dx), ($p[1] + $dy)) }
    foreach ($c in $cant) {
        if (DentroPoligono $c[0] $c[1] $hs) { return -1 }
        for ($k = 0; $k -lt $hs.Count; $k++) { $p = $hs[$k]; $q = $hs[($k + 1) % $hs.Count]; $d = DistSeg $c[0] $c[1] $p[0] $p[1] $q[0] $q[1]; if ($d -lt $m) { $m = $d } }
    }
    return $m
}
# procura a posição da vista (deslocamento dx,dy) que deixa a forma dentro da área útil, longe da lista,
# com a maior folga possível (fica bem distribuída na folha); null = não cabe nesta escala
function MelhorPosicaoVista($v, $b, $mesa, $margem) {
    $h = HullVista $v $b
    if ($h.Count -lt 3) { return $null }
    $hx1 = ($h | ForEach-Object { $_[0] } | Measure-Object -Minimum).Minimum; $hx2 = ($h | ForEach-Object { $_[0] } | Measure-Object -Maximum).Maximum
    $hy1 = ($h | ForEach-Object { $_[1] } | Measure-Object -Minimum).Minimum; $hy2 = ($h | ForEach-Object { $_[1] } | Measure-Object -Maximum).Maximum
    $lim1 = $AreaL + $margem; $lim2 = $AreaR - $margem; $lim3 = $AreaB + $margem; $lim4 = $AreaT - $margem
    if (($hx2 - $hx1) -gt ($lim2 - $lim1) -or ($hy2 - $hy1) -gt ($lim4 - $lim3)) { return $null }
    $melhor = $null; $passo = 0.004
    for ($nx = $lim1; $nx + ($hx2 - $hx1) -le $lim2 + 1e-9; $nx += $passo) {
        for ($ny = $lim3; $ny + ($hy2 - $hy1) -le $lim4 + 1e-9; $ny += $passo) {
            $dx = $nx - $hx1; $dy = $ny - $hy1
            $dmesa = DistHullRet $h $dx $dy $mesa
            if ($dmesa -lt $margem) { continue }
            # folga: a menor distância até a lista e até as bordas da área útil
            $f = [math]::Min($dmesa, [math]::Min([math]::Min($nx - $AreaL, $AreaR - ($nx + $hx2 - $hx1)), [math]::Min($ny - $AreaB, $AreaT - ($ny + $hy2 - $hy1))))
            if (-not $melhor -or $f -gt $melhor.folga) { $melhor = [pscustomobject]@{ dx = $dx; dy = $dy; folga = $f } }
        }
    }
    return $melhor
}

# balões da solda em fileiras alinhadas: os que ficam "acima" da diagonal da vista vão para uma fileira em cima,
# os outros para uma fileira embaixo; cada fileira em ordem do ponto de ligação (linhas de chamada sem cruzar),
# com espaço entre eles; se não couber numa fileira, alterna em duas alturas
function PontoBalao($n) {
    $an = AnnOf $n
    try { $lp = XD (X $an "GetLeaderPointsAtIndex" 0); if ($lp -and $lp.Count -ge 2) { return @($lp[0], $lp[1]) } } catch { }
    try { $ap = XD (X $n "GetAttachPos"); if ($ap -and $ap.Count -ge 2) { return @($ap[0], $ap[1]) } } catch { }
    $r = RetNota $n; if ($r) { return @((($r.x1 + $r.x2) / 2), (($r.y1 + $r.y2) / 2)) }
    return $null
}
function OrganizarBaloes($dm, $v, $notas) {
    # "escadinha": os balões de cada lado da peça ficam numa linha paralela ao comprimento da isométrica,
    # fora da forma da peça, na ordem das peças e com espaçamento igual (linhas de chamada paralelas, sem cruzar)
    $h = $script:hullSolda
    if (-not $h -or $h.Count -lt 3) { $o = Contorno $v; $h = @(@($o.x1, $o.y1), @($o.x2, $o.y1), @($o.x2, $o.y2), @($o.x1, $o.y2)) }
    # eixo comprido = par de vértices mais distantes do contorno
    $best = -1; $pa = $h[0]; $pb = $h[1]
    for ($i = 0; $i -lt $h.Count; $i++) { for ($k = $i + 1; $k -lt $h.Count; $k++) { $ddx = $h[$k][0] - $h[$i][0]; $ddy = $h[$k][1] - $h[$i][1]; $dd = $ddx * $ddx + $ddy * $ddy; if ($dd -gt $best) { $best = $dd; $pa = $h[$i]; $pb = $h[$k] } } }
    if ($pb[0] -lt $pa[0]) { $tmp = $pa; $pa = $pb; $pb = $tmp }
    $L = [math]::Sqrt($best); if ($L -lt 1e-6) { return }
    $ux = ($pb[0] - $pa[0]) / $L; $uy = ($pb[1] - $pa[1]) / $L
    $nx = -$uy; $ny = $ux
    $cx = ($h | ForEach-Object { $_[0] } | Measure-Object -Average).Average; $cy = ($h | ForEach-Object { $_[1] } | Measure-Object -Average).Average
    # quanto a forma se estende para cada lado da linha central
    $dsup = 0.0; $dinf = 0.0
    foreach ($p in $h) { $d = ($p[0] - $cx) * $nx + ($p[1] - $cy) * $ny; if ($d -gt $dsup) { $dsup = $d }; if (-$d -gt $dinf) { $dinf = -$d } }
    $its = @()
    foreach ($n in $notas) {
        if (-not $n) { continue }
        $r = RetNota $n; if (-not $r) { continue }
        $p = PontoBalao $n; if (-not $p) { continue }
        $t = ($p[0] - $cx) * $ux + ($p[1] - $cy) * $uy; $d = ($p[0] - $cx) * $nx + ($p[1] - $cy) * $ny
        $its += ,[pscustomobject]@{ n = $n; r = $r; t = $t; d = $d; w = ($r.x2 - $r.x1); h = ($r.y2 - $r.y1) }
    }
    if ($its.Count -eq 0) { return }
    $mesa = $script:mesaSolda
    $mov = 0
    foreach ($lado in 1, -1) {
        $fila = @($its | Where-Object { [math]::Sign($_.d + 1e-9) -eq $lado } | Sort-Object t)
        if ($fila.Count -eq 0) { continue }
        $off = $(if ($lado -gt 0) { $dsup } else { $dinf }) + 0.010
        $t1 = ($fila | Measure-Object -Property t -Minimum).Minimum; $t2 = ($fila | Measure-Object -Property t -Maximum).Maximum
        $passo = 0.0
        if ($fila.Count -gt 1) {
            $larg = ($fila | Measure-Object -Property w -Maximum).Maximum
            $passo = [math]::Max(($t2 - $t1) / ($fila.Count - 1), $larg * [math]::Abs($ux) * 0.9 + 0.006)
            $meio = ($t1 + $t2) / 2; $t1 = $meio - $passo * ($fila.Count - 1) / 2
        }
        for ($k = 0; $k -lt $fila.Count; $k++) {
            $it = $fila[$k]
            $tk = $t1 + $k * $passo
            $px = $cx + $tk * $ux + $lado * $off * $nx; $py = $cy + $tk * $uy + $lado * $off * $ny
            if ($lado -gt 0) { $x1 = $px - $it.w; $y1 = $py } else { $x1 = $px; $y1 = $py - $it.h }
            $x1 = [math]::Max($AreaL + 0.004, [math]::Min($AreaR - 0.004 - $it.w, $x1))
            $y1 = [math]::Max($AreaB + 0.004, [math]::Min($AreaT - 0.004 - $it.h, $y1))
            # não pode ficar em cima da lista de materiais: sobe para logo acima dela
            if ($mesa -and $x1 + $it.w -gt $mesa.x1 - 0.002 -and $y1 -lt $mesa.y2 + 0.003) { $y1 = $mesa.y2 + 0.004 }
            try {
                MoverNota $it.n ($x1 - $it.r.x1) ($y1 - $it.r.y1); $mov++
                if ($mov -eq 1) { $r2 = RetNota $it.n; Log ("   [dbg] 1º balão: era ({0:N1};{1:N1}) mm, pedido ({2:N1};{3:N1}), ficou ({4:N1};{5:N1})" -f ($it.r.x1 * 1000), ($it.r.y1 * 1000), ($x1 * 1000), ($y1 * 1000), ($r2.x1 * 1000), ($r2.y1 * 1000)) "DarkGray" }
            } catch { Log "   (mover balão: $($_.Exception.Message))" "DarkYellow" }
        }
    }
    Log "   $mov balão(ões) em escadinha, paralelos à peça" "DarkGray"
}
# deixa o desenho como documento ativo do SolidWorks (balões automáticos só funcionam no documento ativo).
# O título de desenho vem como "Desenho3 - Folha1": o ActivateDoc quer só "Desenho3".
function TemplateSolda($caminhoAsm) {
    if ($TabelaSolda -and (Test-Path $TabelaSolda)) { return $TabelaSolda }
    $tpl = Join-Path $Pasta "ListaSolda_ProEstamp.sldbomtbt"
    if (Test-Path $tpl) { return $tpl }
    $ref = C "DesenhoReferenciaSolda" ""
    if (-not $ref -or -not (Test-Path $ref)) { $ref = Join-Path (Split-Path -Parent $caminhoAsm) "13011773.SLDDRW" }
    if (-not (Test-Path $ref)) { Log "   (desenho de referência da lista de solda não encontrado: $ref)" "DarkYellow"; return "" }
    $jaAberto = $null; try { $jaAberto = X $sw "GetOpenDocumentByName" $ref } catch { }
    $d = AbrirDoc $ref $DocDRW
    if (-not $d) { return "" }
    $tipoBom = K "swTableAnnotationType_e" @("swTableAnnotation_BillOfMaterials") 2
    $salvou = $false
    try {
        $v = X $d "GetFirstView"
        while ($v -and -not $salvou) {
            $tas = $null; try { $tas = X $v "GetTableAnnotations" } catch { }
            foreach ($t in @($tas)) {
                if (-not $t) { continue }
                $tp = -1; try { $tp = [int](XG $t "Type") } catch { }
                if ($tp -eq $tipoBom) { try { $salvou = [bool](X $t "SaveAsTemplate" $tpl) } catch { Log "   (SaveAsTemplate: $($_.Exception.Message))" "DarkYellow" }; if ($salvou) { break } }
            }
            $v = X $v "GetNextView"
        }
    } catch { Log "   (lendo a lista do desenho de referência: $($_.Exception.Message))" "DarkYellow" }
    if (-not $jaAberto) { Fechar $d }
    if ($salvou -and (Test-Path $tpl)) { Log "   Template da lista de solda criado a partir de $(Split-Path -Leaf $ref): $tpl" "Green"; return $tpl }
    Log "   (não consegui salvar o template da lista a partir de $(Split-Path -Leaf $ref))" "DarkYellow"
    return ""
}
function DetalharMontagem($caminho, $asm) {
    $cod = Codigo $caminho
    $destDir = PastaDestino $caminho
    $drwPath = Join-Path $destDir "$cod.SLDDRW"
    if ((Test-Path $drwPath) -and -not $Sobrescrever) { Log "   Já existe $drwPath (Sobrescrever=não). Pulando criação." "Yellow"; Relatorio $caminho "montagem" "detalhar" "pulado" "desenho já existe"; return }
    ValidarPropriedades $asm $caminho   # DESCRIÇÃO, ACABAMENTO e um processo preenchidos (senão avisa e não detalha)
    $clsM = ClassificarMontagem $caminho $asm   # 3.1 sem usinagem | 3.2 com usinagem
    if ($Modo -ne "gerar") { $script:FazPdf = $true }   # pelo Monitor vale o que o usuário marcou
    if (-not $clsM.EhSolda) { Log "   Aviso: não é solda pelas regras (código 1301.../descrição SOLDA/pasta); vou detalhar igual (isométrica + lista)." "Yellow" }
    if ($clsM.Usinagem) { Log "   3.2: montagem de solda com usinagem - cotas do padrão de furos ainda não automáticas (PENDENTE)." "Yellow" }

    try { $real = [string](X $asm "GetPathName"); if ($real) { $caminho = $real } } catch { }
    try { X $asm "ResolveAllLightWeightComponents" $false | Out-Null } catch { }
    $b = XD (X $asm "GetBox" 0)
    $X = [math]::Abs($b[3] - $b[0]); $Y = [math]::Abs($b[4] - $b[1]); $Z = [math]::Abs($b[5] - $b[2])
    $diag = [math]::Sqrt($X * $X + $Y * $Y + $Z * $Z)
    try { X $sw "ActivateDoc" (Titulo $asm) | Out-Null } catch { Log "   (ActivateDoc: $($_.Exception.Message))" "DarkGray" }
    try { $nc = X $asm "GetComponentCount" $false; Log "   Componentes: $nc" "DarkGray" } catch { }
    $dm = NovoDesenho
    # montagem: criar a vista pelo título do documento aberto (pelo caminho o SolidWorks 2016 dá erro interno)
    $refAsm = Titulo $asm
    $v1 = VistaModelo $dm $refAsm @("*Isométrica", "*Isometric") 0.08 0.14
    if (-not $v1) { $refAsm = $caminho; $v1 = VistaModelo $dm $caminho @("*Isométrica", "*Isometric") 0.08 0.14 }
    # padrão ProEstamp (ex.: 13011773): uma isométrica grande, balões com o Nº DA PEÇA e a lista de materiais embaixo à direita
    $v2 = $null
    if (-not $v1) { throw "não consegui criar a vista isométrica" }
    Modo $v1 $DispShaded $true

    $nLinhas = 8; $tabW = 0.155; $tabH = 0.0
    try {
        $tpl = TemplateSolda $caminho
        AtivarDesenho $dm   # volta para o desenho novo (o de referência pode ter sido aberto)
        if ($tpl -eq "") { Log "   Aviso: sem template da lista de solda; usando a lista padrão do SolidWorks." "Yellow" } else { Log "   Lista de materiais pelo template: $tpl" "DarkGray" }
        $tab = X $v1 "InsertBomTable4" $false 0.2917 0.0345 $AnchorBR $BomParts (NomeConfig $asm) $tpl $false $NumNone $false
        if (-not $tab) { Log "   (InsertBomTable4 devolveu vazio)" "DarkYellow" }
        if ($tab) {
            try { $nLinhas = [int](XG $tab "RowCount") } catch { }
            # tamanho real da tabela (soma das larguras das colunas e alturas das linhas)
            try { $w = 0.0; $nc = [int](XG $tab "ColumnCount"); for ($c = 0; $c -lt $nc; $c++) { $w += [double](X $tab "GetColumnWidth" $c) }; if ($w -gt 0.02) { $tabW = $w } } catch { }
            try { $h = 0.0; for ($r = 0; $r -lt $nLinhas; $r++) { $h += [double](X $tab "GetRowHeight" $r) }; if ($h -gt 0.005) { $tabH = $h } } catch { }
            Log ("   Lista de materiais: {0} linha(s), {1:N0} x {2:N0} mm" -f $nLinhas, ($tabW * 1000), ($tabH * 1000))
        }
    } catch { Log "   Aviso: não inseri a lista de materiais ($($_.Exception.Message))" "Yellow" }
    if ($tabH -le 0) { $tabH = $nLinhas * 0.0051 }
    $baseMin = 0.0345 + $tabH + 0.008
    $tabX1 = 0.2917 - $tabW

    # ETAPA 1: lista no canto inferior direito (já inserida). ETAPA 2: a vista na maior escala possível,
    # testando a FORMA real da isométrica (contorno da caixa da montagem projetada), não o retângulo da vista:
    # numa peça comprida a diagonal passa por cima do canto da lista sem encostar nela. ETAPA 3: balões no espaço que sobrou.
    $script:xfCache = @{}; $script:xfModo = @{}
    $mesa = [pscustomobject]@{ x1 = $tabX1; y1 = 0.0345; x2 = 0.2917; y2 = 0.0345 + $tabH }
    $script:mesaSolda = $mesa
    $ok = $false
    $i0 = EscalaInicial ($diag * 1.2) ($diag * 0.8)
    $i0 = [math]::Max(0, $i0 - 4)
    for ($i = $i0; $i -lt $Escalas.Count -and -not $ok; $i++) {
        DefinirEscala $dm $Escalas[$i][0] $Escalas[$i][1]
        $pos = MelhorPosicaoVista $v1 $b $mesa 0.014
        if ($pos) {
            MoverPara $v1 ((Contorno $v1).x1 + $pos.dx) ((Contorno $v1).y2 + $pos.dy); Rebuild $dm
            $ok = $true
            Log ("   Escala {0}:{1} (folga mínima de {2:N0} mm até a lista e as bordas)" -f $Escalas[$i][0], $Escalas[$i][1], ($pos.folga * 1000))
        }
    }
    if (-not $ok) { Log "   Aviso: a vista não coube perfeitamente; confira a disposição." "Yellow" }
    $script:hullSolda = HullVista $v1 $b

    AtivarDesenho $dm
    foreach ($v in @($v1)) {
        if (-not $v) { continue }
        try {
            Selecionar $dm $v | Out-Null
            $op = X $dm "CreateAutoBalloonOptions"
            try { XS $op "IgnoreMultiple" $true } catch { }
            try { XS $op "Style" (K "swBalloonStyle_e" @("swBS_None") 0) } catch { }
            try { XS $op "UpperTextContent" (K "swBalloonTextContent_e" @("swBalloonTextCustomProperties") 3) } catch { }
            try { XS $op "UpperText" "SW-Nome de arquivo(File Name)" } catch { }
            $bl = X $dm "AutoBalloon5" $op
            $nb = 0; if ($bl) { $nb = @($bl).Count }
            if ($nb -eq 0) { Log "   Aviso: o SolidWorks não colocou nenhum balão (desenho não estava ativo?)" "Yellow" } else { Log "   Balões com o Nº DA PEÇA: $nb" }
            if ($nb -gt 0) { Rebuild $dm; try { SetasNoCentro $dm $v @($bl) } catch { Log "   (setas no centro: $($_.Exception.Message))" "DarkYellow" } }
            if ($nb -gt 0) { Rebuild $dm; try { OrganizarBaloes $dm $v @($bl) } catch { Log "   (organizar balões: $($_.Exception.Message))" "DarkYellow" } }
        } catch { Log "   Aviso: não coloquei balões ($($_.Exception.Message))" "Yellow" }
    }
    Rebuild $dm
    # balões já organizados em fileiras (OrganizarBaloes); não passam mais pelo "afastar" genérico
    TrocarDesenhista $dm
    Rebuild $dm
    AtivarDesenho $dm | Out-Null; try { X $dm "ViewZoomtofit2" | Out-Null } catch { }   # folha inteira na tela para conferir
    SalvarComo $dm $drwPath $SaveSilent
    Log "   Desenho: $drwPath" "Green"
    $pdf = Join-Path $destDir "$cod.PDF"
    $pdfMsg = ""
    if ($script:FazPdf) { if (PdfProtegido $destDir $cod) { $pdfMsg = " (PDF mantido: existe APR)" } else { SalvarComo $dm $pdf ($SaveSilent + $SaveCopy); Log "   PDF: $pdf" "Green"; $pdfMsg = " + PDF" } }
    if ($FecharDesenho) { Fechar $dm }
    Relatorio $caminho "montagem" "detalhar" "ok" ("desenho" + $pdfMsg)
}

# ---------------------------------------------------------------- seta do balão no CENTRO da peça (não na aresta)
# o balão automático prende numa aresta. Aqui: pega a maior face vizinha dessa aresta, acha um ponto no meio dela,
# converte para a folha (componente -> montagem -> vista) e move a ponta da seta para lá, presa na face.
# A conversão é conferida pela própria aresta: usa a fórmula que coloca a aresta onde a seta estava.
function PtComp([double[]]$t, [double[]]$p, [int]$conv) {
    if (-not $t -or $conv -eq 2) { return $p }
    $s = 1.0; if ($t.Count -gt 12 -and $t[12] -ne 0) { $s = $t[12] }
    if ($conv -eq 0) { return [double[]]@((($p[0] * $t[0] + $p[1] * $t[3] + $p[2] * $t[6]) * $s + $t[9]), (($p[0] * $t[1] + $p[1] * $t[4] + $p[2] * $t[7]) * $s + $t[10]), (($p[0] * $t[2] + $p[1] * $t[5] + $p[2] * $t[8]) * $s + $t[11])) }
    return [double[]]@((($p[0] * $t[0] + $p[1] * $t[1] + $p[2] * $t[2]) * $s + $t[9]), (($p[0] * $t[3] + $p[1] * $t[4] + $p[2] * $t[5]) * $s + $t[10]), (($p[0] * $t[6] + $p[1] * $t[7] + $p[2] * $t[8]) * $s + $t[11]))
}
function DistSegPt($p, $a, $b) {
    $dx = $b[0] - $a[0]; $dy = $b[1] - $a[1]; $l2 = $dx * $dx + $dy * $dy
    $u = 0.0; if ($l2 -gt 1e-12) { $u = [math]::Max(0, [math]::Min(1, (($p[0] - $a[0]) * $dx + ($p[1] - $a[1]) * $dy) / $l2)) }
    $qx = $a[0] + $u * $dx - $p[0]; $qy = $a[1] + $u * $dy - $p[1]
    return [math]::Sqrt($qx * $qx + $qy * $qy)
}
function SetasNoCentro($dm, $v, $notas) {
    $xa = DadosXf $v
    $seta = K "swArrowStyle_e" @("swFILLED_ARROWHEAD") -99
    $ok = 0; $nTot = 0
    foreach ($n in $notas) {
        if (-not $n) { continue }
        $nTot++
        try {
            $an = AnnOf $n
            $lp0 = XD (X $an "GetLeaderPointsAtIndex" 0); if (-not $lp0 -or $lp0.Count -lt 3) { continue }
            # pontos da linha de chamada: o 1º é o lado do balão, o ÚLTIMO é a ponta da seta (na peça)
            $k3 = $lp0.Count - 3; $lp = @($lp0[$k3], $lp0[$k3 + 1])
            $ents = @(X $an "GetAttachedEntities3"); $ed = $ents | Where-Object { $_ } | Select-Object -First 1
            if (-not $ed) { continue }
            $comp = $null; try { $comp = X $ed "GetComponent" } catch { }
            $t = $null; if ($comp) { try { $t = [double[]](XD (XG (XG $comp "Transform2") "ArrayData")) } catch { } }
            $gp = [double[]](XD (X $ed "GetCurveParams2"))
            $e1 = [double[]]@($gp[0], $gp[1], $gp[2]); $e2 = [double[]]@($gp[3], $gp[4], $gp[5])
            # calibra: conversão componente->montagem e fórmula da vista que põem a aresta onde a seta está
            $melhor = $null; $md = 1e9
            foreach ($conv in 0, 1, 2) { foreach ($m in 0, 1, 2, 3) {
                $a1 = AplicarXf $xa (PtComp $t $e1 $conv) $m; $a2 = AplicarXf $xa (PtComp $t $e2 $conv) $m
                $d = DistSegPt @($lp[0], $lp[1]) $a1 $a2
                if ($d -lt $md) { $md = $d; $melhor = @($conv, $m) }
            } }
            if ($md -gt 0.004) { Log ("   (balão {0}: não achei a posição da peça na folha, seta mantida na aresta)" -f $nTot) "DarkGray"; continue }
            # maior face vizinha da aresta e um ponto no meio dela
            $fs = @(X $ed "GetTwoAdjacentFaces2") | Where-Object { $_ }
            $face = $fs | Sort-Object { try { -[double](X $_ "GetArea") } catch { 0 } } | Select-Object -First 1
            if (-not $face) { continue }
            $bx = [double[]](XD (X $face "GetBox"))
            $cp = [double[]](XD (X $face "GetClosestPointOn" (($bx[0] + $bx[3]) / 2) (($bx[1] + $bx[4]) / 2) (($bx[2] + $bx[5]) / 2)))
            $alvo = AplicarXf $xa (PtComp $t ([double[]]@($cp[0], $cp[1], $cp[2])) $melhor[0]) $melhor[1]
            # prende na face e leva a ponta da seta para o meio dela
            try { X $an "SetAttachedEntities" ([object[]]@($face)) | Out-Null } catch { }
            $mv = $false
            try { $mv = [bool](X $an "SetLeaderAttachmentPointAtIndex" 0 ([double]$alvo[0]) ([double]$alvo[1]) 0.0) } catch { }
            if ($seta -ne -99) { try { X $an "SetArrowHeadStyleAtIndex" 0 $seta | Out-Null } catch { } }
            if ($mv) { $ok++ } else { Log ("   (balão {0}: o SolidWorks não aceitou mover a ponta da seta)" -f $nTot) "DarkYellow" }
        } catch { Log "   (seta do balão $nTot : $($_.Exception.Message))" "DarkYellow" }
    }
    Log "   Setas no centro da peça: $ok de $nTot balão(ões)" "DarkGray"
}
