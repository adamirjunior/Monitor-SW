# Regras.ps1 - regras do setor (Detalhamento\REGRAS_DETALHAMENTO.txt): palavras-chave, validação das propriedades,
# leitura dos furos (rosca / rebaixo) e avisos em VERMELHO (desenho e DXF).
# Carregado pelo DetalharSW.ps1 (dot-source). Não rodar sozinho.

# ---------------------------------------------------------------- palavras-chave (editáveis no detalhamento.ini)
function Lista($nome, $padrao) { return @((C $nome $padrao).Split("|") | ForEach-Object { $_.Trim() } | Where-Object { $_ }) }
$PalavrasLaser      = Lista "PalavrasLaser" "LASER|OXICORTE|CHAPA"
$PalavrasPerfil     = Lista "PalavrasPerfil" "METALON|METALOM|CANTONEIRA|BARRA"
$PalavrasBarraUsin  = Lista "PalavrasBarraUsinagem" "BARRA CHATA"
$PalavrasUsinagem   = Lista "PalavrasMaterialUsinagem" "BARRA CHATA|TRIF|TRIFILADO|LAMINADO|SEXTAVADO|TARUGO|POLIACETAL|TECNNYL|TECNYL|BRONZE|ALUMÍNIO|ALUMINIO"
$PalavrasSolda      = Lista "PalavrasSolda" "SOLDA|MONTAGEM DE SOLDA"
$PrefixosSolda      = Lista "PrefixosSolda" "1301"
$PropsUsinagemCnc   = Lista "PropriedadesUsinagemCnc" "TORNO CNC|FRESA CNC|ELETRO|TORNO|FRESA"
$PropsProcesso      = Lista "PropriedadesProcesso" "SOLDA|TORNO|TORNO CNC|FRESA|FRESA CNC|ELETRO|FURADEIRA|ACAB.MANUAL|ACAB. MANUAL|LASER|OXICORTE|DOBRA|DOBRADEIRA|SERRA|PINTURA|CALANDRA"
$PropAcabamento     = C "PropriedadeAcabamento" "ACABAMENTO"
$ExigirPropriedades = Sim (C "ExigirPropriedades" "sim")
$EspessuraLimiteCnc = [double](C "EspessuraLimiteFuracaoCnc" "5").Replace(",", ".") / 1000
$FatorDiametroRosca = [double](C "FatorDiametroRoscaEspessura" "0.7").Replace(",", ".")
$CorAviso           = 255   # vermelho (COLORREF: R + G*256 + B*65536)

function TemPalavra($texto, $lista) {
    $t = ([string]$texto).ToUpper()
    foreach ($p in $lista) { if ($p -and $t.Contains($p.ToUpper())) { return $p } }
    return $null
}
function EhLaser($desc) { return [bool](TemPalavra $desc $PalavrasLaser) }
# processo de usinagem CNC preenchido (TORNO CNC, FRESA CNC, ELETRO...)
function TemUsinagemCnc($model) {
    foreach ($p in $PropsUsinagemCnc) { if ($p -and ([string](Prop $model $p)).Trim() -ne "") { return $true } }
    return $false
}

# nome da propriedade sem espaço/ponto/acento: "ACAB. MANUAL", "ACAB.MANUAL" e "ACABAMENTO MANUAL" ficam iguais
function NomeProcNorm([string]$n) {
    $t = $n.ToUpperInvariant().Normalize([Text.NormalizationForm]::FormD)
    return ($t -replace '[^A-Z0-9]', '') -replace '^ACABAMENTO', 'ACAB'
}
# algum processo com valor? confere os nomes REAIS das propriedades da peça (config + geral) contra a lista,
# sem depender da grafia (ex. 02124107: "ACABAMENTO MANUAL" = 02 e "ACABAMENTO FINAL" = 03, a lista só tinha ACAB.MANUAL)
function TemAlgumProcesso($model) {
    foreach ($p in $PropsProcesso) { if ($p -and ([string](Prop $model $p)).Trim() -ne "") { return $true } }
    $aceitos = @{}
    foreach ($p in $PropsProcesso) { if ($p) { $aceitos[(NomeProcNorm $p)] = 1 } }
    $aceitos["ACABMANUAL"] = 1; $aceitos["ACABFINAL"] = 1
    foreach ($cfg in @((NomeConfig $model), "")) {
        $nomes = @(); try { $nomes = @(X $model "GetCustomInfoNames2" $cfg) } catch { }
        foreach ($n in $nomes) {
            if (-not $n -or -not $aceitos.ContainsKey((NomeProcNorm ([string]$n)))) { continue }
            $v = ""; try { $v = [string](X $model "GetCustomInfoValue" $cfg ([string]$n)) } catch { }
            if ($v.Trim() -ne "" -and $v -notmatch '^\$PRP') { return $true }
        }
    }
    return $false
}

