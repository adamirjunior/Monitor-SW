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
$EspessuraLimiteCnc = [double](C "EspessuraLimiteFuracaoCnc" "4.76").Replace(",", ".") / 1000
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

# ---------------------------------------------------------------- validação (antes de gerar)
# só detalha se DESCRIÇÃO e ACABAMENTO estiverem preenchidos e pelo menos um processo tiver valor (ex.: 02)
function FaltaPropriedades($model) {
    $falta = @()
    if (([string](Prop $model $PropDesc)).Trim() -eq "") { $falta += $PropDesc }
    if (([string](Prop $model $PropAcabamento)).Trim() -eq "") { $falta += $PropAcabamento }
    $algum = $false
    foreach ($p in $PropsProcesso) { if ($p -and ([string](Prop $model $p)).Trim() -ne "") { $algum = $true; break } }
    if (-not $algum) { $falta += "um processo (SOLDA, TORNO CNC, FRESA CNC, ACAB. MANUAL...)" }
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
    $tCb = K "swWzdHoleTypes_e" @("swCounterBored") 0
    $tCs = K "swWzdHoleTypes_e" @("swCounterSunk") 1
    $tTap = K "swWzdHoleTypes_e" @("swTapped") 3
    $tPipe = K "swWzdHoleTypes_e" @("swPipeTapped") 4
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
# avisos do desenho (folha A4): empilhados no canto superior esquerdo da área útil
function AvisosDesenho($dm, [string[]]$textos) {
    $y = $AreaT - 0.002
    foreach ($t in $textos) { if ($t) { AvisoVermelho $dm $t ($AreaL + 0.002) $y 0.0025 | Out-Null; $y -= 0.007 } }
}
