# Dxf.ps1 - DXF de corte e abertura no AutoCAD
# Carregado pelo DetalharSW.ps1 (dot-source). Não rodar sozinho.

# ---------------------------------------------------------------- DXF (laser)
# o desenho novo herda do template a tabela de tolerâncias (Bruto/Desbastar/Alisar/Retificar) e os símbolos
# de acabamento; no DXF de corte só pode ir a peça, então apaga tudo que estiver solto na folha
function LimparFolhaDxf($d) {
    $n = 0
    try {
        $fv = X $d "GetFirstView"
        $anns = $null; try { $anns = X $fv "GetAnnotations" } catch { }
        foreach ($a in @($anns)) {
            if (-not $a) { continue }
            X $d "ClearSelection2" $true | Out-Null
            $ok = $false; try { $ok = X $a "Select2" $false 0 } catch { }
            if (-not $ok) { try { $ok = X $a "Select3" $false ([SwCom]::NullDisp()) } catch { } }
            if ($ok) { try { X $d "EditDelete" | Out-Null; $n++ } catch { } }
        }
        $tabs = $null; try { $tabs = X $fv "GetTableAnnotations" } catch { }
        foreach ($t in @($tabs)) {
            if (-not $t) { continue }
            X $d "ClearSelection2" $true | Out-Null
            try { $a = X $t "GetAnnotation"; if (X $a "Select2" $false 0) { X $d "EditDelete" | Out-Null; $n++ } } catch { }
        }
        X $d "ClearSelection2" $true | Out-Null
    } catch { Log "   (DXF: não consegui limpar a folha: $($_.Exception.Message))" "DarkYellow" }
    Log "   (DXF: $n item(ns) do template removido(s) da folha)" "DarkGray"
}
# DXF de corte: sem marcas de centro / linhas de centro (o laser cortaria), cotas totais com ±0,1
$AnnCenterMark = K "swAnnotationType_e" @("swCenterMarkSym") 13
$AnnCenterLine = K "swAnnotationType_e" @("swCenterLine") 15
$AnnDim = K "swAnnotationType_e" @("swDisplayDimension") 4
$TolSym = K "swTolType_e" @("swTolSYMMETRIC") 4
function SemMarcasAutomaticas($d) {
    $ext = $null; try { $ext = XG $d "Extension" } catch { }
    foreach ($nome in @("swDetailingAutoInsertCenterMarksForHoles", "swDetailingAutoInsertCenterMarksForSlots", "swDetailingAutoInsertCenterMarksForFillets", "swDetailingAutoInsertCenterLines", "swDetailingAutoInsertDowelSymbols")) {
        $p = K "swUserPreferenceToggle_e" @($nome) -1
        if ($p -lt 0) { continue }
        try { if ($ext) { X $ext "SetUserPreferenceToggle" $p 0 $false | Out-Null } else { X $d "SetUserPreferenceToggle" $p $false | Out-Null } } catch { }
    }
}
function TirarMarcasCentro($d, $vistas) {
    $n = 0
    foreach ($v in @($vistas)) {
        if (-not $v) { continue }
        $anns = $null; try { $anns = X $v "GetAnnotations" } catch { }
        foreach ($a in @($anns)) {
            if (-not $a) { continue }
            $t = -1; try { $t = [int](X $a "GetType") } catch { }
            if ($t -ne $AnnCenterMark -and $t -ne $AnnCenterLine) { continue }
            X $d "ClearSelection2" $true | Out-Null
            $ok = $false; try { $ok = X $a "Select2" $false 0 } catch { }
            if ($ok) { try { X $d "EditDelete" | Out-Null; $n++ } catch { } }
        }
    }
    X $d "ClearSelection2" $true | Out-Null
    if ($n -gt 0) { Log "   (DXF: $n marca(s)/linha(s) de centro removida(s))" "DarkGray" }
}
# depois de salvo: cotas e texto na mesma camada/cor das linhas do corte (camada 0, cor 7)
# o DXF do SolidWorks vem com a extensão/vista da folha inteira (0..1000): abre longe da peça.
# Calcula a extensão real das entidades e grava no cabeçalho ($EXTMIN/$EXTMAX) e na vista ativa (*Active),
# assim o arquivo já abre enquadrado em qualquer programa (como o duplo clique no scroll)
function VistaDxf($arq) {
    try {
        $enc = [Text.Encoding]::Default
        $L = [IO.File]::ReadAllLines($arq, $enc)
        $inv = [Globalization.CultureInfo]::InvariantCulture
        $x1 = 1e18; $y1 = 1e18; $x2 = -1e18; $y2 = -1e18
        $sec = ""; $tipo = ""; $cx = $null; $cy = $null
        for ($i = 0; $i -lt $L.Count - 1; $i += 2) {
            $c = $L[$i].Trim(); $v = $L[$i + 1].Trim()
            if ($c -eq "0" -and $v -eq "SECTION") { $sec = "?"; continue }
            if ($c -eq "2" -and $sec -eq "?") { $sec = $v; continue }
            if ($c -eq "0" -and $v -eq "ENDSEC") { $sec = ""; continue }
            if ($sec -ne "ENTITIES") { continue }
            if ($c -eq "0") { $tipo = $v; $cx = $null; $cy = $null; continue }
            $d = 0.0
            if (-not [double]::TryParse($v, [Globalization.NumberStyles]::Float, $inv, [ref]$d)) { continue }
            switch ($c) {
                { $_ -eq "10" -or $_ -eq "11" } { if ($d -lt $x1) { $x1 = $d }; if ($d -gt $x2) { $x2 = $d }; if ($c -eq "10") { $cx = $d } }
                { $_ -eq "20" -or $_ -eq "21" } { if ($d -lt $y1) { $y1 = $d }; if ($d -gt $y2) { $y2 = $d }; if ($c -eq "20") { $cy = $d } }
                "40" { if (($tipo -eq "CIRCLE" -or $tipo -eq "ARC") -and $cx -ne $null -and $cy -ne $null) { $x1 = [math]::Min($x1, $cx - $d); $x2 = [math]::Max($x2, $cx + $d); $y1 = [math]::Min($y1, $cy - $d); $y2 = [math]::Max($y2, $cy + $d) } }
            }
        }
        if ($x2 -le $x1 -or $y2 -le $y1) { return }
        $w = $x2 - $x1; $h = $y2 - $y1
        $mx = ($x1 + $x2) / 2; $my = ($y1 + $y2) / 2
        $alt = [math]::Max($h, $w / 1.8) * 1.15   # altura da vista com folga (tela mais larga que alta)
        $f = { param($n) ([double]$n).ToString("0.######", $inv) }
        $out = New-Object System.Collections.Generic.List[string]
        $sec = ""; $alvo = ""; $vp = $false
        for ($i = 0; $i -lt $L.Count - 1; $i += 2) {
            $c = $L[$i].Trim(); $v = $L[$i + 1]; $vt = $v.Trim()
            if ($c -eq "0" -and $vt -eq "SECTION") { $sec = "?" } elseif ($c -eq "2" -and $sec -eq "?") { $sec = $vt } elseif ($c -eq "0" -and $vt -eq "ENDSEC") { $sec = "" }
            if ($sec -eq "HEADER" -and $c -eq "9") { $alvo = $vt }
            elseif ($sec -eq "HEADER") {
                if ($alvo -eq '$EXTMIN') { if ($c -eq "10") { $v = & $f $x1 } elseif ($c -eq "20") { $v = & $f $y1 } }
                elseif ($alvo -eq '$EXTMAX') { if ($c -eq "10") { $v = & $f $x2 } elseif ($c -eq "20") { $v = & $f $y2 } }
            }
            if ($sec -eq "TABLES") {
                if ($c -eq "0") { $vp = $false }
                if ($c -eq "2" -and $vt -ieq "*Active") { $vp = $true }
                elseif ($vp) { if ($c -eq "12") { $v = & $f $mx } elseif ($c -eq "22") { $v = & $f $my } elseif ($c -eq "40") { $v = & $f $alt } }
            }
            $out.Add($L[$i]); $out.Add($v)
        }
        if ($L.Count % 2 -eq 1) { $out.Add($L[$L.Count - 1]) }
        [IO.File]::WriteAllLines($arq, $out, $enc)
        Log ("   (DXF: abre enquadrado na peça - {0:N0} x {1:N0} mm)" -f $w, $h) "DarkGray"
    } catch { Log "   (DXF: não consegui ajustar a vista inicial: $($_.Exception.Message))" "DarkYellow" }
}
function CorDxf($arq) {
    try {
        $enc = [Text.Encoding]::Default
        $L = [IO.File]::ReadAllLines($arq, $enc)
        $out = New-Object System.Collections.Generic.List[string]
        $sec = ""; $n = 0; $lfac = $false; $aviso = $false; $ent = ""; $zin = $false
        for ($i = 0; $i -lt $L.Count - 1; $i += 2) {
            $c = $L[$i].Trim(); $v = $L[$i + 1]
            if ($c -eq "0" -and $v.Trim() -eq "SECTION") { $sec = "?" }
            elseif ($c -eq "2" -and $sec -eq "?") { $sec = $v.Trim() }
            elseif ($c -eq "0" -and $v.Trim() -eq "ENDSEC") { $sec = "" }
            # fator de medição das cotas sempre 1 (senão o AutoCAD mede a peça multiplicada)
            if ($c -eq "9" -and $v.Trim() -eq "`$DIMLFAC") { $out.Add($L[$i]); $out.Add($v); $out.Add($L[$i + 2]); $out.Add("1.0"); $i += 2; continue }
            if ($sec -eq "TABLES" -and $c -eq "144") { $v = "1.0" }
            if ($c -eq "1040" -and $lfac) { $v = "1.0" }
            $lfac = ($c -eq "1070" -and $v.Trim() -eq "144")
            # cotas com as casas decimais sempre visíveis (12,70 e não 12; 390,00 e não 390): o SolidWorks grava
            # DIMZIN = 12 (tira zeros à direita). Zera no cabeçalho, nos estilos de cota e nas sobreposições das cotas.
            if ($c -eq "0") { $ent = $v.Trim() }
            if ($c -eq "9" -and $v.Trim() -eq "`$DIMZIN") { $out.Add($L[$i]); $out.Add($v); $out.Add($L[$i + 2]); $out.Add("     0"); $i += 2; continue }
            if ($sec -eq "TABLES" -and $ent -eq "DIMSTYLE" -and $c -eq "78") { $v = "     0" }
            if ($c -eq "1070" -and $zin) { $v = "     0" }
            $zin = ($c -eq "1070" -and $v.Trim() -eq "78")
            if ($sec -eq "ENTITIES" -or $sec -eq "BLOCKS") {
                # camada AVISOS (balões vermelhos do setor): mantém a camada e força vermelho (cor 1)
                if ($c -eq "0") { $aviso = $false }
                if ($c -eq "8" -and $v.Trim() -eq "AVISOS") { $aviso = $true }
                elseif ($aviso -and $c -eq "62") { $v = "     1" }
                elseif ($aviso -and $c -eq "420") { continue }
                elseif ($c -eq "8" -and $v.Trim() -ne "0" -and $v.Trim() -notmatch "DEFPOINTS") { $v = "0"; $n++ }
                elseif ($c -eq "62" -and $v.Trim() -ne "0") { $v = "     7" }
                elseif ($c -eq "420") { continue }
            }
            $out.Add($L[$i]); $out.Add($v)
        }
        if ($L.Count % 2 -eq 1) { $out.Add($L[$L.Count - 1]) }
        [IO.File]::WriteAllLines($arq, $out, $enc)
        Log "   (DXF: cotas e texto na mesma cor das linhas - $n item(ns) ajustado(s))" "DarkGray"
    } catch { Log "   (DXF: não consegui ajustar as cores: $($_.Exception.Message))" "DarkYellow" }
}
# tamanho das setas das cotas no desenho do DXF (em metros)
function SetasDxf($d, $alt) {
    $ext = $null; try { $ext = XG $d "Extension" } catch { }
    foreach ($par in @(@("swDetailingArrowHeight", $alt * 0.35), @("swDetailingArrowWidth", $alt * 1.0), @("swDetailingArrowLength", $alt * 2.0))) {
        $p = K "swUserPreferenceDoubleValue_e" @($par[0]) -1
        if ($p -lt 0) { continue }
        try { if ($ext) { X $ext "SetUserPreferenceDouble" $p 0 ([double]$par[1]) | Out-Null } else { X $d "SetUserPreferenceDoubleValue" $p ([double]$par[1]) | Out-Null } } catch { }
    }
}
function ToleranciaDxf($d, $vistas, $altCota) {
    $n = 0
    foreach ($v in @($vistas)) {
        if (-not $v) { continue }
        $anns = $null; try { $anns = X $v "GetAnnotations" } catch { }
        foreach ($a in @($anns)) {
            if (-not $a) { continue }
            $t = -1; try { $t = [int](X $a "GetType") } catch { }
            if ($t -ne $AnnDim) { continue }
            try {
                $dd = X $a "GetSpecificAnnotation"
                $dim = X $dd "GetDimension2" 0
                $mm = [math]::Round([math]::Abs([double](XG $dim "SystemValue")) * 1000, 3)
                # sempre 2 casas (pedido do usuário em 27/10: 12,70 ±0,1 e não 12 ±0,1; inteiro sai 390,00)
                $casas = 2
                try { X $dd "SetPrecision3" $casas -1 1 -1 | Out-Null } catch { try { X $dd "SetPrecision2" $casas -1 1 -1 | Out-Null } catch { } }
                if ($altCota -gt 0) { try { $tf = X $a "GetTextFormat" 0; XS $tf "CharHeight" $altCota; X $a "SetTextFormat" 0 $false $tf | Out-Null } catch { } }
                $tol = XG $dim "Tolerance"
                XS $tol "Type" $TolSym
                $okv = $false
                try { $okv = X $tol "SetValues2" (-0.0001) 0.0001 1 "" } catch { }
                if (-not $okv) { try { X $tol "SetValues" (-0.0001) 0.0001 | Out-Null } catch { } }
                $n++
            } catch { Log "   (tolerância da cota não aplicada: $($_.Exception.Message))" "DarkYellow" }
        }
    }
    if ($n -gt 0) { Log "   (DXF: ±0,1 em $n cota(s))" "DarkGray" }
}
# abre o DXF gerado no AutoCAD (só quando gerado pelo Monitor). Se o AutoCAD já estiver aberto, abre o arquivo NELE
# (não inicia outro AutoCAD) e enquadra o desenho (zoom extensão, como o duplo clique no scroll)
function AcadAberto {
    foreach ($pid0 in @("AutoCAD.Application", "AutoCAD.Application.25", "AutoCAD.Application.24", "AutoCAD.Application.23", "AutoCAD.Application.22", "AutoCAD.Application.21", "AutoCAD.Application.20")) {
        try { $a = [Runtime.InteropServices.Marshal]::GetActiveObject($pid0); if ($a) { return $a } } catch { }
    }
    return $null
}
function AcadAbrirArquivo($acad, $arq) {
    $docs = [SwCom]::Get($acad, "Documents")
    $doc = $null
    # já aberto (gerou de novo a mesma peça): fecha sem salvar e abre a versão nova
    try {
        $n = [int][SwCom]::Get($docs, "Count")
        for ($i = 0; $i -lt $n; $i++) {
            $d = [SwCom]::Call($docs, "Item", [object[]]@($i))
            if ([string]([SwCom]::Get($d, "FullName")) -ieq $arq) { [SwCom]::Call($d, "Close", [object[]]@($false)) | Out-Null; break }
        }
    } catch { }
    $doc = [SwCom]::Call($docs, "Open", [object[]]@($arq, $false))
    try { [SwCom]::Call($doc, "Activate", [object[]]@()) | Out-Null } catch { }
    try { [SwCom]::Set($acad, "Visible", $true) } catch { }
    AcadEnquadrar $acad $doc
    # o AutoCAD executa o comando quando termina de carregar: repete o enquadramento para garantir
    Start-Sleep -Milliseconds 1500
    AcadEnquadrar $acad $doc
}
# documento do AutoCAD com este arquivo (ou $null)
function AcadDocDoArquivo($acad, $arq) {
    try {
        $docs = [SwCom]::Get($acad, "Documents"); $n = [int][SwCom]::Get($docs, "Count")
        for ($i = 0; $i -lt $n; $i++) { $d = [SwCom]::Call($docs, "Item", [object[]]@($i)); if ([string]([SwCom]::Get($d, "FullName")) -ieq $arq) { return $d } }
    } catch { }
    return $null
}
# enquadra pelo desenho de verdade: recalcula a extensão (o cabeçalho do DXF pode trazer a extensão da folha inteira)
# e dá zoom de extensão como o duplo clique no scroll
function AcadEnquadrar($acad, $doc) {
    if (-not $doc) { try { $doc = [SwCom]::Get($acad, "ActiveDocument") } catch { } }
    $ok = $false
    if ($doc) { try { [SwCom]::Call($doc, "SendCommand", [object[]]@("_.REGEN _.ZOOM _E ")) | Out-Null; $ok = $true } catch { } }
    if (-not $ok) { try { [SwCom]::Call($acad, "ZoomExtents", [object[]]@()) | Out-Null } catch { } }
}
function AbrirAutoCAD($arq) {
    if ($Modo -ne "gerar" -or -not (Test-Path $arq)) { return }
    $arq = (Resolve-Path $arq).Path
    $acad = AcadAberto
    if ($acad) {
        try { AcadAbrirArquivo $acad $arq; Log "   DXF aberto no AutoCAD que já estava aberto (enquadrado)" "DarkGray"; return }
        catch { Log "   (AutoCAD aberto, mas não consegui abrir o DXF nele: $($_.Exception.Message))" "DarkYellow" }
    } else { Log "   (nenhum AutoCAD aberto encontrado: vou abrir um)" "DarkGray" }
    $exe = $null
    try {
        foreach ($k in Get-ChildItem "HKLM:\SOFTWARE\Autodesk\AutoCAD" -ErrorAction Stop) {
            foreach ($r in Get-ChildItem $k.PSPath -ErrorAction SilentlyContinue) {
                $loc = (Get-ItemProperty $r.PSPath -ErrorAction SilentlyContinue).AcadLocation
                if ($loc -and (Test-Path (Join-Path $loc "acad.exe"))) { $exe = Join-Path $loc "acad.exe" }
            }
        }
    } catch { }
    try {
        if ($exe) { Start-Process -FilePath $exe -ArgumentList ('"' + $arq + '"') } else { Start-Process -FilePath $arq }
        Log "   DXF aberto no $(if ($exe) { 'AutoCAD' } else { 'programa padrão do Windows' })" "DarkGray"
    } catch { Log "   (não consegui abrir o DXF: $($_.Exception.Message))" "DarkYellow"; return }
    # espera o AutoCAD subir E abrir este DXF (até ~2 min) para enquadrar, como o duplo clique no scroll
    $feito = $false
    for ($t = 0; $t -lt 60 -and -not $feito; $t++) {
        Start-Sleep -Seconds 2
        $acad = AcadAberto
        if (-not $acad) { continue }
        $doc = AcadDocDoArquivo $acad $arq
        if (-not $doc) { continue }
        try {
            Start-Sleep -Seconds 2
            try { [SwCom]::Call($doc, "Activate", [object[]]@()) | Out-Null } catch { }
            AcadEnquadrar $acad $doc; Start-Sleep -Seconds 2; AcadEnquadrar $acad $doc
            $feito = $true; Log "   (DXF enquadrado)" "DarkGray"
        } catch { }
    }
    if (-not $feito) { Log "   (não consegui enquadrar o DXF no AutoCAD: o arquivo já abre enquadrado pelo cabeçalho)" "DarkYellow" }
}
function GerarDxf($caminhoPeca, $peca, $destinoDxf, $desc) {
    $d = NovoDesenho
    $script:dxfDesenhos += $d
    try {
        $sh = X $d "GetCurrentSheet"
        $semFormato = $false
        try { $r = X $d "SetupSheet5" (X $sh "GetName") $PaperUser $TplNone 1.0 1.0 $true "" 1.0 1.0 "" $true; Log "   (DXF: SetupSheet5 sem formato = $r)" "DarkGray"; $semFormato = [bool]$r } catch { Log "   (DXF: SetupSheet5 falhou: $($_.Exception.Message))" "DarkYellow" }
        if (-not $semFormato) { try { X $sh "SetProperties2" $PaperUser $TplNone 1.0 1.0 $true 1.0 1.0 $true | Out-Null } catch { } }
        try { XS $sh "SheetFormatVisible" $false; Log "   (DXF: formato oculto)" "DarkGray" } catch { Log "   (DXF: SheetFormatVisible falhou: $($_.Exception.Message))" "DarkYellow" }
        Rebuild $d
        LimparFolhaDxf $d
        SemMarcasAutomaticas $d
        $v = $null
        if (TemChapa $peca) {
            try { $v = X $d "CreateFlatPatternViewFromModelView3" $caminhoPeca (NomeConfig $peca) 0.3 0.3 0.0 $false $false } catch { Log "   (planificada no DXF falhou: $($_.Exception.Message))" "DarkYellow" }
        }
        if (-not $v) {
            # chapa sem recurso de chapa metálica: vista na direção da menor medida (espessura)
            $b = XD (X $peca "GetPartBox" $true)
            $dx = [math]::Abs($b[3] - $b[0]); $dy = [math]::Abs($b[4] - $b[1]); $dz = [math]::Abs($b[5] - $b[2])
            $nomes = @("*Frontal", "*Front")
            if ($dy -le $dx -and $dy -le $dz) { $nomes = @("*Superior", "*Top") } elseif ($dx -le $dy -and $dx -le $dz) { $nomes = @("*Esquerda", "*Left") }
            $v = VistaModelo $d $caminhoPeca $nomes 0.3 0.3
        }
        if (-not $v) { throw "não consegui criar a vista planificada" }
        # DXF de corte TEM que sair em 1:1 (vista criada pelo SolidWorks pode vir com escala automática)
        try { XS $v "UseSheetScale" $false } catch { try { XS $v "UseSheetScale" 0 } catch { } }
        try { XS $v "ScaleDecimal" 1.0 } catch { try { XS $v "ScaleRatio" ([double[]]@(1.0, 1.0)) } catch { } }
        Modo $v $DispHidden $true
        Rebuild $d
        $esc = 0.0; try { $esc = [double](XG $v "ScaleDecimal") } catch { }
        if ([math]::Abs($esc - 1.0) -gt 0.0001) { throw "a vista do DXF ficou em escala $esc (precisa ser 1:1); DXF não gerado" }
        Log "   (DXF em escala 1:1 conferida)" "DarkGray"
        # comprimento sempre na horizontal (como nos DXFs da ProEstamp)
        $o = Contorno $v
        if ($o.h -gt 1.05 * $o.w) {
            try { XS $v "Angle" ([math]::PI / 2); Rebuild $d; Log "   (DXF: vista girada 90° - comprimento na horizontal)" "DarkGray" } catch { }
            $esc = 0.0; try { $esc = [double](XG $v "ScaleDecimal") } catch { }
            if ([math]::Abs($esc - 1.0) -gt 0.0001) { throw "a vista do DXF ficou em escala $esc depois de girar; DXF não gerado" }
        }
        # o SolidWorks muda a escala da FOLHA sozinho ao inserir a vista (ex.: 1:5); no DXF isso vira fator de
        # medição 5 (DIMLFAC) e a peça mede 5x maior no AutoCAD. Folha volta para 1:1 e a vista continua 1:1.
        DefinirEscala $d 1 1
        $pf = @(X (X $d "GetCurrentSheet") "GetProperties2")
        try { XS $v "UseSheetScale" $false } catch { }
        try { XS $v "ScaleDecimal" 1.0 } catch { }
        Rebuild $d
        $esc = 0.0; try { $esc = [double](XG $v "ScaleDecimal") } catch { }
        Log ("   (DXF: folha {0}:{1}, vista {2})" -f $pf[2], $pf[3], $esc) "DarkGray"
        if ([math]::Abs($esc - 1.0) -gt 0.0001 -or [math]::Abs([double]$pf[2] / [double]$pf[3] - 1.0) -gt 0.0001) { throw "folha/vista do DXF não ficou 1:1; DXF não gerado" }
        $o = Contorno $v
        # tamanhos proporcionais à peça (DXF em tamanho real): texto da descrição ~5% e cotas ~2,5% do comprimento
        $maior = [math]::Max($o.w, $o.h)
        $altDesc = [math]::Min(0.025, [math]::Max(0.005, $maior * 0.05))
        $altCota = [math]::Min(0.015, [math]::Max(0.0035, $maior * 0.025))
        $DistCota = [math]::Max(0.010, 2.5 * $altCota)
        SetasDxf $d $altCota
        Log ("   (DXF: cotas com {0:N1} mm, descrição com {1:N0} mm)" -f ($altCota * 1000), ($altDesc * 1000)) "DarkGray"
        $lat = $null
        if ($VistaLateralDxf) {
            try {
                if (Selecionar $d $v) { $lat = X $d "CreateUnfoldedViewAt3" ($o.x2 + 0.05) (($o.y1 + $o.y2) / 2) 0.0 $false }
            } catch { Log "   (vista projetada de espessura falhou: $($_.Exception.Message))" "DarkGray" }
            if (-not $lat) {
                # plano B (ex.: chapa plana 1.1): vista de modelo de lado, mostrando a espessura, à direita da peça em 1:1
                try {
                    $b = XD (X $peca "GetPartBox" $true)
                    $dx = [math]::Abs($b[3] - $b[0]); $dy = [math]::Abs($b[4] - $b[1]); $dz = [math]::Abs($b[5] - $b[2])
                    $lado = @("*Superior", "*Top")
                    if ($dy -le $dx -and $dy -le $dz) { $lado = @("*Frontal", "*Front") } elseif ($dx -le $dy -and $dx -le $dz) { $lado = @("*Frontal", "*Front") }
                    $lat = VistaModelo $d $caminhoPeca $lado ($o.x2 + 0.05) (($o.y1 + $o.y2) / 2)
                    if ($lat) {
                        try { XS $lat "UseSheetScale" $false } catch { }
                        try { XS $lat "ScaleDecimal" 1.0 } catch { }
                        Rebuild $d
                        $ol = Contorno $lat
                        # espessura na horizontal (vista em pé, ao lado da peça)
                        if ($ol.w -gt $ol.h) { try { XS $lat "Angle" ([math]::PI / 2); Rebuild $d } catch { } }
                        # encosta à direita da peça, centralizada na altura
                        $ol = Contorno $lat
                        try { MoverPara $lat ($o.x2 + 0.05) ((($o.y1 + $o.y2) / 2) + $ol.h / 2); Rebuild $d } catch { }
                        Log "   (DXF: vista de espessura criada pela vista de modelo)" "DarkGray"
                    }
                } catch { Log "   (sem vista de espessura no DXF: $($_.Exception.Message))" "DarkYellow"; $lat = $null }
            }
            if ($lat) { Modo $lat $DispHidden $true } else { Log "   (DXF sem vista de espessura)" "DarkYellow" }
        }
        # cotas totais como nos DXFs de referência (comprimento x largura na planificada + medidas da vista lateral)
        $script:xfCache = @{}; $script:xfModo = @{}
        $tgl = K "swUserPreferenceToggle_e" @("swInputDimValOnCreate") 10
        $antes = $null
        try { $antes = X $sw "GetUserPreferenceToggle" $tgl; X $sw "SetUserPreferenceToggle" $tgl $false | Out-Null } catch { }
        try {
            Rebuild $d
            $nc = CotaTotal $d $v $true $true
            if ($lat) {
                $ol = Contorno $lat
                $mesmaAltura = ([math]::Abs(($ol.y2 - $ol.y1) - ($o.y2 - $o.y1)) -lt 0.0008)
                # espessura: cota entre as duas linhas paralelas da vista de lado (mesma função do desenho)
                $espL = 0.0
                try { $ft = X $peca "FirstFeature"; while ($ft) { if ([string](X $ft "GetTypeName2") -eq "SheetMetal") { $espL = [double](XG (X $ft "GetDefinition") "Thickness"); break }; $ft = X $ft "GetNextFeature" } } catch { }
                if ($espL -le 0) { $bb = XD (X $peca "GetPartBox" $true); $espL = [math]::Min([math]::Abs($bb[3] - $bb[0]), [math]::Min([math]::Abs($bb[4] - $bb[1]), [math]::Abs($bb[5] - $bb[2]))) }
                $espAntes = $script:espessura; $script:espessura = $espL
                $yH = $null; try { $yH = [double](CaixaReal $v).y2 + $DistCota } catch { }
                $ne = 0; try { $ne = CotaEspessura $d @($lat) $null $yH } catch { }
                $script:espessura = $espAntes
                if ($ne -gt 0) { $nc += $ne; if (-not $mesmaAltura) { $nc += CotaTotal $d $lat $false $true } }
                else { $nc += CotaTotal $d $lat $true (-not $mesmaAltura) }
            }
            Log "   (DXF: $nc cota(s) total(is))" "DarkGray"
            Rebuild $d
            ToleranciaDxf $d @($v, $lat) $altCota
        } catch { Log "   (DXF sem cotas: $($_.Exception.Message))" "DarkYellow" }
        finally { if ($null -ne $antes) { try { X $sw "SetUserPreferenceToggle" $tgl ([bool]$antes) | Out-Null } catch { } } }
        TirarMarcasCentro $d @($v, $lat)
        $o = Contorno $v
        if ($NotaDxf -and $desc) {
            try {
                # texto da descrição bem visível para quem vai cortar: ~5% do comprimento (entre 5 e 25 mm), acima das cotas
                $alt = $altDesc
                X $d "ClearSelection2" $true | Out-Null
                $n = X $d "InsertNote" $desc
                if ($n) {
                    $an = X $n "GetAnnotation"
                    try { $tf = X $an "GetTextFormat" 0; XS $tf "CharHeight" $alt; X $an "SetTextFormat" 0 $false $tf | Out-Null } catch { Log "   (altura do texto não alterada: $($_.Exception.Message))" "DarkYellow" }
                    # centralizado em relação ao conjunto das vistas (peça + vista da espessura)
                    $x1 = $o.x1; $x2 = $o.x2
                    if ($lat) { try { $ol = Contorno $lat; $x1 = [math]::Min($x1, $ol.x1); $x2 = [math]::Max($x2, $ol.x2) } catch { } }
                    $yTxt = $o.y2 + $DistCota + 0.012 + 2 * $alt
                    $larg = $desc.Length * $alt * 0.8
                    X $an "SetPosition" (($x1 + $x2) / 2 - $larg / 2) $yTxt 0.0 | Out-Null
                    Rebuild $d
                    try {
                        $ext = XD (X $n "GetExtent")
                        $lr = [math]::Abs($ext[3] - $ext[0])
                        if ($lr -gt 0.001 -and $lr -lt 2) { X $an "SetPosition" (($x1 + $x2) / 2 - $lr / 2) $yTxt 0.0 | Out-Null }
                    } catch { }
                    Log ("   (DXF: texto '{0}' com {1:N0} mm)" -f $desc, ($alt * 1000)) "DarkGray"
                }
            } catch { Log "   (sem nota no DXF: $($_.Exception.Message))" "DarkYellow" }
        }
        # avisos do setor em VERMELHO (camada AVISOS, preservada pelo CorDxf)
        $fuD = InfoFuros $peca
        try {
            $espD = 0.0
            try { $ft = X $peca "FirstFeature"; while ($ft) { if ([string](X $ft "GetTypeName2") -eq "SheetMetal") { $espD = [double](XG (X $ft "GetDefinition") "Thickness"); break }; $ft = X $ft "GetNextFeature" } } catch { }
            if ($espD -le 0) { $bb = XD (X $peca "GetPartBox" $true); $espD = [math]::Min([math]::Abs($bb[3] - $bb[0]), [math]::Min([math]::Abs($bb[4] - $bb[1]), [math]::Abs($bb[5] - $bb[2]))) }
            $avD = @()
            if (TemUsinagemCnc $peca) { $avD += "Avaliar sobremetal - Recurso Offset" }
            $limTxt = ("{0:0.##}" -f ($EspessuraLimiteCnc * 1000)).Replace(".", ",")
            $grossa = $espD -gt $EspessuraLimiteCnc + 0.000001
            if (($fuD.Roscados + $fuD.Rebaixos) -gt 0 -and $grossa) { $avD += "Avaliar furação no CNC - Espessura > ${limTxt}mm" }
            # chapa acima do limite (5 mm) com qualquer furo: 2º aviso - furos pequenos do laser precisam de CNC
            $nCirc = 0; try { foreach ($ed in (Entidades $v "swViewEntityType_Edge" 1)) { try { $cc = X $ed "GetCurve"; if ((X $cc "IsCircle") -and -not (X $ed "GetStartVertex")) { $nCirc++ } } catch { } } } catch { }
            if ($grossa -and ($nCirc + $fuD.Roscados + $fuD.Rebaixos + $fuD.Simples) -gt 0) { $avD += "Avaliar furações pequenas em relação a espessura - Requer CNC" }
            if (@($fuD.DiamRoscas | Where-Object { $_ -lt $FatorDiametroRosca * $espD }).Count -gt 0) { $avD += "Avaliar furação no CNC - Diâmetro pequeno" }
            if ($fuD.Roscados -gt 0 -and @($fuD.DiamRoscas).Count -eq 0) { Log "   (DXF: rosca sem diâmetro legível - regra do diâmetro pequeno não conferida)" "DarkYellow" }
            $o = Contorno $v
            $altAv = [math]::Max(0.0035, $altCota * 1.2)
            $yAv = $o.y2 + $DistCota + 0.012 + 2 * $altDesc + 2.5 * $altDesc
            foreach ($t in $avD) { AvisoVermelho $d $t $o.x1 $yAv $altAv | Out-Null; $yAv += 3 * $altAv }
        } catch { Log "   (DXF: avisos não inseridos: $($_.Exception.Message))" "DarkYellow" }
        Rebuild $d
        # DXF anterior aberto no AutoCAD trava o arquivo: fecha (sem salvar) antes de gravar o novo
        if (Test-Path $destinoDxf) {
            try {
                $acad0 = AcadAberto
                if ($acad0) { $doc0 = AcadDocDoArquivo $acad0 $destinoDxf; if ($doc0) { [SwCom]::Call($doc0, "Close", [object[]]@($false)) | Out-Null; Start-Sleep -Milliseconds 800; Log "   (DXF anterior fechado no AutoCAD para gravar o novo)" "DarkGray" } }
            } catch { }
        }
        SalvarComo $d $destinoDxf ($SaveSilent + $SaveCopy)
        CorDxf $destinoDxf
        if (($fuD.Roscados + $fuD.Rebaixos) -gt 0) { PreFuroDxf $destinoDxf }
        VistaDxf $destinoDxf
    } finally {
        Fechar $d
    }
}