# ---------------------------------------------------------------- validação (antes de gerar)
# só detalha se DESCRIÇÃO e ACABAMENTO estiverem preenchidos e pelo menos um processo tiver valor (ex.: 02)
function FaltaPropriedades($model) {
    $falta = @()
    if (([string](Prop $model $PropDesc)).Trim() -eq "") { $falta += $PropDesc }
    if (([string](Prop $model $PropAcabamento)).Trim() -eq "") { $falta += $PropAcabamento }
    $algum = TemAlgumProcesso $model
    if (-not $algum) { $falta += "um processo (SOLDA, TORNO CNC, FRESA CNC, ACABAMENTO MANUAL/FINAL...)" }
    return ,$falta
}
function ValidarPropriedades($model, $caminho) {
    if (-not $ExigirPropriedades) { return }
    $falta = FaltaPropriedades $model
    if ($falta.Count -eq 0) { return }
    $msg = "Preencha a tabela de propriedades da peça antes de detalhar. Falta: " + ($falta -join ", ")
    Log "   $msg" "Red"
    try {
        Add-Type -AssemblyName System.Windows.Forms
        $f = New-Object System.Windows.Forms.Form; $f.TopMost = $true
        [void][System.Windows.Forms.MessageBox]::Show($f, ((Codigo $caminho) + "`n`n" + $msg), "Detalhamento - propriedades incompletas", "OK", "Warning")
        $f.Dispose()
    } catch { }
    throw $msg
}

# ---------------------------------------------------------------- furos da peça (pelos recursos do modelo)
# Assistente de furação: roscado / rebaixo (escareado conta como rebaixo) / simples; rosca cosmética conta como roscado
function InfoFuros($peca) {
    $r = [pscustomobject]@{ Roscados = 0; Rebaixos = 0; Simples = 0; DiamRoscas = @() }
    # Type do assistente de furação = swWzdGeneralHoleTypes_e (o enum swWzdHoleTypes_e é outro: lá rebaixo = 2)
    $tCb = K "swWzdGeneralHoleTypes_e" @("swWzdCounterBore") 0
    $tCs = K "swWzdGeneralHoleTypes_e" @("swWzdCounterSink") 1
    $tTap = K "swWzdGeneralHoleTypes_e" @("swWzdTap") 4
    $tPipe = K "swWzdGeneralHoleTypes_e" @("swWzdPipeTap") 3
    try {
        $ft = X $peca "FirstFeature"
        while ($ft) {
            $t = [string](X $ft "GetTypeName2")
            if ($t -match '(?i)^(HoleWzd|AdvHole)') {
                $tipo = -1; $d = $null
                try { $d = X $ft "GetDefinition"; $tipo = [int](XG $d "Type") } catch { }
                $qtd = 1; try { $sk = X $ft "GetFirstSubFeature"; $n = 0; while ($sk) { $n++; $sk = X $sk "GetNextSubFeature" }; if ($n -gt 1) { $qtd = $n - 1 } } catch { }
                if ($tipo -eq $tTap -or $tipo -eq $tPipe -or $t -match '(?i)AdvHole') {
                    $r.Roscados += $qtd
                    $dia = 0.0
                    foreach ($p in @("ThreadDiameter", "Diameter")) { try { $v = [double](XG $d $p); if ($v -gt 0) { $dia = $v; break } } catch { } }
                    if ($dia -gt 0) { $r.DiamRoscas += $dia }
                } elseif ($tipo -eq $tCb -or $tipo -eq $tCs) { $r.Rebaixos += $qtd }
                else { $r.Simples += $qtd }
            } elseif ($t -match '(?i)CosmeticThread') { $r.Roscados++ }
            $ft = X $ft "GetNextFeature"
        }
    } catch { Log "   (não consegui ler os furos: $($_.Exception.Message))" "DarkYellow" }
    return $r
}

