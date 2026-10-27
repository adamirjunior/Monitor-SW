# DetalharSW.ps1 - Detalhamento automatico no SolidWorks 2016 (padrao ProEstamp / gabarito CUP-400)
# Uso: arraste pecas/montagens/desenhos sobre DETALHAR.bat ou EXPORTAR_PDF_DXF.bat
#   -Modo detalhar : cria o .SLDDRW no padrao + PDF (+ DXF se for laser)
#   -Modo exportar : abre o .SLDDRW existente e gera PDF (+ DXF se for laser)
[CmdletBinding(PositionalBinding = $false)]
param(
    [string]$Modo = "detalhar",          # detalhar | exportar | gerar (gerar = chamado pelo botão do Monitor)
    [string]$Saidas = "",                # gerar: drw,pdf,dxf (o que o usuário marcou)
    [string]$Destino = "",               # servidor = ignora PastaSaida e grava na pasta da peça
    [switch]$Recriar,                    # recria o .SLDDRW mesmo se existir
    [string]$Desenhista = "",            # nome no carimbo (vem do login do Monitor)
    [Parameter(ValueFromRemainingArguments = $true)][string[]]$Arquivos
)

$ErrorActionPreference = "Stop"
$Pasta = Split-Path -Parent $MyInvocation.MyCommand.Path
$LogFile = Join-Path $Pasta "log.txt"
$RelFile = Join-Path $Pasta ("relatorio_" + (Get-Date -Format "yyyy-MM-dd") + ".csv")

