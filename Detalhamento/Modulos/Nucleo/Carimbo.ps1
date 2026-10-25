# Carimbo.ps1 - nome do desenhista no carimbo
# Carregado pelo DetalharSW.ps1 (dot-source). Não rodar sozinho.

# ---------------------------------------------------------------- desenhista (nome no carimbo)
function NomeDesenhista {
    if ($Desenhista -and $Desenhista.Trim() -ne "") { return $Desenhista.Trim() }   # login do Monitor
    foreach ($chave in @("Desenhista.$env:USERNAME", "Desenhista.$env:COMPUTERNAME")) {
        if ($cfg.ContainsKey($chave) -and $cfg[$chave] -ne "") { return $cfg[$chave] }
    }
    return $env:USERNAME.ToUpper()
}
function TrocarDesenhista($dm) {
    $nome = NomeDesenhista
    $trocou = $false
    try {
        X $dm "EditTemplate" | Out-Null
        $sv = X $dm "GetFirstView"
        $notas = @(X $sv "GetNotes")
        foreach ($n in $notas) {
            if (-not $n) { continue }
            $t = ([string](X $n "GetText")).Trim()
            foreach ($alvo in $NomesTemplate) {
                if ($alvo -and $t -eq $alvo.Trim()) { X $n "SetText" $nome | Out-Null; $trocou = $true }
            }
        }
    } catch { Log "   (não consegui trocar o desenhista: $($_.Exception.Message))" "DarkYellow" }
    finally { try { X $dm "EditSheet" | Out-Null } catch { } }
    if ($trocou) { Log "   Desenhista no carimbo: $nome" } else { Log "   Aviso: não achei o nome do desenhista no carimbo para trocar (NomesDesenhistaNoTemplate no .ini)." "Yellow" }
}