# ---------------------------------------------------------------- avisos em vermelho
# camada AVISOS em vermelho: no PDF sai vermelho e no DXF o CorDxf mantém a cor (as outras entidades vão para cor 7)
function CamadaAvisos($dm) {
    try {
        $lm = X $dm "GetLayerManager"
        if ($lm) {
            $existe = $null; try { $existe = X $lm "GetLayer" "AVISOS" } catch { }
            if (-not $existe) { X $lm "AddLayer" "AVISOS" "Avisos do detalhamento automático" $CorAviso 0 0 | Out-Null }
            return $true
        }
    } catch { }
    return $false
}
# nota em "balão" retangular, vermelha, com a esquina superior esquerda em (x, y) da folha
function AvisoVermelho($dm, [string]$texto, [double]$x, [double]$y, [double]$alt = 0.0025) {
    try {
        $temCamada = CamadaAvisos $dm
        X $dm "ClearSelection2" $true | Out-Null
        $n = X $dm "InsertNote" $texto
        if (-not $n) { Log "   (aviso não inserido: $texto)" "DarkYellow"; return $null }
        $an = X $n "GetAnnotation"
        try { $tf = X $an "GetTextFormat" 0; XS $tf "CharHeight" $alt; X $an "SetTextFormat" 0 $false $tf | Out-Null } catch { }
        if ($temCamada) { try { XS $an "Layer" "AVISOS" } catch { } }
        try { XS $an "Color" $CorAviso } catch { }
        $box = K "swBalloonStyle_e" @("swBS_Box") 4
        $fit = K "swBalloonFit_e" @("swBF_Tightest") 0
        try { X $n "SetBalloon" $box $fit | Out-Null } catch { }
        X $an "SetPosition" $x $y 0.0 | Out-Null
        Log "   Aviso em vermelho: $texto" "DarkGray"
        return $n
    } catch { Log "   (aviso não inserido: $($_.Exception.Message))" "DarkYellow"; return $null }
}
# avisos do desenho (folha A4): no cantinho superior esquerdo da FOLHA, acima da área das vistas
# (faixa entre o topo da área útil e a margem). Vários avisos: uma COLUNA, todos com a mesma borda esquerda,
# um embaixo do outro, sem encostar
$AvisoX = [double](C "AvisoPosicaoX" "0.012").Replace(",", ".")
$AvisoY = [double](C "AvisoPosicaoY" "0.197").Replace(",", ".")
function AvisosDesenho($dm, [string[]]$textos) {
    $y = $AvisoY
    foreach ($t in $textos) {
        if (-not $t) { continue }
        $n = AvisoVermelho $dm $t $AvisoX $y 0.0022
        $prox = $y - 0.005
        # o próximo começa logo abaixo do anterior (pela altura real do balão), mesma borda esquerda
        if ($n) { try { Rebuild $dm; $ext = XD (X $n "GetExtent"); $baixo = [math]::Min($ext[1], $ext[4]); if ($baixo -gt 0.05 -and $baixo -lt $y) { $prox = $baixo - 0.0012 } } catch { } }
        $y = $prox
    }
}

