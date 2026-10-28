# Fluxo.ps1 - exportar desenho existente e Gerar (botão do Monitor)
# Carregado pelo DetalharSW.ps1 (dot-source). Não rodar sozinho.

# ---------------------------------------------------------------- exportar de desenho existente
function Exportar($drwPath) {
    $cod = Codigo $drwPath
    $dir = Split-Path -Parent $drwPath
    $apr = @()   # APR-XXX são revisões antigas de registro: o PDF atual (<código>.PDF) pode ser regerado
    if ($apr.Count -gt 0 -and $PastaSaida -eq "") {
        Log "   Existe versão APR ($($apr[-1].Name)). Não vou sobrescrever o PDF vigente; gere a revisão manualmente." "Yellow"
        Relatorio $drwPath "desenho" "exportar" "pulado" "existe APR"
        return
    }
    $dm = AbrirDoc $drwPath $DocDRW
    if (-not $dm) { throw "não consegui abrir $drwPath" }
    Rebuild $dm
    $destDir = PastaDestino $drwPath
    $pdf = Join-Path $destDir "$cod.PDF"
    SalvarComo $dm $pdf ($SaveSilent + $SaveCopy); Log "   PDF: $pdf" "Green"
    $msg = "PDF"
    $prt = Join-Path $dir "$cod.SLDPRT"
    if (Test-Path $prt) {
        $peca = AbrirDoc $prt $DocPART
        if ($peca) {
            $desc = Prop $peca $PropDesc
            if (EhLaser $desc) { $dxf = Join-Path $destDir "$cod.DXF"; GerarDxf $prt $peca $dxf $desc; Log "   DXF: $dxf" "Green"; AbrirAutoCAD $dxf; $msg = "PDF + DXF" }
        }
    }
    Relatorio $drwPath "desenho" "exportar" "ok" $msg
}

# ---------------------------------------------------------------- gerar (botão do Monitor): escolhe desenho / PDF / DXF
# no servidor nunca sobrescreve o PDF vigente quando já existe revisão APR
function PdfProtegido($destDir, $cod) {
    # padrão ProEstamp: o PDF atual é sempre "<código>.PDF"; "<código> APR-XXX" são revisões antigas guardadas
    # como registro, então não impedem gerar o PDF atual
    return $false
    if ($PastaSaida -ne "") { return $false }
    $apr = @(Get-ChildItem -Path $destDir -Filter "$cod*APR*.PDF" -ErrorAction SilentlyContinue)
    if ($apr.Count -gt 0) { Log "   Existe versão APR ($($apr[-1].Name)). Não sobrescrevo o PDF vigente; gere a revisão manualmente." "Yellow"; return $true }
    return $false
}
function AcharDesenho($arq) {
    $cod = Codigo $arq
    foreach ($d in @((PastaDestino $arq), (Split-Path -Parent $arq))) { $p = Join-Path $d "$cod.SLDDRW"; if (Test-Path $p) { return $p } }
    return $null
}
function Gerar($arq) {
    $ext = [IO.Path]::GetExtension($arq).ToUpper()
    $cod = Codigo $arq
    $quer = @($Saidas.ToLower().Split(",") | ForEach-Object { $_.Trim() } | Where-Object { $_ })
    if ($quer.Count -eq 0) { $quer = @("drw", "pdf") }
    $qDrw = $quer -contains "drw"; $qPdf = $quer -contains "pdf"; $qDxf = ($quer -contains "dxf") -and $ext -eq ".SLDPRT"
    if (($quer -contains "dxf") -and $ext -ne ".SLDPRT") { Log "   DXF só para peças; ignorado." "Yellow" }
    Log ("   Gerar: " + ($quer -join ", ") + $(if ($Sobrescrever) { " (recriar desenho)" } else { "" }))
    $existe = AcharDesenho $arq
    if ($qDrw -and ((-not $existe) -or $Sobrescrever)) {
        $script:FazPdf = $qPdf; $script:FazDxf = $qDxf
        # opção escolhida na janela do Monitor (1 = padrão; 2 / 3 = outra disposição das vistas depois da principal)
        $script:variante = [math]::Max(0, [math]::Min(2, [int]$Opcao - 1))
        if ($script:variante -gt 0) { Log ("   Opção {0}: vistas giradas / em outra disposição (a vista principal continua a mesma)" -f ($script:variante + 1)) "Yellow" }
        if ($ext -eq ".SLDPRT") { $peca = AbrirDoc $arq $DocPART; if (-not $peca) { throw "não consegui abrir a peça" }; DetalharPeca $arq $peca }
        elseif ($ext -eq ".SLDASM") { $asm = AbrirDoc $arq $DocASM; if (-not $asm) { throw "não consegui abrir a montagem" }; DetalharMontagem $arq $asm }
        else { throw "tipo não suportado: $ext" }
        return
    }
    $feito = @()
    if ($qDrw) { Log "   Desenho já existe ($existe); mantido." "Yellow"; $feito += "desenho já existia" }
    $destDir = PastaDestino $arq
    if ($qPdf) {
        if (-not $existe) { throw "não existe desenho (.SLDDRW) para gerar o PDF" }
        if (PdfProtegido $destDir $cod) { $feito += "PDF mantido (existe APR)" }
        else {
            $dm = AbrirDoc $existe $DocDRW
            if (-not $dm) { throw "não consegui abrir $existe" }
            Rebuild $dm
            $pdf = Join-Path $destDir "$cod.PDF"
            SalvarComo $dm $pdf ($SaveSilent + $SaveCopy); Log "   PDF: $pdf" "Green"; $feito += "PDF"
        }
    }
    if ($qDxf) {
        $peca = AbrirDoc $arq $DocPART
        if (-not $peca) { throw "não consegui abrir a peça" }
        $desc = Prop $peca $PropDesc
        $script:sobremetal = $null; $script:semDxf = $false
        if (EhLaser $desc) { ConferirEspessuraLaser $peca $arq }   # só DXF: também confere a espessura
        if ($script:semDxf) { Log "   DXF não gerado: espessura da descrição diferente do 3D e não é sobremetal" "Yellow"; $feito += "sem DXF (espessura)" }
        else {
            $dxf = Join-Path $destDir "$cod.DXF"
            GerarDxf $arq $peca $dxf $desc; Log "   DXF: $dxf" "Green"; AbrirAutoCAD $dxf; $feito += "DXF"
        }
    }
    Relatorio $arq "" "gerar" "ok" ($feito -join " + ")
}

# contador de recriações por peça (tentativas.tsv na pasta do gerador): 1ª vez pelo gerador = 0; recriar = anterior + 1
function Tentativa([string]$cod, [bool]$recriando) {
    $arqT = Join-Path $Pasta "tentativas.tsv"
    $m = @{}
    try { if (Test-Path -LiteralPath $arqT) { foreach ($l in (Get-Content -LiteralPath $arqT -Encoding UTF8)) { $c = $l.Split("`t"); if ($c.Count -ge 2) { $m[$c[0]] = [int]$c[1] } } } } catch { }
    $n = 0
    # só conta como recriação se a vez anterior foi do gerador (desenho feito à mão existente = 1ª tentativa normal)
    if ($recriando -and $m.ContainsKey($cod)) { $n = $m[$cod] + 1 }
    $m[$cod] = $n
    try { $linhas = @($m.Keys | Sort-Object | ForEach-Object { "{0}`t{1}`t{2}" -f $_, $m[$_], (Get-Date -Format "yyyy-MM-dd HH:mm") }); Set-Content -LiteralPath $arqT -Value $linhas -Encoding UTF8 } catch { }
    return $n
}