# furo roscado / rebaixo no DXF: fica só a circunferência do PRÉ-FURO (diâmetro menor).
# Círculos/arcos concêntricos com um círculo menor (até 2,2x o raio dele) são removidos; o contorno externo
# de uma peça redonda (bem maior que o furo) não é tocado.
function PreFuroDxf($arq) {
    try {
        $enc = [Text.Encoding]::Default
        $L = [IO.File]::ReadAllLines($arq, $enc)
        # localiza a seção ENTITIES e quebra em entidades (cada uma começa no código 0)
        $ini = -1; $fim = -1
        for ($i = 0; $i -lt $L.Count - 3; $i += 2) {
            if ($L[$i].Trim() -eq "0" -and $L[$i + 1].Trim() -eq "SECTION" -and $L[$i + 2].Trim() -eq "2" -and $L[$i + 3].Trim() -eq "ENTITIES") { $ini = $i + 4 }
            elseif ($ini -ge 0 -and $L[$i].Trim() -eq "0" -and $L[$i + 1].Trim() -eq "ENDSEC" -and $i -ge $ini) { $fim = $i; break }
        }
        if ($ini -lt 0 -or $fim -lt 0) { return }
        $ents = New-Object System.Collections.Generic.List[object]
        $cur = $null
        for ($i = $ini; $i -lt $fim; $i += 2) {
            if ($L[$i].Trim() -eq "0") { $cur = [pscustomobject]@{ tipo = $L[$i + 1].Trim(); de = $i; ate = $i + 1; x = $null; y = $null; r = $null }; $ents.Add($cur) }
            elseif ($cur) {
                $cur.ate = $i + 1
                $c = $L[$i].Trim(); $val = $L[$i + 1].Trim()
                if ($c -eq "10") { $cur.x = [double]::Parse($val, [Globalization.CultureInfo]::InvariantCulture) }
                elseif ($c -eq "20") { $cur.y = [double]::Parse($val, [Globalization.CultureInfo]::InvariantCulture) }
                elseif ($c -eq "40") { $cur.r = [double]::Parse($val, [Globalization.CultureInfo]::InvariantCulture) }
            }
        }
        $circ = @($ents | Where-Object { ($_.tipo -eq "CIRCLE" -or $_.tipo -eq "ARC") -and $null -ne $_.r })
        $tirar = @{}
        foreach ($e in $circ) {
            if ($e.tipo -ne "CIRCLE") { continue }
            foreach ($o in $circ) {
                if ($o -eq $e -or $tirar.ContainsKey($o.de)) { continue }
                $mesmoCentro = ([math]::Abs($o.x - $e.x) -lt 0.01 -and [math]::Abs($o.y - $e.y) -lt 0.01)
                if ($mesmoCentro -and $o.r -gt $e.r + 0.001 -and $o.r -le 2.2 * $e.r) { $tirar[$o.de] = $true }
            }
        }
        if ($tirar.Count -eq 0) { Log "   (DXF: nenhuma circunferência dupla de rosca/rebaixo para remover)" "DarkGray"; return }
        $out = New-Object System.Collections.Generic.List[string]
        $pular = @{}; foreach ($e in $ents) { if ($tirar.ContainsKey($e.de)) { for ($j = $e.de; $j -le $e.ate; $j++) { $pular[$j] = $true } } }
        for ($i = 0; $i -lt $L.Count; $i++) { if (-not $pular.ContainsKey($i)) { $out.Add($L[$i]) } }
        [IO.File]::WriteAllLines($arq, $out, $enc)
        Log "   DXF: $($tirar.Count) circunferência(s) de rosca/rebaixo removida(s) - ficou só o pré-furo" "DarkGray"
    } catch { Log "   (DXF: não consegui deixar só o pré-furo: $($_.Exception.Message))" "DarkYellow" }
}