# ---------------------------------------------------------------- conferência da ESPESSURA (laser)
$ToleranciaEspessura = [double](C "ToleranciaEspessuraMm" "0.05").Replace(",", ".") / 1000
$ConferirEspessura   = Sim (C "ConferirEspessuraLaser" "sim")
$ToleranciaEspessuraPol = [double](C "ToleranciaEspessuraPolegadaMm" "0.1").Replace(",", ".") / 1000
# espessura escrita na descrição, em mm ou em POLEGADA (pedido do usuário em 27/10: 3D 12,7 e descrição 1/2"):
#   1º depois de "ESP." / "ESPESSURA" / "E=": 3/16"  1/2'  1.1/4"  1 1/4"  1-1/4"  0,5"  1/2 POL  1/2 (fração = polegada)  2MM  2
#   2º senão a MENOR medida do texto com unidade (mm, " , ', '', POL) ou fração com marca de polegada
# Devolve { m = metros; pol = $true se veio em polegada; texto = como estava escrito } ou $null.
$script:rxPol = '(?:(?<int>\d{1,2})\s*(?:[\.\-]|\s)\s*)?(?<num>\d+)\s*/\s*(?<den>\d+)|(?<dec>\d+(?:[\.,]\d+)?)'
$script:rxMarcaPol = '\s*(?:"|\u201D|\u2033|\u2019\u2019|\u0027\u0027|\u0027|\u2019|\u2032|POLEGADAS?\b|POL\b\.?)'
function ValorPolegada($m) {
    if ($m.Groups["den"].Success -and $m.Groups["den"].Value -ne "") {
        $den = [double]$m.Groups["den"].Value; if ($den -le 0) { return $null }
        $v = [double]$m.Groups["num"].Value / $den
        if ($m.Groups["int"].Success -and $m.Groups["int"].Value -ne "") { $v += [double]$m.Groups["int"].Value }
        return $v * 0.0254
    }
    return [double]($m.Groups["dec"].Value.Replace(",", ".")) * 0.0254
}
function LerEspessuraDescricao([string]$desc) {
    if (-not $desc) { return $null }
    $num = '([0-9]+(?:[\.,][0-9]+)?)'
    # 1) depois da palavra-chave
    foreach ($chave in @("(?i)ESPESSURA\s*[:=]?\s*", "(?i)\bESP(?![A-Z])\.?\s*[:=]?\s*", "(?i)\bE\s*=\s*")) {
        $k = [regex]::Match($desc, $chave)
        if (-not $k.Success) { continue }
        $resto = $desc.Substring($k.Index + $k.Length)
        # polegada: fração (com ou sem marca) ou número com marca de polegada
        $mp = [regex]::Match($resto, "(?i)^(?:$($script:rxPol))(?<marca>$($script:rxMarcaPol))?")
        if ($mp.Success -and (($mp.Groups["den"].Success -and $mp.Groups["den"].Value -ne "") -or $mp.Groups["marca"].Value -ne "")) {
            $mm = [regex]::Match($resto, "(?i)^$num\s*MM(?![A-Z])")
            if (-not $mm.Success) { return [pscustomobject]@{ m = (ValorPolegada $mp); pol = $true; texto = $mp.Value.Trim() } }
        }
        $mn = [regex]::Match($resto, "^$num")
        if ($mn.Success) { return [pscustomobject]@{ m = [double]($mn.Groups[1].Value.Replace(",", ".")) / 1000; pol = $false; texto = $mn.Value } }
    }
    # 2) menor medida do texto com unidade
    $cands = @()
    foreach ($m in [regex]::Matches($desc, "(?i)$num\s*MM(?![A-Z])")) { $cands += [pscustomobject]@{ m = [double]($m.Groups[1].Value.Replace(",", ".")) / 1000; pol = $false; texto = $m.Value.Trim() } }
    foreach ($m in [regex]::Matches($desc, "(?i)(?<![\d\.,/])(?:$($script:rxPol))(?<marca>$($script:rxMarcaPol))")) {
        $v = ValorPolegada $m; if ($v -and $v -gt 0) { $cands += [pscustomobject]@{ m = $v; pol = $true; texto = $m.Value.Trim() } }
    }
    if ($cands.Count -gt 0) { return ($cands | Sort-Object m | Select-Object -First 1) }
    return $null
}
function EspessuraDaDescricao([string]$desc) { $r = LerEspessuraDescricao $desc; if ($r) { return $r.m }; return $null }
# espessura do 3D (m): recurso de chapa metálica; senão a menor medida da caixa (chapa plana). $null se não der para saber
function EspessuraDo3D($peca) {
    try {
        $ft = X $peca "FirstFeature"
        while ($ft) { if ([string](X $ft "GetTypeName2") -eq "SheetMetal") { return [double](XG (X $ft "GetDefinition") "Thickness") }; $ft = X $ft "GetNextFeature" }
    } catch { }
    try {
        $b = XD (X $peca "GetPartBox" $true)
        $d = @([math]::Abs($b[3] - $b[0]), [math]::Abs($b[4] - $b[1]), [math]::Abs($b[5] - $b[2])) | Sort-Object
        if ($d[0] -lt 0.1 * $d[2]) { return $d[0] }   # chapa plana sem recurso de chapa metálica
    } catch { }
    return $null
}
# laser: a espessura da descrição tem que ser a do 3D. Diferente (ou faltando) -> aviso e NÃO detalha
function ConferirEspessuraLaser($peca, $caminho) {
    $script:sobremetal = $null; $script:semDxf = $false
    if (-not $ConferirEspessura) { return }
    $desc = [string](Prop $peca $PropDesc)
    $e3d = EspessuraDo3D $peca
    $ld = LerEspessuraDescricao $desc
    $eDesc = if ($ld) { $ld.m } else { $null }
    if ($null -eq $e3d) { Log "   (espessura do 3D não identificada: conferência da descrição pulada)" "DarkYellow"; return }
    $f = { param($x) ("{0:0.###} mm" -f ($x * 1000)) }
    # em polegada a chapa comercial é arredondada (3/16" = 4,7625 -> 4,75 ou 4,76; 1/4" = 6,35 -> 6,3): tolerância maior
    $tol = $ToleranciaEspessura; $comoDesc = ""
    if ($ld -and $ld.pol) { $tol = [math]::Max($ToleranciaEspessura, $ToleranciaEspessuraPol); $comoDesc = " ($($ld.texto) = $(& $f $eDesc))" }
    if ($null -eq $eDesc) {
        $msg = "A descrição não informa a espessura da chapa. Espessura do 3D: $(& $f $e3d). Escreva na descrição, por exemplo: ESP. $(& $f $e3d)"
    } elseif ($eDesc -gt $e3d + $tol + 1e-9) {
        # descrição MAIOR que o 3D: pode ser SOBREMETAL (chapa cortada mais grossa para usinar depois) - pergunta
        $txtD = if ($ld.pol) { $ld.texto + " = " + (& $f $eDesc) } else { & $f $eDesc }
        $perg = "Espessura diferente: descrição $txtD, 3D $(& $f $e3d).`n`nÉ SOBREMETAL (sobra de material para usinar)?`n`nSim: detalha pelo 3D e o DXF sai com a espessura da descrição ($(& $f $eDesc)) e o aviso de sobremetal.`nNão: detalha sem gerar o DXF."
        $resp = "No"
        if ($env:DETALHAR_SOBREMETAL -eq "sim") { $resp = "Yes" } elseif ($env:DETALHAR_SOBREMETAL -eq "nao") { $resp = "No" }   # testes sem janela
        else { try {
            Add-Type -AssemblyName System.Windows.Forms
            $fm = New-Object System.Windows.Forms.Form; $fm.TopMost = $true
            $resp = [string][System.Windows.Forms.MessageBox]::Show($fm, ((Codigo $caminho) + "`n`n" + $desc + "`n`n" + $perg), "Detalhamento - sobremetal?", "YesNo", "Question")
            $fm.Dispose()
        } catch { } }
        if ($resp -eq "Yes") {
            $script:sobremetal = [pscustomobject]@{ de = $e3d; para = $eDesc }
            Log ("   SOBREMETAL confirmado: 3D {0} -> chapa {1} (DXF com a espessura da descrição)" -f (& $f $e3d), (& $f $eDesc)) "Yellow"
        } else {
            $script:semDxf = $true
            Log ("   Espessura diferente (descrição {0}, 3D {1}) e NÃO é sobremetal: DXF não será gerado" -f $txtD, (& $f $e3d)) "Yellow"
        }
        return
    } elseif ([math]::Abs($eDesc - $e3d) -gt $tol + 1e-9) {
        $msg = "Espessura diferente: descrição $(if ($ld.pol) { $ld.texto + ' = ' + (& $f $eDesc) } else { & $f $eDesc }), 3D $(& $f $e3d). Corrija a descrição (ou o modelo) para a espessura do 3D antes de detalhar."
    } else { Log ("   Espessura conferida: descrição{0} = 3D = {1}" -f $comoDesc, (& $f $e3d)) "DarkGray"; return }
    Log "   $msg" "Red"
    try {
        Add-Type -AssemblyName System.Windows.Forms
        $fm = New-Object System.Windows.Forms.Form; $fm.TopMost = $true
        [void][System.Windows.Forms.MessageBox]::Show($fm, ((Codigo $caminho) + "`n`n" + $desc + "`n`n" + $msg), "Detalhamento - espessura da chapa", "OK", "Warning")
        $fm.Dispose()
    } catch { }
    throw $msg
}
