# Utilidades.ps1 - caminhos, propriedades, abrir/fechar, vistas, escala, salvar
# Carregado pelo DetalharSW.ps1 (dot-source). Não rodar sozinho.

# ---------------------------------------------------------------- utilidades
function Codigo($caminho) { return [IO.Path]::GetFileNameWithoutExtension($caminho) }
function PastaDestino($caminho) {
    if ($PastaSaida -ne "") { if (-not (Test-Path $PastaSaida)) { New-Item -ItemType Directory -Path $PastaSaida | Out-Null }; return $PastaSaida }
    return (Split-Path -Parent $caminho)
}
function EhIgnorado($caminho) { foreach ($p in $PastasIgnorar) { if ($p -and $caminho -like "*\$p*") { return $true } }; return $false }
function EhPastaSolda($caminho) {
    foreach ($seg in $caminho.Split("\")) { foreach ($p in $PastasSolda) { if ($p -and $seg.Trim().StartsWith($p)) { return $true } } }
    return $false
}
function NomeConfig($model) {
    try { return [string](XG (XG (XG $model "ConfigurationManager") "ActiveConfiguration") "Name") } catch { return "" }
}
function Prop($model, $nome) {
    $v = ""
    try { $v = X $model "GetCustomInfoValue" (NomeConfig $model) $nome } catch { }
    if (-not $v) { try { $v = X $model "GetCustomInfoValue" "" $nome } catch { } }
    if ($v -match '^\$PRP') { $v = "" }
    return "$v"
}
function TemChapa($model) {
    try {
        $f = X $model "FirstFeature"
        while ($f) { if ((X $f "GetTypeName2") -eq "FlatPattern") { return $true }; $f = X $f "GetNextFeature" }
    } catch { Log "   (não consegui ler a árvore: $($_.Exception.Message))" "DarkYellow" }
    return $false
}
function Titulo($doc) { return [string](X $doc "GetTitle") }
function Fechar($doc) { try { X $sw "CloseDoc" (Titulo $doc) | Out-Null } catch { } }

$script:abertosPorMim = @()
function AbrirDoc($caminho, $tipo) {
    $doc = $null
    try { $doc = X $sw "GetOpenDocumentByName" $caminho } catch { }
    if ($doc) { return $doc }
    try { $doc = [SwCom]::OpenDoc6((Base $sw), [string]$caminho, [int]$tipo, [int]$OptSilent, "") } catch { Log "   (OpenDoc6 falhou: $($_.Exception.Message))" "DarkYellow"; $doc = $null }
    if (-not $doc) { try { $doc = X $sw "OpenDoc" $caminho $tipo } catch { } }
    if ($doc) { $script:abertosPorMim += (Titulo $doc) }
    return $doc
}
function FecharAbertos { foreach ($t in $script:abertosPorMim) { try { X $sw "CloseDoc" $t | Out-Null } catch { } }; $script:abertosPorMim = @() }

$script:novosDesenhos = @()
function NovoDesenho {
    $d = X $sw "NewDocument" $Template 6 0.297 0.21
    if (-not $d) { throw "Não consegui criar desenho com o template $Template" }
    $script:novosDesenhos += $d
    return $d
}
function Selecionar($dm, $vista) {
    X $dm "ClearSelection2" $true | Out-Null
    $nome = X $vista "GetName2"
    $ok = $false
    try { $ext = XG $dm "Extension"; $ok = [bool](X $ext "SelectByID2" $nome "DRAWINGVIEW" 0.0 0.0 0.0 $false 0 ([SwCom]::NullDisp()) 0) } catch { }
    # SelectByID2 pela ponte COM às vezes dá DISP_E_TYPEMISMATCH: usa o SelectByID antigo do ModelDoc
    if (-not $ok) { try { $ok = [bool](X $dm "SelectByID" $nome "DRAWINGVIEW" 0.0 0.0 0.0) } catch { } }
    return $ok
}
function VistaModelo($drw, $caminho, [string[]]$nomes, $x, $y) {
    $erros = @()
    foreach ($n in $nomes) {
        # o SolidWorks 2016 às vezes dá erro interno na primeira tentativa; a segunda funciona
        for ($t = 1; $t -le 2; $t++) {
            try { $v = X $drw "CreateDrawViewFromModelView3" $caminho $n ([double]$x) ([double]$y) 0.0; if ($v) { return $v } else { $erros += "$n=vazio"; break } } catch { $erros += "$n(tentativa $t)=$($_.Exception.Message)"; Start-Sleep -Milliseconds 500 }
        }
    }
    Log "   (vista não criada para $caminho : $($erros -join ' | '))" "DarkYellow"
    return $null
}
# deixa a vista "deitada" (comprimento na horizontal)
function Deitar($dm, $v, [double]$fator = 1.6) {
    if (-not $v) { return }
    try {
        $o = Contorno $v
        if ($o.h -gt $fator * $o.w) {
            XS $v "Angle" ([math]::PI / 2); Rebuild $dm
            Log "   Vista $(X $v 'GetName2') girada 90° (peça comprida)" "DarkGray"
        }
    } catch { Log "   (não consegui girar a vista: $($_.Exception.Message))" "DarkYellow" }
}
function Modo($v, $modo, $arestas) { try { X $v "SetDisplayMode3" $false $modo $false $arestas | Out-Null } catch { } }
function Contorno($v) { $o = XD (X $v "GetOutline"); return [pscustomobject]@{ x1 = $o[0]; y1 = $o[1]; x2 = $o[2]; y2 = $o[3]; w = $o[2] - $o[0]; h = $o[3] - $o[1] } }
$script:dbgMover = 0
function PosVista($v) {
    $raw = $null
    try { $raw = XG $v "Position" } catch { }
    $p = XD $raw
    if (-not $p -or $p.Count -lt 2) { try { $p = XD (X $v "Position") } catch { } }
    return $p
}
# O SolidWorks lê o array de posição de forma diferente conforme o tipo passado pela ponte COM;
# testa os formatos na primeira vez e guarda o que funcionou.
$script:formatoPos = -1
function ArrayPos($fmt, $x, $y) {
    switch ($fmt) {
        0 { return ,([double[]]@($x, $y)) }
        1 { $a = New-Object object[] 2; $a[0] = [double]$x; $a[1] = [double]$y; return ,$a }
        2 { return ,([double[]]@($x, $y, 0.0)) }
        3 { $a = New-Object object[] 3; $a[0] = [double]$x; $a[1] = [double]$y; $a[2] = 0.0; return ,$a }
        4 { return ,([double[]]@(0.0, $x, $y)) }
    }
}
function DefinirPosicao($v, $x, $y) {
    $fmts = if ($script:formatoPos -ge 0) { @($script:formatoPos) } else { @(0, 1, 2, 3, 4) }
    foreach ($f in $fmts) {
        try { [SwCom]::Set((Base $v), "Position", (ArrayPos $f $x $y)) } catch { continue }
        $p2 = PosVista $v
        if ($p2 -and [math]::Abs($p2[0] - $x) -lt 0.0005 -and [math]::Abs($p2[1] - $y) -lt 0.0005) {
            if ($script:formatoPos -lt 0) { $script:formatoPos = $f; Log "   (posição das vistas: formato $f funcionou)" "DarkGray" }
            return
        }
    }
    Log ("   Aviso: não consegui posicionar a vista em ({0:N3};{1:N3})" -f $x, $y) "Yellow"
}
function MoverPara($v, $esq, $topo) {
    $o = Contorno $v; $p = PosVista $v
    if (-not $p -or $p.Count -lt 2) { throw "não consegui ler a posição da vista $(X $v 'GetName2')" }
    $novo = [double[]]@(($p[0] + ($esq - $o.x1)), ($p[1] + ($topo - $o.y2)))
    DefinirPosicao $v $novo[0] $novo[1]
    if ($false) {
        $script:dbgMover++
        $o2 = Contorno $v; $p2 = PosVista $v
        Log ("   [dbg] {0}: contorno antes ({1:N3};{2:N3})-({3:N3};{4:N3}) pos antes ({5:N3};{6:N3}) -> pos pedida ({7:N3};{8:N3}) pos depois ({9:N3};{10:N3}) contorno depois ({11:N3};{12:N3})-({13:N3};{14:N3})" -f (X $v "GetName2"), $o.x1, $o.y1, $o.x2, $o.y2, $p[0], $p[1], $novo[0], $novo[1], $p2[0], $p2[1], $o2.x1, $o2.y1, $o2.x2, $o2.y2) "DarkGray"
    }
}
function Sobrepoe($a, $b) { return -not ($a.x2 + 0.004 -le $b.x1 -or $b.x2 + 0.004 -le $a.x1 -or $a.y2 + 0.004 -le $b.y1 -or $b.y2 + 0.004 -le $a.y1) }
$script:MargemCotas = 0.0
$script:chamadas = @()
function DentroDaArea($o, $baseMin) { $m = $script:MargemCotas; return ($o.x1 -ge $AreaL + $m - 0.001 -and $o.x2 -le $AreaR - $m + 0.001 -and $o.y2 -le $AreaT - $m + 0.001 -and $o.y1 -ge $baseMin + $m - 0.001) }
function Rebuild($dm) { try { X $dm "ForceRebuild3" $false | Out-Null } catch { }; try { X $dm "GraphicsRedraw2" | Out-Null } catch { } }
function DefinirEscala($dm, $num, $den) {
    $sh = X $dm "GetCurrentSheet"; $p = @(X $sh "GetProperties2")
    X $sh "SetProperties2" ([int]$p[0]) ([int]$p[1]) ([double]$num) ([double]$den) $true ([double]$p[5]) ([double]$p[6]) ([bool]$p[7]) | Out-Null
    Rebuild $dm
}
function EscalaInicial($larguraFator, $alturaFator) {
    $W = $AreaR - $AreaL - 3 * $Gap; $H = $AreaT - $AreaB - 2 * $Gap
    for ($i = 0; $i -lt $Escalas.Count; $i++) {
        $s = $Escalas[$i][0] / $Escalas[$i][1]
        if ($s * $larguraFator -le $W -and $s * $alturaFator -le $H) { return $i }
    }
    return $Escalas.Count - 1
}
function SalvarComo($dm, $destino, $opcoes) {
    # se o arquivo de destino estiver aberto no SolidWorks (rodada anterior), fecha antes
    try { $aberto = X $sw "GetOpenDocumentByName" $destino; if ($aberto -and (Titulo $aberto) -ne (Titulo $dm)) { X $sw "CloseDoc" (Titulo $aberto) | Out-Null } } catch { }
    if (Test-Path $destino) { Remove-Item $destino -Force }
    $r = X $dm "SaveAs3" $destino 0 $opcoes
    if (-not (Test-Path $destino)) { throw "SolidWorks não gravou $destino (código $r)" }
}

function AtivarDesenho($d) {
    $t = Titulo $d
    foreach ($nome in @(($t -replace '\s+-\s+[^-]+$', ''), $t)) {
        try { $e = 0; X $sw "ActivateDoc2" $nome $true ([ref]$e) | Out-Null } catch { }
        try { X $sw "ActivateDoc" $nome | Out-Null } catch { }
        try { $at = XG $sw "ActiveDoc"; if ($at -and (Titulo $at) -eq $t) { return $true } } catch { }
    }
    Log "   (não consegui deixar o desenho ativo: $t)" "DarkYellow"
    return $false
}

# ---------------------------------------------------------------- vistas conferidas pela orientação REAL
# (as vistas-padrão do modelo podem estar trocadas: na 02115197 "Esquerda" olhava em Y; na 02124120 "Posterior"
#  mostrava a face sem os escareados). Devolve @(eixo 0/1/2 ou -1, sinal +1 = mostra a face do lado + do eixo).
function DirecaoVista($v) {
    try {
        $script:xfCache = @{}; $script:xfModo = @{}
        $a = DadosXf $v
        for ($k = 0; $k -lt 3; $k++) {
            if ([math]::Abs([double]$a[3 * $k]) + [math]::Abs([double]$a[3 * $k + 1]) -lt 0.05) { return ,@($k, $(if ([double]$a[3 * $k + 2] -ge 0) { 1 } else { -1 })) }
        }
    } catch { }
    return ,@(-1, 0)
}
# cria a vista que olha de frente a face do lado $lado (+1/-1; 0 = tanto faz) do eixo $k; testa as vistas-padrão e
# fica com a que realmente olha para lá (as erradas são apagadas)
function VistaPorEixo($dm, $caminho, [int]$k, [int]$lado, $x, $y) {
    $nomes = @(@(@("*Direita", "*Right"), @("*Esquerda", "*Left")), @(@("*Superior", "*Top"), @("*Inferior", "*Bottom")), @(@("*Frontal", "*Front"), @("*Posterior", "*Back")))
    $ordem = @()
    if ($lado -lt 0) { $ordem += ,$nomes[$k][1]; $ordem += ,$nomes[$k][0] } else { $ordem += ,$nomes[$k][0]; $ordem += ,$nomes[$k][1] }
    for ($i = 0; $i -lt 3; $i++) { if ($i -ne $k) { $ordem += ,$nomes[$i][0]; $ordem += ,$nomes[$i][1] } }
    $reserva = $null
    foreach ($nm in $ordem) {
        $v = VistaModelo $dm $caminho $nm $x $y
        if (-not $v) { continue }
        Rebuild $dm
        $dv = DirecaoVista $v
        if ($dv[0] -eq $k -and ($lado -eq 0 -or $dv[1] -eq $lado)) {
            if ($reserva) { try { Selecionar $dm $reserva | Out-Null; X $dm "EditDelete" | Out-Null } catch { } }
            Log ("   Vista principal: {0} (olha a face {1}{2})" -f $nm[0], $(if ($dv[1] -gt 0) { "+" } else { "-" }), @("X", "Y", "Z")[$k]) "DarkGray"
            return $v
        }
        if (-not $reserva -and $dv[0] -eq $k) { $reserva = $v } else { try { Selecionar $dm $v | Out-Null; X $dm "EditDelete" | Out-Null } catch { } }
    }
    if ($reserva) { Log "   (vista principal: nenhuma vista olhou pelo lado pedido; usando a do mesmo eixo)" "DarkYellow" }
    return $reserva
}
# isométrica PROJETADA da principal (como arrastar a vista frontal na diagonal): fica coerente com a frente escolhida.
# Se o SolidWorks não fizer a projeção na diagonal, usa a isométrica nomeada do modelo.
function IsoDaFrontal($dm, $caminho, $front, $x, $y) {
    $iso = $null
    try {
        $p = Contorno $front
        if (Selecionar $dm $front) { $iso = X $dm "CreateUnfoldedViewAt3" ([double]$x) ([double]$y) 0.0 $false }
        if ($iso) {
            Rebuild $dm
            $dv = DirecaoVista $iso
            if ($dv[0] -ge 0) { Log "   (isométrica pela diagonal saiu ortogonal; usando a isométrica do modelo)" "DarkGray"; try { Selecionar $dm $iso | Out-Null; X $dm "EditDelete" | Out-Null } catch { }; $iso = $null }
            else { Log "   Isométrica projetada da vista principal" "DarkGray" }
        }
    } catch { $iso = $null }
    if (-not $iso) { $iso = VistaModelo $dm $caminho @("*Isométrica", "*Isometric") $x $y }
    return $iso
}
