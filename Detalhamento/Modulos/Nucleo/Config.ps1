# Config.ps1 - log, relatório e leitura do detalhamento.ini
# Carregado pelo DetalharSW.ps1 (dot-source). Não rodar sozinho.

function Log([string]$msg, [string]$cor = "Gray") {
    $linha = (Get-Date -Format "HH:mm:ss") + "  " + $msg
    Write-Host $linha -ForegroundColor $cor
    # log.txt é um só no servidor: com duas pessoas gerando ao mesmo tempo o arquivo fica ocupado por instantes.
    # Tenta de novo e, se não der, segue sem gravar (antes o erro de gravação interrompia as cotas)
    for ($t = 0; $t -lt 5; $t++) { try { Add-Content -Path $LogFile -Value $linha -Encoding UTF8 -ErrorAction Stop; break } catch { Start-Sleep -Milliseconds 120 } }
    if ($script:ui) { $t = $msg.Trim(); if ($t -and -not $t.StartsWith("[dbg]") -and -not $t.StartsWith("(")) { $script:ui.Texto = $t } }   # etapa atual na janelinha
}
function Relatorio($arquivo, $tipo, $acao, $resultado, $msg) {
    for ($t = 0; $t -lt 5; $t++) {
        try {
            if (-not (Test-Path $RelFile)) { Add-Content -Path $RelFile -Value "DATA;ARQUIVO;TIPO;ACAO;RESULTADO;MENSAGEM" -Encoding UTF8 -ErrorAction Stop }
            Add-Content -Path $RelFile -Value ((Get-Date -Format "dd/MM/yyyy HH:mm") + ";$arquivo;$tipo;$acao;$resultado;$msg") -Encoding UTF8 -ErrorAction Stop
            break
        } catch { Start-Sleep -Milliseconds 120 }
    }
}

# ---------------------------------------------------------------- configuracao
function LerIni($caminho) {
    $h = @{}
    if (Test-Path $caminho) {
        foreach ($l in (Get-Content -Path $caminho -Encoding UTF8)) {
            $t = $l.Trim()
            if ($t -eq "" -or $t.StartsWith("#")) { continue }
            $i = $t.IndexOf("=")
            if ($i -gt 0) { $h[$t.Substring(0, $i).Trim()] = $t.Substring($i + 1).Trim() }
        }
    }
    return $h
}
$cfg = LerIni (Join-Path $Pasta "detalhamento.ini")
$mon = LerIni (Join-Path (Split-Path -Parent $Pasta) "config.ini")   # config do Monitor SW (regras laser/solda)
function C($nome, $padrao) { if ($cfg.ContainsKey($nome) -and $cfg[$nome] -ne "") { return $cfg[$nome] } ; return $padrao }
function M($nome, $padrao) { if ($mon.ContainsKey($nome) -and $mon[$nome] -ne "") { return $mon[$nome] } ; return $padrao }
function Sim($v) { return ($v -match '^(s|sim|y|yes|1|true)') }

$PropDesc      = M "PropriedadeDescricao" "DESCRIÇÃO"
$PalavrasLaser = (M "PalavrasLaser" "LASER").Split("|")
$PastasSolda   = (M "PastasSolda" "1301|1304").Split("|")
$PastasIgnorar = (M "PastasIgnoradas" "03 (MATÉRIA PRIMA)").Split("|")
$PastaSaida    = C "PastaSaida" ""
if ($PastaSaida -ne "" -and -not [IO.Path]::IsPathRooted($PastaSaida)) { $PastaSaida = Join-Path $Pasta $PastaSaida }
$Sobrescrever  = Sim (C "Sobrescrever" "não")
$InserirCotas  = Sim (C "InserirCotas" "sim")
$PropsUsinagem = (M "PropriedadesUsinagem" "TORNO|TORNO CNC|FRESA|FRESA CNC|FURADEIRA|ELETRO").Split("|")
$NomesTemplate = (C "NomesDesenhistaNoTemplate" "MATEUS|Victor E.|G. DIAS|G. Dias|ZAQUEU").Split("|")
$FatorIso      = [double](C "FatorEscalaIsometrica" "0.7").Replace(",", ".")
$VistaFrontal  = C "VistaFrontal" "*Frontal"
$TabelaSolda   = C "TemplateListaSolda" ""
$NotaDxf       = Sim (C "NotaDescricaoNoDxf" "sim")
$VistaLateralDxf = Sim (C "VistaEspessuraNoDxf" "sim")
$FecharDesenho = Sim (C "FecharDesenhoAoTerminar" "sim")
$FurosParaTabela = [int](C "FurosParaTabela" "9")   # usinada com MAIS DE 8 furos na vista principal: tabela de furos (regra do setor)
$script:dxfDesenhos = @()
# chamado pelo Monitor (botão Gerar detalhamento)
if ($Destino -eq "servidor") { $PastaSaida = "" }
if ($Modo -eq "gerar") { $Sobrescrever = [bool]$Recriar; $FecharDesenho = $false }   # pelo Monitor: o desenho gerado fica aberto no SolidWorks
$script:FazPdf = $true; $script:FazDxf = "auto"

# area util da folha A4 paisagem (metros) - acima do carimbo
$DistCota = 0.010   # distância da cota total até a peça (na folha)
$AreaL = 0.022; $AreaR = 0.287; $AreaT = 0.186; $AreaB = 0.046; $Gap = 0.030
$Escalas = @(@(5,1),@(4,1),@(2,1),@(1,1),@(1,1.5),@(1,2),@(1,2.5),@(1,3),@(1,4),@(1,5),@(1,7.5),@(1,10),@(1,15),@(1,20),@(1,25),@(1,30),@(1,40),@(1,50))

Log "Iniciando DetalharSW (modo $Modo, PowerShell $($PSVersionTable.PSVersion), admin: $(([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)))"