# ---------------------------------------------------------------- um detalhamento por vez
# gerando.lock na pasta do gerador (servidor): enquanto alguém gera, ninguém mais gera (em nenhum PC).
# O arquivo fica ABERTO durante a geração; se o processo cair, o Windows solta o arquivo e o próximo apaga e segue.
$script:trava = $null
function SoltarTrava {
    if ($script:trava) { try { $script:trava.Dispose() } catch { }; $script:trava = $null; try { Remove-Item -LiteralPath (Join-Path $Pasta "gerando.lock") -Force -ErrorAction Stop } catch { } }
}
if ($Modo -ne "diag") {
    $arqTrava = Join-Path $Pasta "gerando.lock"
    $quem = if ($Desenhista) { $Desenhista } else { $env:USERNAME }
    for ($tent = 0; $tent -lt 2 -and -not $script:trava; $tent++) {
        if (Test-Path -LiteralPath $arqTrava) { try { Remove-Item -LiteralPath $arqTrava -Force -ErrorAction Stop } catch { } }   # sobra de geração que caiu: apaga
        try {
            $fs = New-Object IO.FileStream($arqTrava, [IO.FileMode]::CreateNew, [IO.FileAccess]::Write, [IO.FileShare]::Read)
            $txt = [Text.Encoding]::UTF8.GetBytes(("{0}|{1}|{2}|{3}" -f $quem, $env:COMPUTERNAME, (Get-Date -Format "HH:mm"), (($Arquivos | ForEach-Object { [IO.Path]::GetFileNameWithoutExtension($_) }) -join ", ")))
            $fs.Write($txt, 0, $txt.Length); $fs.Flush()
            $script:trava = $fs
        } catch { Start-Sleep -Milliseconds 300 }
    }
    if (-not $script:trava) {
        $info = @("outra pessoa", "", "", "")
        try { $r = New-Object IO.FileStream($arqTrava, [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::ReadWrite); $sr = New-Object IO.StreamReader($r, [Text.Encoding]::UTF8); $info = $sr.ReadToEnd().Split('|'); $sr.Dispose() } catch { }
        $msg = "Já tem um detalhamento sendo gerado por {0}{1}{2}{3}.`n`nAguarde terminar e gere de novo." -f $info[0], $(if ($info.Count -gt 1 -and $info[1]) { " (PC " + $info[1] + ")" } else { "" }), $(if ($info.Count -gt 2 -and $info[2]) { " desde " + $info[2] } else { "" }), $(if ($info.Count -gt 3 -and $info[3]) { ": " + $info[3] } else { "" })
        try { Add-Content -Path $LogFile -Value ((Get-Date -Format "HH:mm:ss") + "  Bloqueado: " + $msg.Replace("`n", " ")) -Encoding UTF8 } catch { }
        try { Add-Type -AssemblyName System.Windows.Forms; $own = New-Object System.Windows.Forms.Form; $own.TopMost = $true; [void][System.Windows.Forms.MessageBox]::Show($own, $msg, "Detalhamento em andamento", "OK", "Information"); $own.Dispose() } catch { }
        exit 3
    }
}

# ---------------------------------------------------------------- módulos
# Nucleo\ = funções comuns; Tipos\ = um arquivo por tipo de peça. A ordem importa (configuração e COM primeiro).
foreach ($mod in @('Nucleo\Config', 'Nucleo\Janela', 'Nucleo\SwCom', 'Nucleo\Utilidades', 'Nucleo\Dxf', 'Nucleo\Carimbo', 'Nucleo\Cotas', 'Nucleo\Layout', 'Nucleo\Regras', 'Nucleo\Classificar', 'Tipos\Chapa', 'Tipos\Metalon', 'Tipos\UsinadaTabelaFuros', 'Tipos\Solda', 'Tipos\Peca', 'Nucleo\Fluxo')) {
    $arqMod = Join-Path $Pasta ("Modulos\" + $mod + ".ps1")
    if (-not (Test-Path $arqMod)) { throw "Módulo não encontrado: $arqMod" }
    . $arqMod
}

# ---------------------------------------------------------------- lista de arquivos
if (-not $Arquivos -or $Arquivos.Count -eq 0) {
    Add-Type -AssemblyName System.Windows.Forms
    $dlg = New-Object System.Windows.Forms.OpenFileDialog
    $dlg.Multiselect = $true
    $dlg.Title = if ($Modo -eq "exportar") { "Escolha os desenhos (.SLDDRW) para gerar PDF/DXF" } else { "Escolha peças/montagens para detalhar" }
    $dlg.Filter = if ($Modo -eq "exportar") { "Desenhos SolidWorks|*.SLDDRW" } else { "Peças e montagens|*.SLDPRT;*.SLDASM" }
    if ($dlg.ShowDialog() -ne "OK") { exit 0 }
    $Arquivos = $dlg.FileNames
}
$lista = @()
foreach ($a in $Arquivos) {
    if (Test-Path $a -PathType Container) {
        $ext = if ($Modo -eq "exportar") { @("*.SLDDRW") } else { @("*.SLDPRT", "*.SLDASM") }
        foreach ($e in $ext) { $lista += @(Get-ChildItem -Path $a -Filter $e | ForEach-Object { $_.FullName }) }
    } elseif ($a -match '\.txt$' -and (Test-Path $a)) {
        # arquivo .txt com um caminho por linha
        foreach ($l in (Get-Content -Path $a -Encoding UTF8)) { $t = $l.Trim(); if ($t -and -not $t.StartsWith("#") -and (Test-Path -LiteralPath $t)) { $lista += $t } elseif ($t -and -not $t.StartsWith("#")) { Log "   Não encontrado: $t" "Yellow" } }
    } elseif (Test-Path -LiteralPath $a) { $lista += (Resolve-Path -LiteralPath $a).ProviderPath }   # ProviderPath: caminho de rede (\\servidor\...) sem o prefixo "Microsoft.PowerShell.Core\FileSystem::" que o SolidWorks não abre
}
Log "==================== $Modo : $($lista.Count) arquivo(s) ====================" "Cyan"
if ($PastaSaida -ne "") { Log "Saída de TESTE: $PastaSaida (o servidor não é alterado)" "Cyan" }

$nOk = 0; $nErro = 0; $nItem = 0
AbrirJanelaStatus   # janelinha "Gerando detalhamento" com animação
foreach ($arq in $lista) {
    $nItem++
    StatusPeca ([IO.Path]::GetFileNameWithoutExtension($arq) + $(if ($lista.Count -gt 1) { "  ($nItem de $($lista.Count))" } else { "" }))
    Log ">> $arq" "White"
    try {
        if (EhIgnorado $arq) { Log "   Item comercial (pasta ignorada). Pulando." "DarkGray"; continue }
        $ext = [IO.Path]::GetExtension($arq).ToUpper()
        if ($Modo -eq "gerar") {
            Gerar $arq
        } elseif ($Modo -eq "exportar") {
            if ($ext -ne ".SLDDRW") { $arq = [IO.Path]::ChangeExtension($arq, ".SLDDRW"); if (-not (Test-Path $arq)) { throw "não existe desenho para este arquivo" } }
            Exportar $arq
        } elseif ($ext -eq ".SLDPRT") {
            $peca = AbrirDoc $arq $DocPART
            if (-not $peca) { throw "não consegui abrir a peça" }
            DetalharPeca $arq $peca
        } elseif ($ext -eq ".SLDASM") {
            $asm = AbrirDoc $arq $DocASM
            if (-not $asm) { throw "não consegui abrir a montagem" }
            DetalharMontagem $arq $asm
        } else { Log "   Tipo não suportado: $ext" "DarkGray"; continue }
        $nOk++
    } catch {
        $nErro++
        Log ("   ERRO: " + $_.Exception.Message + " (" + [IO.Path]::GetFileName($_.InvocationInfo.ScriptName) + " linha " + $_.InvocationInfo.ScriptLineNumber + ")") "Red"
        Relatorio $arq "" $Modo "erro" $_.Exception.Message
    } finally {
        foreach ($d in $script:novosDesenhos) {
            $ehDxf = $script:dxfDesenhos -contains $d   # desenho auxiliar do DXF sempre fecha
            if ($FecharDesenho -or $ehDxf) { try { X $sw "CloseDoc" (Titulo $d) | Out-Null } catch { } }
        }
        $script:dxfDesenhos = @()
        $script:novosDesenhos = @()
        FecharAbertos
    }
}
Log "Concluído: $nOk ok, $nErro com erro. Log: $LogFile" "Cyan"
SoltarTrava   # libera para o próximo (o enquadramento do AutoCAD já terminou)
FecharJanelaStatus ($nErro -gt 0)
if ($Modo -eq "gerar") {
    # janela fecha sozinha sempre (o Monitor mostra o resultado/erro no aviso e o detalhe fica no log.txt)
    if ($nErro -gt 0) { Write-Host ""; Write-Host "Deu erro (veja o aviso do Monitor ou o log.txt). Fechando..." -ForegroundColor Yellow; Start-Sleep -Seconds 3 }
    else { Start-Sleep -Seconds 1 }
}
