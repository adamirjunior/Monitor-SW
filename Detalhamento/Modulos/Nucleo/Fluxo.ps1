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
        if (EhLaser $desc) { ConferirEspessuraLaser $peca $arq }   # só DXF: também confere a espessura
        $dxf = Join-Path $destDir "$cod.DXF"
        GerarDxf $arq $peca $dxf $desc; Log "   DXF: $dxf" "Green"; AbrirAutoCAD $dxf; $feito += "DXF"
    }
    Relatorio $arq "" "gerar" "ok" ($feito -join " + ")
}
