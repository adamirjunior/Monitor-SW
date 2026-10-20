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

function Log([string]$msg, [string]$cor = "Gray") {
    $linha = (Get-Date -Format "HH:mm:ss") + "  " + $msg
    Write-Host $linha -ForegroundColor $cor
    Add-Content -Path $LogFile -Value $linha -Encoding UTF8
}
function Relatorio($arquivo, $tipo, $acao, $resultado, $msg) {
    if (-not (Test-Path $RelFile)) { Add-Content -Path $RelFile -Value "DATA;ARQUIVO;TIPO;ACAO;RESULTADO;MENSAGEM" -Encoding UTF8 }
    Add-Content -Path $RelFile -Value ((Get-Date -Format "dd/MM/yyyy HH:mm") + ";$arquivo;$tipo;$acao;$resultado;$msg") -Encoding UTF8
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
# chamado pelo Monitor (botão Gerar detalhamento)
if ($Destino -eq "servidor") { $PastaSaida = "" }
if ($Modo -eq "gerar") { $Sobrescrever = [bool]$Recriar }
$script:FazPdf = $true; $script:FazDxf = "auto"

# area util da folha A4 paisagem (metros) - acima do carimbo
$DistCota = 0.010   # distância da cota total até a peça (na folha)
$AreaL = 0.022; $AreaR = 0.287; $AreaT = 0.186; $AreaB = 0.046; $Gap = 0.030
$Escalas = @(@(5,1),@(4,1),@(2,1),@(1,1),@(1,1.5),@(1,2),@(1,2.5),@(1,3),@(1,4),@(1,5),@(1,7.5),@(1,10),@(1,15),@(1,20),@(1,25),@(1,30),@(1,40),@(1,50))

Log "Iniciando DetalharSW (modo $Modo, PowerShell $($PSVersionTable.PSVersion), admin: $(([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)))"

# ---------------------------------------------------------------- ponte COM
# O PowerShell não consegue ler a tabela de métodos do SolidWorks ("Elemento não encontrado"),
# então todas as chamadas passam por IDispatch direto (InvokeMember).
if (-not ("SwCom" -as [type])) {
Add-Type -TypeDefinition @"
using System;
using System.Reflection;
using System.Runtime.InteropServices;
public static class SwCom {
    public static object Call(object o, string m, object[] a) {
        if (a == null) a = new object[0];
        return o.GetType().InvokeMember(m, BindingFlags.InvokeMethod, null, o, a);
    }
    public static object Get(object o, string p) {
        return o.GetType().InvokeMember(p, BindingFlags.GetProperty, null, o, null);
    }
    public static void Set(object o, string p, object v) {
        o.GetType().InvokeMember(p, BindingFlags.SetProperty, null, o, new object[] { v });
    }
    public static object NullDisp() { return new DispatchWrapper(null); }
    public static object OpenDoc6(object sw, string f, int t, int opt, string cfg) {
        object[] a = new object[] { f, t, opt, cfg, 0, 0 };
        ParameterModifier pm = new ParameterModifier(6);
        pm[4] = true; pm[5] = true;
        return sw.GetType().InvokeMember("OpenDoc6", BindingFlags.InvokeMethod, null, sw, a, new ParameterModifier[] { pm }, null, null);
    }
    public static double[] Dbl(object v) {
        if (v == null) return null;
        Array arr = v as Array;
        if (arr == null) return null;
        double[] r = new double[arr.Length];
        for (int i = 0; i < arr.Length; i++) r[i] = Convert.ToDouble(arr.GetValue(i));
        return r;
    }
}
"@
}
function Base($v) {
    if ($null -eq $v) { return $null }
    if ($v -is [array]) { return ,$v }        # não deixar o PowerShell desmontar arrays (double[] vira object[] e o SW lê errado)
    $b = $v.psobject.BaseObject; if ($null -ne $b) { return $b }; return $v
}
function X($o, [string]$m) {                                                     # chama método
    $a = New-Object object[] $args.Count
    for ($i = 0; $i -lt $args.Count; $i++) { $a[$i] = Base $args[$i] }
    try { return [SwCom]::Call((Base $o), $m, $a) } catch { throw ("$m" + ": " + $_.Exception.InnerException.Message) }
}
function XG($o, [string]$p) { return [SwCom]::Get((Base $o), $p) }                       # lê propriedade
function XS($o, [string]$p, $v) { [SwCom]::Set((Base $o), $p, (Base $v)) }                      # grava propriedade
function XD($v) { return [SwCom]::Dbl($v) }                                       # array de double

# ---------------------------------------------------------------- SolidWorks
Log "Conectando ao SolidWorks..."
$sw = $null
try { $sw = [Runtime.InteropServices.Marshal]::GetActiveObject("SldWorks.Application") } catch { }
if (-not $sw) {
    Log "SolidWorks não está aberto. Abrindo..." "Yellow"
    try { $sw = New-Object -ComObject "SldWorks.Application.24" } catch { $sw = New-Object -ComObject "SldWorks.Application" }
    XS $sw "Visible" $true
    Start-Sleep -Seconds 5
}
$rev = "?"; try { $rev = X $sw "RevisionNumber" } catch { $rev = "? (" + $_.Exception.Message + ")" }
Log "Conectado ao SolidWorks $rev"

# constantes do SolidWorks (lidas da biblioteca swconst instalada; se não achar, usa o valor conhecido)
$script:swconst = $null
try { $script:swconst = [Reflection.Assembly]::LoadWithPartialName("SolidWorks.Interop.swconst") } catch { }
if (-not $script:swconst) {
    $cands = @()
    try { $dir = (Get-ItemProperty "HKLM:\SOFTWARE\SolidWorks\SOLIDWORKS 2016\Setup" -ErrorAction Stop)."SolidWorks Folder"; if ($dir) { $cands += (Join-Path $dir "api\redist\SolidWorks.Interop.swconst.dll"); $cands += (Join-Path $dir "SolidWorks.Interop.swconst.dll") } } catch { }
    $cands += "$env:ProgramFiles\SOLIDWORKS Corp\SOLIDWORKS\api\redist\SolidWorks.Interop.swconst.dll"
    $cands += "D:\SOLIDWORKS\api\redist\SolidWorks.Interop.swconst.dll"
    $cands += "D:\SOLIDWORKS\SolidWorks.Interop.swconst.dll"
    foreach ($c in $cands) { if (Test-Path $c) { try { $script:swconst = [Reflection.Assembly]::LoadFrom($c); break } catch { } } }
}
if (-not $script:swconst) { Log "Aviso: biblioteca swconst não encontrada; usando constantes internas." "Yellow" }
function K([string]$enum, [string[]]$nomes, [int]$padrao) {
    if ($script:swconst) {
        $t = $script:swconst.GetType("SolidWorks.Interop.swconst.$enum")
        if ($t) { foreach ($n in $nomes) { try { return [int][Enum]::Parse($t, $n) } catch { } } }
    }
    return $padrao
}
$DocPART = 1; $DocASM = 2; $DocDRW = 3
$OptSilent = K "swOpenDocOptions_e" @("swOpenDocOptions_Silent") 1
$SaveSilent = K "swSaveAsOptions_e" @("swSaveAsOptions_Silent") 1
$SaveCopy = K "swSaveAsOptions_e" @("swSaveAsOptions_Copy") 2
$DispHidden = K "swDisplayMode_e" @("swHIDDEN") 2
$DispShaded = K "swDisplayMode_e" @("swSHADED") 3
$PaperUser = K "swDwgPaperSizes_e" @("swDwgPapersUserDefined") 12
$TplNone = K "swDwgTemplates_e" @("swDwgTemplateNone") 13
$InsDims = K "swInsertAnnotation_e" @("swInsertDimensionsMarkedForDrawing") 32768
$InsHoleCallout = K "swInsertAnnotation_e" @("swInsertHoleWizardProfileDims") 0
$AnchorBR = K "swBOMConfigurationAnchorType_e" @("swBOMConfigurationAnchor_BottomRight") 4
$BomParts = K "swBomType_e" @("swBomType_PartsOnly") 2
$NumNone = K "swNumberingType_e" @("swNumberingType_None", "swIndentedBOMNotSet") 0

# template do detalhamento
function AcharTemplate {
    $t = C "TemplateDesenho" ""
    if ($t -ne "" -and (Test-Path $t)) { return $t }
    $cands = @("$env:ProgramData\SolidWorks\SOLIDWORKS 2016\templates\DETALHAMENTO.drwdot",
               "$env:ProgramData\SOLIDWORKS\SOLIDWORKS 2016\templates\DETALHAMENTO.drwdot")
    foreach ($c in $cands) { if (Test-Path $c) { return $c } }
    $dir = "$env:ProgramData\SolidWorks\SOLIDWORKS 2016\templates"
    if (Test-Path $dir) { $f = Get-ChildItem $dir -Filter "*.drwdot" | Where-Object { $_.Name -match "DETALHAMENTO" } | Select-Object -First 1; if ($f) { return $f.FullName } }
    return ""
}
$Template = AcharTemplate
if ($Template -eq "") { Log "ERRO: não achei o template DETALHAMENTO.drwdot. Informe o caminho em detalhamento.ini (TemplateDesenho=)." "Red"; Read-Host "Enter para sair"; exit 1 }
Log "Template: $Template"

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
function EhLaser($desc) { foreach ($p in $PalavrasLaser) { if ($p -and $desc.ToUpper().Contains($p.ToUpper())) { return $true } }; return $false }
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
    $ext = XG $dm "Extension"
    return (X $ext "SelectByID2" (X $vista "GetName2") "DRAWINGVIEW" 0.0 0.0 0.0 $false 0 ([SwCom]::NullDisp()) 0)
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
function Deitar($dm, $v) {
    if (-not $v) { return }
    try {
        $o = Contorno $v
        if ($o.h -gt 1.6 * $o.w) {
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
function CorDxf($arq) {
    try {
        $enc = [Text.Encoding]::Default
        $L = [IO.File]::ReadAllLines($arq, $enc)
        $out = New-Object System.Collections.Generic.List[string]
        $sec = ""; $n = 0; $lfac = $false
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
            if ($sec -eq "ENTITIES" -or $sec -eq "BLOCKS") {
                if ($c -eq "8" -and $v.Trim() -ne "0" -and $v.Trim() -notmatch "DEFPOINTS") { $v = "0"; $n++ }
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
                $casas = 0; if ([math]::Abs($mm - [math]::Round($mm, 0)) -gt 0.0005) { $casas = 1 }; if ([math]::Abs($mm - [math]::Round($mm, 1)) -gt 0.0005) { $casas = 2 }
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
function GerarDxf($caminhoPeca, $peca, $destinoDxf, $desc) {
    $d = NovoDesenho
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
                Selecionar $d $v | Out-Null
                $lat = X $d "CreateUnfoldedViewAt3" ($o.x2 + 0.05) (($o.y1 + $o.y2) / 2) 0.0 $false
                if ($lat) { Modo $lat $DispHidden $true }
            } catch { Log "   (sem vista de espessura no DXF: $($_.Exception.Message))" "DarkYellow" }
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
                $nc += CotaTotal $d $lat $true (-not $mesmaAltura)
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
        Rebuild $d
        SalvarComo $d $destinoDxf ($SaveSilent + $SaveCopy)
        CorDxf $destinoDxf
    } finally {
        Fechar $d
    }
}


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

# ---------------------------------------------------------------- processo / cotas
function TemUsinagem($peca) {
    foreach ($p in $PropsUsinagem) { if ($p -and (Prop $peca $p).Trim() -ne "") { return $true } }
    return $false
}
$script:mu = $null
$script:xfCache = @{}
$script:xfModo = @{}
# transformação modelo -> folha calculada aqui (MathUtility pela ponte COM devolvia sempre o mesmo ponto)
function DadosXf($v) {
    $nomeV = [string](X $v "GetName2")
    if (-not $script:xfCache.ContainsKey($nomeV)) { $script:xfCache[$nomeV] = XD (XG (XG $v "ModelToViewTransform") "ArrayData") }
    return $script:xfCache[$nomeV]
}
function AplicarXf($a, [double[]]$p, [int]$modo) {
    $rx = $p[0] * $a[0] + $p[1] * $a[3] + $p[2] * $a[6]
    $ry = $p[0] * $a[1] + $p[1] * $a[4] + $p[2] * $a[7]
    switch ($modo) {
        0 { return @(($rx * $a[12] + $a[9]), ($ry * $a[12] + $a[10])) }       # escala depois gira, + translação
        1 { return @((($rx + $a[9]) * $a[12]), (($ry + $a[10]) * $a[12])) }   # (gira + translação) * escala
        2 { $rx = $p[0] * $a[0] + $p[1] * $a[1] + $p[2] * $a[2]; $ry = $p[0] * $a[3] + $p[1] * $a[4] + $p[2] * $a[5]; return @(($rx * $a[12] + $a[9]), ($ry * $a[12] + $a[10])) }
        3 { $rx = $p[0] * $a[0] + $p[1] * $a[1] + $p[2] * $a[2]; $ry = $p[0] * $a[3] + $p[1] * $a[4] + $p[2] * $a[5]; return @((($rx + $a[9]) * $a[12]), (($ry + $a[10]) * $a[12])) }
    }
}
# escolhe a fórmula que coloca os pontos dentro do contorno da vista
function EscolherModoXf($v, $pontosModelo) {
    $nomeV = [string](X $v "GetName2")
    if ($script:xfModo.ContainsKey($nomeV)) { return $script:xfModo[$nomeV] }
    $a = DadosXf $v; $o = Contorno $v; $melhor = 0; $melhorQtd = -1
    foreach ($m in 0, 1, 2, 3) {
        $dentro = 0
        foreach ($pm in $pontosModelo) { $q = AplicarXf $a $pm $m; if ($q[0] -ge $o.x1 - 0.002 -and $q[0] -le $o.x2 + 0.002 -and $q[1] -ge $o.y1 - 0.002 -and $q[1] -le $o.y2 + 0.002) { $dentro++ } }
        if ($dentro -gt $melhorQtd) { $melhorQtd = $dentro; $melhor = $m }
    }
    Log "   [dbg] $nomeV : fórmula $melhor ($melhorQtd de $($pontosModelo.Count) pontos dentro do contorno)" "DarkGray"
    $script:xfModo[$nomeV] = $melhor
    return $melhor
}
function Rot($a, [double[]]$p) {
    return @(($p[0] * $a[0] + $p[1] * $a[3] + $p[2] * $a[6]), ($p[0] * $a[1] + $p[1] * $a[4] + $p[2] * $a[7]))
}
function NaFolha($v, [double[]]$pt) {
    $nomeV = [string](X $v "GetName2")
    $m = if ($script:xfModo.ContainsKey($nomeV)) { $script:xfModo[$nomeV] } else { 0 }
    return AplicarXf (DadosXf $v) $pt $m
}
function Entidades($v, [string]$tipo, [int]$padrao) {
    $t = K "swViewEntityType_e" @($tipo) $padrao
    $r = X $v "GetVisibleEntities2" ([SwCom]::NullDisp()) $t
    if (-not $r) { return @() }
    return @($r)
}
function SelecionarEntidade($dm, $v, $ent, [bool]$somar) {
    try {
        $sd = X (XG $dm "SelectionManager") "CreateSelectData"
        XS $sd "View" $v
        if (X $ent "Select4" $somar $sd) { return $true }
    } catch { }
    try { if (X $v "SelectEntity" $ent $somar) { return $true } } catch { }
    return $false
}
# cota total horizontal (acima da vista) e/ou vertical (à esquerda) entre os vértices extremos
function QtdSelecionados($dm) { try { return [int](X (XG $dm "SelectionManager") "GetSelectedObjectCount2" -1) } catch { return 0 } }
function CotaEntre($dm, $v, $a, $b, $x, $y, [string]$nome) {
    $metodo = if ($nome -eq "horizontal") { "AddHorizontalDimension2" } else { "AddVerticalDimension2" }
    X $dm "ClearSelection2" $true | Out-Null
    $s1 = SelecionarEntidade $dm $v $a[0] $false; $s2 = SelecionarEntidade $dm $v $b[0] $true
    $q = QtdSelecionados $dm
    if ($q -ne 2) { Log "   (cota $nome de $(X $v 'GetName2') não feita: $q selecionado(s))" "DarkYellow"; return 0 }
    try { $d = X $dm $metodo ([double]$x) ([double]$y) 0.0; if ($d) { return 1 } } catch { Log "   ($metodo falhou: $($_.Exception.Message))" "DarkYellow" }
    return 0
}
function CotaTotal($dm, $v, [bool]$horiz, [bool]$vert) {
    $verts = Entidades $v "swViewEntityType_Vertex" 3
    if ($verts.Count -lt 2) { return (CotaTotalSemVertices $dm $v $horiz $vert) }
    $modelo = @(); $okVerts = @()
    foreach ($vx in $verts) { try { $modelo += ,([double[]](XD (X $vx "GetPoint"))); $okVerts += $vx } catch { } }
    if ($modelo.Count -lt 2) { return 0 }
    # para achar os extremos basta a rotação da vista (escala e translação não mudam a ordem)
    $a0 = DadosXf $v
    $pts = @()
    for ($k = 0; $k -lt $modelo.Count; $k++) { $pts += ,@($okVerts[$k], (Rot $a0 $modelo[$k])) }
    $o = Contorno $v; $n = 0
    # caixa real da peça na folha: o contorno da vista tem folga em volta; tamanho real = medida rotacionada x escala,
    # e a folga é igual dos dois lados (assim a cota fica a $DistCota da peça e não do contorno)
    $cx1 = $o.x1; $cx2 = $o.x2; $cy1 = $o.y1; $cy2 = $o.y2
    try {
        $esc = [double](XG $v "ScaleDecimal")
        $rx = @($pts | ForEach-Object { $_[1][0] }); $ry = @($pts | ForEach-Object { $_[1][1] })
        $w = (($rx | Measure-Object -Maximum).Maximum - ($rx | Measure-Object -Minimum).Minimum) * $esc
        $h = (($ry | Measure-Object -Maximum).Maximum - ($ry | Measure-Object -Minimum).Minimum) * $esc
        $fx = (($o.x2 - $o.x1) - $w) / 2; $fy = (($o.y2 - $o.y1) - $h) / 2
        if ($fx -gt 0 -and $fx -lt 0.05) { $cx1 = $o.x1 + $fx; $cx2 = $o.x2 - $fx }
        if ($fy -gt 0 -and $fy -lt 0.05) { $cy1 = $o.y1 + $fy; $cy2 = $o.y2 - $fy }
    } catch { }
    $tol = 0.0002
    if ($horiz) {
        # extremos em X; entre vértices empatados usa o mais alto (linha de chamada curta até a cota em cima)
        $minX = ($pts | ForEach-Object { $_[1][0] } | Measure-Object -Minimum).Minimum
        $maxX = ($pts | ForEach-Object { $_[1][0] } | Measure-Object -Maximum).Maximum
        $a = @($pts | Where-Object { $_[1][0] -le $minX + $tol } | Sort-Object { $_[1][1] })[-1]
        $b = @($pts | Where-Object { $_[1][0] -ge $maxX - $tol } | Sort-Object { $_[1][1] })[-1]
        if ([math]::Abs($maxX - $minX) -gt 0.001) { $n += CotaEntre $dm $v $a $b (($cx1 + $cx2) / 2) ($cy2 + $DistCota) "horizontal" }
    }
    if ($vert) {
        # extremos em Y; entre vértices empatados usa o mais à esquerda (cota fica à esquerda)
        $minY = ($pts | ForEach-Object { $_[1][1] } | Measure-Object -Minimum).Minimum
        $maxY = ($pts | ForEach-Object { $_[1][1] } | Measure-Object -Maximum).Maximum
        $a = @($pts | Where-Object { $_[1][1] -le $minY + $tol } | Sort-Object { $_[1][0] })[0]
        $b = @($pts | Where-Object { $_[1][1] -ge $maxY - $tol } | Sort-Object { $_[1][0] })[0]
        if ([math]::Abs($maxY - $minY) -gt 0.001) { $n += CotaEntre $dm $v $a $b ($cx1 - $DistCota) (($cy1 + $cy2) / 2) "vertical" }
    }
    X $dm "ClearSelection2" $true | Out-Null
    return $n
}
# peça redonda (arruela, disco, bucha vista de lado...): não tem cantos. Cota o diâmetro dos círculos
# e/ou a distância entre as linhas retas extremas (aresta de silhueta não tem vértice)
function CotaTotalSemVertices($dm, $v, [bool]$horiz, [bool]$vert) {
    $a = DadosXf $v; $o = Contorno $v; $n = 0
    $circ = @(); $lin = @()
    foreach ($e in (Entidades $v "swViewEntityType_Edge" 1)) {
        try {
            $c = X $e "GetCurve"
            if (X $c "IsCircle") {
                $sv = $null; try { $sv = X $e "GetStartVertex" } catch { }
                if ($sv) { continue }
                $cp = XD (XG $c "CircleParams")
                $eixo = Rot $a @($cp[3], $cp[4], $cp[5])
                if ([math]::Abs($eixo[0]) -gt 0.05 -or [math]::Abs($eixo[1]) -gt 0.05) { continue }
                $circ += ,@($e, [math]::Round($cp[6] * 2000, 3))
            } elseif (X $c "IsLine") {
                $cpp = XD (X $e "GetCurveParams2")
                $p1 = Rot $a @($cpp[0], $cpp[1], $cpp[2]); $p2 = Rot $a @($cpp[3], $cpp[4], $cpp[5])
                if ([math]::Abs($p1[0] - $p2[0]) -lt 1e-6) { $lin += ,@($e, 0, $p1[0]) }
                elseif ([math]::Abs($p1[1] - $p2[1]) -lt 1e-6) { $lin += ,@($e, 1, $p1[1]) }
            }
        } catch { }
    }
    # diâmetros: um de cada tamanho (externo e furo)
    $feitos = @{}; $k = 0
    foreach ($ci in ($circ | Sort-Object { -$_[1] })) {
        if ($feitos.ContainsKey($ci[1])) { continue }
        X $dm "ClearSelection2" $true | Out-Null
        if (-not (SelecionarEntidade $dm $v $ci[0] $false)) { continue }
        $tx = $o.x2 + 0.008 + $k * 0.004; $ty = $o.y2 + 0.006 + $k * 0.008
        $d = $null; try { $d = X $dm "AddDiameterDimension2" ([double]$tx) ([double]$ty) 0.0 } catch { }
        if ($d) { $feitos[$ci[1]] = 1; $n++; $k++ }
    }
    # linhas retas extremas (ex.: espessura da arruela vista de lado)
    foreach ($eixo in 0, 1) {
        if (($eixo -eq 0 -and -not $horiz) -or ($eixo -eq 1 -and -not $vert)) { continue }
        $ls = @($lin | Where-Object { $_[1] -eq $eixo } | Sort-Object { $_[2] })
        if ($ls.Count -lt 2) { continue }
        if ([math]::Abs($ls[-1][2] - $ls[0][2]) -lt 0.0005) { continue }
        if ($circ.Count -gt 0 -and $feitos.Count -gt 0) {
            # a medida já está no diâmetro? (vista de frente de peça redonda)
            $tam = [math]::Round([math]::Abs($ls[-1][2] - $ls[0][2]) * 1000, 3)
            if ($feitos.ContainsKey($tam)) { continue }
        }
        X $dm "ClearSelection2" $true | Out-Null
        SelecionarEntidade $dm $v $ls[0][0] $false | Out-Null; SelecionarEntidade $dm $v $ls[-1][0] $true | Out-Null
        if ((QtdSelecionados $dm) -ne 2) { continue }
        $d = $null
        try {
            if ($eixo -eq 0) { $d = X $dm "AddHorizontalDimension2" ([double](($o.x1 + $o.x2) / 2)) ([double]($o.y2 + $DistCota)) 0.0 }
            else { $d = X $dm "AddVerticalDimension2" ([double]($o.x1 - $DistCota)) ([double](($o.y1 + $o.y2) / 2)) 0.0 }
        } catch { }
        if ($d) { $n++ }
    }
    X $dm "ClearSelection2" $true | Out-Null
    if ($n -eq 0) { Log "   (vista $(X $v 'GetName2'): sem cantos nem círculos para cotar)" "DarkYellow" }
    else { Log "   (vista $(X $v 'GetName2'): peça sem cantos - $n cota(s) por diâmetro/linhas)" "DarkGray" }
    return $n
}
# chamada de furo (ex.: 2x Ø4,30 PASSANTE) - uma por diâmetro
function FuroDoAssistente($e) {
    # o recurso dono das faces vizinhas da aresta diz se o furo veio do Assistente de Furação
    try {
        $faces = X $e "GetTwoAdjacentFaces2"
        foreach ($f in @($faces)) {
            if (-not $f) { continue }
            $ft = X $f "GetFeature"
            if ($ft) { $t = [string](X $ft "GetTypeName2"); if ($t -match "(?i)HoleWzd|HoleSeries|AdvHole|CosmeticThread") { return $true } }
        }
    } catch { }
    return $false
}
function ChamadasFuro($dm, $v) {
    $edges = Entidades $v "swViewEntityType_Edge" 1
    $a = DadosXf $v
    $circ = @()
    foreach ($e in $edges) {
        try {
            $c = X $e "GetCurve"
            if (-not (X $c "IsCircle")) { continue }
            $sv = $null; try { $sv = X $e "GetStartVertex" } catch { }
            if ($sv) { continue }   # arco (raio/dobra), não furo
            $cp = XD (XG $c "CircleParams")
            $eixo = Rot $a @($cp[3], $cp[4], $cp[5])
            if ([math]::Abs($eixo[0]) -gt 0.05 -or [math]::Abs($eixo[1]) -gt 0.05) { continue }   # só furo visto de frente
            $diam = [math]::Round($cp[6] * 2000, 2)
            if ($diam -gt 40) { continue }
            $circ += ,@($e, $diam, (Rot $a @($cp[0], $cp[1], $cp[2])))
        } catch { }
    }
    # do menor para o maior; círculo concêntrico a um menor (escareado/rebaixo/rosca) não ganha chamada própria
    $circ = @($circ | Sort-Object { $_[1] })
    $mantidos = @(); $diams = @{}; $qtd = @{}
    foreach ($ci in $circ) {
        $conc = $false
        foreach ($m in $mantidos) { if ([math]::Abs($m[2][0] - $ci[2][0]) -lt 0.0003 -and [math]::Abs($m[2][1] - $ci[2][1]) -lt 0.0003) { $conc = $true; break } }
        if ($conc) { continue }
        $mantidos += ,$ci
        if (-not $diams.ContainsKey($ci[1])) { $diams[$ci[1]] = $ci[0] }
        $qtd[$ci[1]] = 1 + [int]$qtd[$ci[1]]
    }
    $o = Contorno $v; $n = 0
    $total = $diams.Count
    $abaixo = (($o.y1 - $AreaB) -gt 0.03)
    foreach ($d in ($diams.Keys | Sort-Object)) {
        try {
            X $dm "ClearSelection2" $true | Out-Null
            if (-not (SelecionarEntidade $dm $v $diams[$d] $false)) { Log "   (não consegui selecionar o furo Ø$d)" "DarkYellow"; continue }
            # chamadas lado a lado embaixo da vista (cada uma ocupa ~6 cm), ou empilhadas à direita com folga
            if ($abaixo) { $tx = [math]::Min($o.x1 + 0.03 + ($n * 0.065), $AreaR - 0.03); $ty = [math]::Max($o.y1 - 0.014, $AreaB + 0.016) }
            else { $tx = [math]::Min($o.x2 + 0.022, $AreaR - 0.05); $ty = $o.y2 - ($n * 0.020) }
            $hc = $null
            # furo do Assistente de Furação ganha a chamada do SolidWorks (tem quantidade/rosca/escareado);
            # furo feito por corte/extrusão vai direto como nota no padrão ProEstamp
            if (FuroDoAssistente $diams[$d]) { try { $hc = X $dm "AddHoleCallout2" $tx $ty 0.0 } catch { } }
            # furo feito por corte simples: o SolidWorks escreve "Ø8,50 THRU" sem quantidade.
            # Troca por uma nota com seta no padrão ProEstamp: "4 x Ø8,50 PASSANTE"
            # texto da chamada: IDisplayDimension.GetText(parte) — junta todas as partes para achar o THRU
            $txtHc = ""
            if ($hc) { foreach ($pt in @(1, 2, 3, 4, 5)) { try { $txtHc += " " + [string](X $hc "GetText" $pt) } catch { } } }
            $ehNota = $false
            if (-not $hc -or ($txtHc -match "(?i)THRU" -and $txtHc -notmatch "(?i)<NUM_INST>|<hw")) {
                # chamada de furo feito por corte: troca por nota com seta no padrão ProEstamp ("4 x Ø8,50 PASSANTE")
                try {
                    if ($hc) { X $dm "ClearSelection2" $true | Out-Null; $an = AnnOf $hc; $sel = $false; try { $sel = X $an "Select2" $false 0 } catch { }; if (-not $sel) { try { X $an "Select3" $false ([SwCom]::NullDisp()) | Out-Null } catch { } }; X $dm "EditDelete" | Out-Null }
                    X $dm "ClearSelection2" $true | Out-Null
                    SelecionarEntidade $dm $v $diams[$d] $false | Out-Null
                    $q = [int]$qtd[$d]
                    $texto = $(if ($q -gt 1) { "$q x " } else { "" }) + "<MOD-DIAM>" + ([double]$d).ToString("0.00") + " PASSANTE"
                    $nt = X $dm "InsertNote" $texto
                    if ($nt) { X (AnnOf $nt) "SetPosition" $tx $ty 0.0 | Out-Null; $hc = $nt; $ehNota = $true; Log "   (chamada do furo Ø$d escrita como nota: $texto)" "DarkGray" }
                } catch { Log "   (não consegui trocar a chamada do furo: $($_.Exception.Message))" "DarkYellow" }
            } elseif ($hc) { Log "   (texto da chamada: $($txtHc.Trim()))" "DarkGray" }
            if ($hc) {
                $n++; $script:chamadas += ,@($hc, $v)
                # padrão ProEstamp: "4 x Ø8,50 PASSANTE" (furo feito por corte sai "Ø8,50 THRU", sem quantidade)
                if (-not $ehNota) { try {
                    $txt = [string](X $hc "GetText" 1)
                    $novo = $txt -replace "(?i)\bTHRU ALL\b", "PASSANTE TOTAL" -replace "(?i)\bTHRU\b", "PASSANTE"
                    if ($qtd[$d] -gt 1 -and $novo -notmatch "^\s*(<NUM_INST>|\d+\s*[xX])") { $novo = "$($qtd[$d]) x " + $novo }
                    if ($novo -ne $txt) { X $hc "SetText" 1 $novo | Out-Null }
                } catch { } }
                Log "   Furo Ø${d} ($($qtd[$d])x): chamada inserida" "DarkGray"
            }
        } catch { }
    }
    X $dm "ClearSelection2" $true | Out-Null
    return $n
}
# ---------------------------------------------------------------- cotas de peça usinada (padrão ProEstamp, ex.: 02115187)
# totais (comprimento em cima, altura à esquerda, espessura na vista de baixo), posição dos furos, raios e chamada de furo
function CotasUsinagem($dm, $front, $top) {
    $tgl = K "swUserPreferenceToggle_e" @("swInputDimValOnCreate") 10
    $antes = $null
    try { $antes = X $sw "GetUserPreferenceToggle" $tgl; X $sw "SetUserPreferenceToggle" $tgl $false | Out-Null } catch { }
    try {
        $script:xfCache = @{}; $script:xfModo = @{}
        $n = 0
        if ($front) {
            $pm = @(); foreach ($vx in (Entidades $front "swViewEntityType_Vertex" 3)) { try { $pm += ,([double[]](XD (X $vx "GetPoint"))) } catch { } }
            if ($pm.Count -gt 0) { EscolherModoXf $front $pm | Out-Null }
        }
        if ($front) { $n += CotaTotal $dm $front $true $true }
        if ($top) { $n += CotaTotal $dm $top $false $true }
        $p = 0; $r = 0; $f = 0
        if ($front) {
            try { $p = CotasPosicaoFuros $dm $front } catch { Log "   (posição dos furos: $($_.Exception.Message))" "DarkYellow" }
            try { $r = CotasRaios $dm $front } catch { Log "   (raios: $($_.Exception.Message))" "DarkYellow" }
            try { $f = ChamadasFuro $dm $front } catch { Log "   (chamada de furo: $($_.Exception.Message))" "DarkYellow" }
        }
        Log "   Cotas de usinagem: $n totais + $p de posição de furo + $r raio(s) + $f chamada(s) de furo"
        Rebuild $dm
        ResolverSobreposicoes $dm @($front, $top, $script:isoAtual) @("furo")
    } finally { if ($null -ne $antes) { try { X $sw "SetUserPreferenceToggle" $tgl ([bool]$antes) | Out-Null } catch { } } }
}
# furos vistos de frente: [aresta, diâmetro mm, centro girado (x,y)] - só o menor de cada centro (rebaixo/escareado fica de fora)
function FurosDaVista($v) {
    $a = DadosXf $v
    $circ = @()
    foreach ($e in (Entidades $v "swViewEntityType_Edge" 1)) {
        try {
            $c = X $e "GetCurve"
            if (-not (X $c "IsCircle")) { continue }
            $sv = $null; try { $sv = X $e "GetStartVertex" } catch { }
            if ($sv) { continue }
            $cp = XD (XG $c "CircleParams")
            $eixo = Rot $a @($cp[3], $cp[4], $cp[5])
            if ([math]::Abs($eixo[0]) -gt 0.05 -or [math]::Abs($eixo[1]) -gt 0.05) { continue }
            $circ += ,@($e, [math]::Round($cp[6] * 2000, 2), (Rot $a @($cp[0], $cp[1], $cp[2])), [double[]]@($cp[0], $cp[1], $cp[2]))
        } catch { }
    }
    $circ = @($circ | Sort-Object { $_[1] })
    $res = @()
    foreach ($ci in $circ) {
        $conc = $false
        foreach ($m in $res) { if ([math]::Abs($m[2][0] - $ci[2][0]) -lt 0.0003 -and [math]::Abs($m[2][1] - $ci[2][1]) -lt 0.0003) { $conc = $true; break } }
        if (-not $conc) { $res += ,$ci }
    }
    return ,$res
}
# posição dos furos: se estão simétricos no eixo, cota só a distância entre os extremos; senão, cota cada posição a partir da borda.
# O texto da cota fica no meio da linha de cota (meio entre os dois pontos medidos, já na folha).
function MeioFolha($v, [double[]]$p1, [double[]]$p2) {
    $q1 = NaFolha $v $p1; $q2 = NaFolha $v $p2
    return @((($q1[0] + $q2[0]) / 2), (($q1[1] + $q2[1]) / 2))
}
function CotasPosicaoFuros($dm, $v) {
    $furos = FurosDaVista $v
    if ($furos.Count -eq 0) { return 0 }
    $a = DadosXf $v
    $pts = @()
    foreach ($vx in (Entidades $v "swViewEntityType_Vertex" 3)) { try { $pm = [double[]](XD (X $vx "GetPoint")); $pts += ,@($vx, (Rot $a $pm), $pm) } catch { } }
    if ($pts.Count -lt 2) { return 0 }
    EscolherModoXf $v @($pts | ForEach-Object { ,$_[2] }) | Out-Null
    # limites reais da peça (caixa do modelo girada como a vista); os vértices visíveis podem não chegar nos cantos arredondados
    $cb = $script:caixaPeca; $lim = @(@(1e9, -1e9), @(1e9, -1e9))
    if ($cb) {
        foreach ($cx in $cb[0], $cb[3]) { foreach ($cy in $cb[1], $cb[4]) { foreach ($cz in $cb[2], $cb[5]) {
            $r = Rot $a @($cx, $cy, $cz)
            for ($i = 0; $i -lt 2; $i++) { $lim[$i][0] = [math]::Min($lim[$i][0], $r[$i]); $lim[$i][1] = [math]::Max($lim[$i][1], $r[$i]) }
        } } }
    }
    $o = Contorno $v; $n = 0; $tol = 0.0002; $passo = 0.008
    foreach ($eixo in 0, 1) {
        $vals = @($pts | ForEach-Object { $_[1][$eixo] })
        $min = ($vals | Measure-Object -Minimum).Minimum; $max = ($vals | Measure-Object -Maximum).Maximum
        if ($cb) { $min = $lim[$eixo][0]; $max = $lim[$eixo][1] }
        $meio = ($min + $max) / 2
        $pos = @()
        foreach ($h in ($furos | Sort-Object { $_[2][$eixo] })) { if (-not ($pos | Where-Object { [math]::Abs($_[2][$eixo] - $h[2][$eixo]) -lt $tol })) { $pos += ,$h } }
        $sim = $true
        foreach ($h in $pos) { $esp = 2 * $meio - $h[2][$eixo]; if (-not ($pos | Where-Object { [math]::Abs($_[2][$eixo] - $esp) -lt 0.0003 })) { $sim = $false; break } }
        $nome = if ($eixo -eq 0) { "horizontal" } else { "vertical" }
        Log ("   [dbg] furos eixo {0}: posições {1} mm (peça {2:N1}..{3:N1}) simétrico={4}" -f $nome, (($pos | ForEach-Object { "{0:N1}" -f (($_[2][$eixo] - $min) * 1000) }) -join ", "), 0, (($max - $min) * 1000), $sim) "DarkGray"
        $metodo = if ($eixo -eq 0) { "AddHorizontalDimension2" } else { "AddVerticalDimension2" }
        $k = 0
        if ($sim) {
            if ($pos.Count -lt 2) { continue }   # furo(s) no centro: não precisa cota
            X $dm "ClearSelection2" $true | Out-Null
            SelecionarEntidade $dm $v $pos[0][0] $false | Out-Null; SelecionarEntidade $dm $v $pos[-1][0] $true | Out-Null
            if ((QtdSelecionados $dm) -ne 2) { continue }
            $mf = MeioFolha $v $pos[0][3] $pos[-1][3]
            if ($eixo -eq 0) { $x = $mf[0]; $y = $o.y2 + $DistCota + $passo } else { $x = $o.x2 + $DistCota; $y = $mf[1] }
            try { if (X $dm $metodo ([double]$x) ([double]$y) 0.0) { $n++ } } catch { }
        } else {
            # a partir da borda de menor coordenada (esquerda / baixo)
            $borda = @($pts | Sort-Object { $_[1][$eixo] })[0]
            foreach ($h in $pos) {
                X $dm "ClearSelection2" $true | Out-Null
                SelecionarEntidade $dm $v $borda[0] $false | Out-Null; SelecionarEntidade $dm $v $h[0] $true | Out-Null
                if ((QtdSelecionados $dm) -ne 2) { continue }
                $mf = MeioFolha $v $borda[2] $h[3]
                # horizontais em cima (além da cota total), verticais à direita; uma afastada da outra
                if ($eixo -eq 0) { $x = $mf[0]; $y = $o.y2 + $DistCota + ($k + 1) * $passo } else { $x = $o.x2 + $DistCota + $k * $passo; $y = $mf[1] }
                try { if (X $dm $metodo ([double]$x) ([double]$y) 0.0) { $n++; $k++ } } catch { }
            }
        }
    }
    X $dm "ClearSelection2" $true | Out-Null
    return $n
}
# um raio de cada tamanho nos cantos arredondados do contorno
function CotasRaios($dm, $v, [bool]$soMenor = $false) {
    $a = DadosXf $v; $o = Contorno $v; $n = 0
    $feitos = @{}
    $cx = ($o.x1 + $o.x2) / 2; $cy = ($o.y1 + $o.y2) / 2
    $arcos = @()
    foreach ($e in (Entidades $v "swViewEntityType_Edge" 1)) {
        try { $c0 = X $e "GetCurve"; if (X $c0 "IsCircle") { $arcos += ,@($e, [double]((XD (XG $c0 "CircleParams"))[6])) } } catch { }
    }
    $arcos = @($arcos | Sort-Object { $_[1] })   # do menor para o maior (raio interno da dobra primeiro)
    foreach ($ar in $arcos) {
        $e = $ar[0]
        if ($soMenor -and $n -gt 0) { break }
        try {
            $c = X $e "GetCurve"
            if (-not (X $c "IsCircle")) { continue }
            $sv = $null; try { $sv = X $e "GetStartVertex" } catch { }
            if (-not $sv) { continue }   # círculo inteiro = furo
            $cp = XD (XG $c "CircleParams")
            $eixo = Rot $a @($cp[3], $cp[4], $cp[5])
            if ([math]::Abs($eixo[0]) -gt 0.05 -or [math]::Abs($eixo[1]) -gt 0.05) { continue }
            $rmm = [math]::Round($cp[6] * 1000, 2)
            if ($rmm -lt 0.5 -or $feitos.ContainsKey($rmm)) { continue }
            # ponto do arco na folha (vértice inicial) para saber para que lado puxar a cota
            $pv = [double[]](XD (X $sv "GetPoint"))
            $q = NaFolha $v $pv
            $dx = $q[0] - $cx; $dy = $q[1] - $cy; $len = [math]::Sqrt($dx * $dx + $dy * $dy); if ($len -lt 1e-6) { $len = 1 }
            X $dm "ClearSelection2" $true | Out-Null
            if (-not (SelecionarEntidade $dm $v $e $false)) { continue }
            $tx = $q[0] + $dx / $len * 0.012; $ty = $q[1] + $dy / $len * 0.008
            # nunca fora da folha: no máximo um pouco além da vista
            $tx = [math]::Max($o.x1 - 0.015, [math]::Min($o.x2 + 0.015, $tx)); $ty = [math]::Max($o.y1 - 0.010, [math]::Min($o.y2 + 0.010, $ty))
            $d = $null; try { $d = X $dm "AddRadialDimension2" ([double]$tx) ([double]$ty) 0.0 } catch { }
            if ($d) { $feitos[$rmm] = 1; $n++ }
        } catch { }
    }
    X $dm "ClearSelection2" $true | Out-Null
    return $n
}
function CotasLaser($dm, $front, $left, $top, $flat) {
    $tgl = K "swUserPreferenceToggle_e" @("swInputDimValOnCreate") 10
    $antes = $null
    try { $antes = X $sw "GetUserPreferenceToggle" $tgl; X $sw "SetUserPreferenceToggle" $tgl $false | Out-Null } catch { }
    try { CotasLaserInterno $dm $front $left $top $flat } finally { if ($null -ne $antes) { try { X $sw "SetUserPreferenceToggle" $tgl ([bool]$antes) | Out-Null } catch { } } }
}
# caixa real da peça na folha (o contorno da vista tem folga igual dos dois lados)
function CaixaReal($v) {
    $o = Contorno $v
    $r = [pscustomobject]@{ x1 = $o.x1; x2 = $o.x2; y1 = $o.y1; y2 = $o.y2 }
    try {
        $a = DadosXf $v; $esc = [double](XG $v "ScaleDecimal")
        $rx = @(); $ry = @()
        foreach ($vx in (Entidades $v "swViewEntityType_Vertex" 3)) { try { $q = Rot $a ([double[]](XD (X $vx "GetPoint"))); $rx += $q[0]; $ry += $q[1] } catch { } }
        if ($rx.Count -ge 2) {
            $w = (($rx | Measure-Object -Maximum).Maximum - ($rx | Measure-Object -Minimum).Minimum) * $esc
            $h = (($ry | Measure-Object -Maximum).Maximum - ($ry | Measure-Object -Minimum).Minimum) * $esc
            $fx = (($o.x2 - $o.x1) - $w) / 2; $fy = (($o.y2 - $o.y1) - $h) / 2
            if ($fx -gt 0 -and $fx -lt 0.05) { $r.x1 = $o.x1 + $fx; $r.x2 = $o.x2 - $fx }
            if ($fy -gt 0 -and $fy -lt 0.05) { $r.y1 = $o.y1 + $fy; $r.y2 = $o.y2 - $fy }
        }
    } catch { }
    return $r
}
function ValorCota($dd) { try { return [math]::Abs([double](XG (X $dd "GetDimension2" 0) "SystemValue")) } catch { return -1 } }
function ApagarCota($dm, $dd) {
    try { X $dm "ClearSelection2" $true | Out-Null; $an = X $dd "GetAnnotation"; $ok = $false; try { $ok = X $an "Select2" $false 0 } catch { }; if (-not $ok) { try { X $an "Select3" $false ([SwCom]::NullDisp()) | Out-Null } catch { } }; X $dm "EditDelete" | Out-Null } catch { }
}
# cota da ESPESSURA da chapa: procura duas arestas retas paralelas separadas pela espessura (aba vista de lado)
function CotaEspessura($dm, $vistas) {
    $T = [double]$script:espessura
    if ($T -le 0) { return 0 }
    foreach ($v in @($vistas)) {
        if (-not $v) { continue }
        try {
            $a = DadosXf $v
            $lin = @()
            foreach ($e in (Entidades $v "swViewEntityType_Edge" 1)) {
                try {
                    $c = X $e "GetCurve"; if (-not (X $c "IsLine")) { continue }
                    $p1 = Rot $a ([double[]](XD (X (X $e "GetStartVertex") "GetPoint"))); $p2 = Rot $a ([double[]](XD (X (X $e "GetEndVertex") "GetPoint")))
                    if ([math]::Abs($p1[0] - $p2[0]) -lt 1e-6) { $lin += ,@($e, "v", $p1[0], [math]::Min($p1[1], $p2[1]), [math]::Max($p1[1], $p2[1])) }
                    elseif ([math]::Abs($p1[1] - $p2[1]) -lt 1e-6) { $lin += ,@($e, "h", $p1[1], [math]::Min($p1[0], $p2[0]), [math]::Max($p1[0], $p2[0])) }
                } catch { }
            }
            $best = $null; $bestOv = 0
            for ($i = 0; $i -lt $lin.Count; $i++) { for ($j = $i + 1; $j -lt $lin.Count; $j++) {
                $A = $lin[$i]; $B = $lin[$j]
                if ($A[1] -ne $B[1]) { continue }
                if ([math]::Abs([math]::Abs($A[2] - $B[2]) - $T) -gt 0.00003) { continue }
                $ov = [math]::Min($A[4], $B[4]) - [math]::Max($A[3], $B[3])
                if ($ov -gt $bestOv) { $bestOv = $ov; $best = @($A, $B) }
            } }
            if (-not $best) { continue }
            X $dm "ClearSelection2" $true | Out-Null
            SelecionarEntidade $dm $v $best[0][0] $false | Out-Null; SelecionarEntidade $dm $v $best[1][0] $true | Out-Null
            if ((QtdSelecionados $dm) -ne 2) { continue }
            $o = Contorno $v
            $dd = $null
            if ($best[0][1] -eq "v") { $dd = X $dm "AddHorizontalDimension2" ([double](($o.x1 + $o.x2) / 2)) ([double]($o.y1 - $DistCota)) 0.0 }
            else { $dd = X $dm "AddVerticalDimension2" ([double]($o.x2 + $DistCota)) ([double](($o.y1 + $o.y2) / 2)) 0.0 }
            X $dm "ClearSelection2" $true | Out-Null
            if ($dd) { $script:vistaPerfil = $v; Log ("   Cota da espessura ({0:N2} mm) na vista {1}" -f ($T * 1000), (X $v "GetName2")) "DarkGray"; return 1 }
        } catch { }
    }
    Log "   (não achei onde cotar a espessura da chapa)" "DarkYellow"
    return 0
}
# chapa dobrada: cota de cada linha de dobra até a extremidade MAIS PRÓXIMA (o operador mede depois de dobrar).
# A direção de cada linha vem da nota "PARA CIMA/BAIXO" presa a ela (a nota fica no sentido da linha, na folha);
# a linha é a entidade em que a nota está presa. Cria a cota até os dois lados e deixa só a menor.
function AnexosDaNota($an) {
    foreach ($m in "GetAttachedEntities3", "GetAttachedEntities2", "GetAttachedEntities") {
        try { $r = X $an $m; if ($r) { $l = @($r) | Where-Object { $_ }; if ($l.Count -gt 0) { return ,$l } } } catch { }
    }
    return ,@()
}
function CotasLinhasDobra($dm, $v) {
    if (-not $v) { return 0 }
    $a = DadosXf $v; $esc = 1.0; try { $esc = [double](XG $v "ScaleDecimal") } catch { }
    $pts = @()
    foreach ($vx in (Entidades $v "swViewEntityType_Vertex" 3)) { try { $pts += ,@($vx, (Rot $a ([double[]](XD (X $vx "GetPoint"))))) } catch { } }
    if ($pts.Count -lt 2) { return 0 }
    # linhas de dobra da vista (para quando a nota não disser a qual linha está presa)
    $bls = @(); try { $bls = @(X $v "GetBendLines") | Where-Object { $_ } } catch { }
    $itens = @()
    foreach ($nt in @(X $v "GetNotes")) {
        if (-not $nt) { continue }
        $t = [string](X $nt "GetText")
        if ($t -notmatch "(?i)PARA (CIMA|BAIXO)") { continue }
        $an = X $nt "GetAnnotation"
        $ang = 0.0; try { $ang = [double](XG $nt "Angle") } catch { }
        $vertical = ([math]::Abs([math]::Sin($ang)) -gt 0.7)
        $linha = $null
        foreach ($e in (AnexosDaNota $an)) { $linha = $e; break }
        if (-not $linha) { Log "   [dbg] nota de dobra sem linha presa: usando a lista de linhas de dobra" "DarkGray" }
        $itens += ,@($linha, $vertical)
    }
    if ($itens.Count -eq 0 -and $bls.Count -eq 0) { return 0 }
    # nota sem entidade presa: usa as linhas de dobra na mesma ordem
    for ($i = 0; $i -lt $itens.Count; $i++) { if (-not $itens[$i][0] -and $i -lt $bls.Count) { $itens[$i][0] = $bls[$i] } }
    $cr = CaixaReal $v; $o = Contorno $v
    $n = 0; $kH = 0; $kV = 0; $passo = 0.008
    foreach ($it in $itens) {
        $bl = $it[0]; $vertical = $it[1]
        if (-not $bl) { continue }
        try {
            $eixo = if ($vertical) { 0 } else { 1 }        # linha em pé -> cota horizontal (eixo X da folha)
            $ord = @($pts | Sort-Object { $_[1][$eixo] })
            $ext = @($ord[0], $ord[-1])
            $metodo = if ($vertical) { "AddHorizontalDimension2" } else { "AddVerticalDimension2" }
            $res = @()
            foreach ($lado in 0, 1) {
                X $dm "ClearSelection2" $true | Out-Null
                if (-not (SelecionarEntidade $dm $v $bl $false)) { continue }
                SelecionarEntidade $dm $v $ext[$lado][0] $true | Out-Null
                if ((QtdSelecionados $dm) -ne 2) { continue }
                $dd = $null
                try {
                    if ($vertical) { $dd = X $dm $metodo ([double](($o.x1 + $o.x2) / 2)) ([double]($o.y1 - $DistCota - $kH * $passo)) 0.0 }
                    else { $dd = X $dm $metodo ([double]($o.x2 + $DistCota + $kV * $passo)) ([double](($o.y1 + $o.y2) / 2)) 0.0 }
                } catch { }
                if ($dd) { $res += ,@($dd, (ValorCota $dd), $lado) }
            }
            X $dm "ClearSelection2" $true | Out-Null
            $bons = @($res | Where-Object { $_[1] -gt 0.0001 } | Sort-Object { $_[1] })
            foreach ($r in $res) { if ($bons.Count -eq 0 -or $r[0] -ne $bons[0][0]) { ApagarCota $dm $r[0] } }   # fica só a da extremidade mais próxima
            if ($bons.Count -eq 0) { continue }
            $fica = $bons[0]; $val = $fica[1] * $esc
            try {
                $an2 = X $fica[0] "GetAnnotation"
                if ($vertical) {
                    $tx = if ($fica[2] -eq 0) { $cr.x1 + $val / 2 } else { $cr.x2 - $val / 2 }
                    X $an2 "SetPosition" ([double]$tx) ([double]($o.y1 - $DistCota - $kH * $passo)) 0.0 | Out-Null; $kH++
                } else {
                    $ty = if ($fica[2] -eq 0) { $cr.y1 + $val / 2 } else { $cr.y2 - $val / 2 }
                    X $an2 "SetPosition" ([double]($o.x2 + $DistCota + $kV * $passo)) ([double]$ty) 0.0 | Out-Null; $kV++
                }
            } catch { }
            Log ("   Linha de dobra {0}: {1:N2} mm até a extremidade mais próxima" -f $(if ($vertical) { "em pé" } else { "deitada" }), ($fica[1] * 1000)) "DarkGray"
            $n++
        } catch { Log "   (cota da linha de dobra: $($_.Exception.Message))" "DarkYellow" }
    }
    X $dm "ClearSelection2" $true | Out-Null
    return $n
}
# chapa dobrada, vista de perfil (onde aparece a espessura): cota de cada aba (distância entre as faces externas),
# para conferir com paquímetro depois de dobrar. Só quando há mais de 2 faces na direção (2 faces = cota total).
function CotasAbas($dm, $v) {
    if (-not $v) { return 0 }
    $T = [double]$script:espessura; if ($T -le 0) { return 0 }
    $a = DadosXf $v; $o = Contorno $v; $cr = CaixaReal $v; $n = 0
    $esc = 1.0; try { $esc = [double](XG $v "ScaleDecimal") } catch { }
    $lin = @()
    foreach ($e in (Entidades $v "swViewEntityType_Edge" 1)) {
        try {
            $c = X $e "GetCurve"; if (-not (X $c "IsLine")) { continue }
            $p1 = Rot $a ([double[]](XD (X (X $e "GetStartVertex") "GetPoint"))); $p2 = Rot $a ([double[]](XD (X (X $e "GetEndVertex") "GetPoint")))
            if ([math]::Abs($p1[0] - $p2[0]) -lt 1e-6) { $lin += ,@($e, 0, $p1[0], [math]::Abs($p1[1] - $p2[1])) }
            elseif ([math]::Abs($p1[1] - $p2[1]) -lt 1e-6) { $lin += ,@($e, 1, $p1[1], [math]::Abs($p1[0] - $p2[0])) }
        } catch { }
    }
    foreach ($eixo in 0, 1) {
        # posições distintas (a mais longa de cada posição); descarta a face interna de cada aba (a que fica a 1 espessura de outra, para dentro)
        $pos = @()
        foreach ($l in (@($lin | Where-Object { $_[1] -eq $eixo }) | Sort-Object { -$_[3] })) { if (-not ($pos | Where-Object { [math]::Abs($_[2] - $l[2]) -lt 0.00005 })) { $pos += ,$l } }
        $pos = @($pos | Sort-Object { $_[2] })
        if ($pos.Count -lt 2) { continue }
        $min = $pos[0][2]; $max = $pos[-1][2]
        $ext = @()
        foreach ($p in $pos) {
            $par = $pos | Where-Object { [math]::Abs([math]::Abs($_[2] - $p[2]) - $T) -lt 0.00003 } | Select-Object -First 1
            if ($par) { $interna = if ([math]::Abs($p[2] - $min) -lt [math]::Abs($p[2] - $max)) { $p[2] -gt $par[2] } else { $p[2] -lt $par[2] }; if ($interna -and $p[2] -ne $min -and $p[2] -ne $max) { continue } }
            $ext += ,$p
        }
        if ($ext.Count -lt 3) { continue }   # só 2 faces: a cota total já mostra
        $k = 0
        for ($i = 0; $i -lt $ext.Count - 1; $i++) {
            $A = $ext[$i]; $B = $ext[$i + 1]
            if ([math]::Abs($B[2] - $A[2]) -lt $T * 1.5) { continue }   # é a própria espessura
            X $dm "ClearSelection2" $true | Out-Null
            SelecionarEntidade $dm $v $A[0] $false | Out-Null; SelecionarEntidade $dm $v $B[0] $true | Out-Null
            if ((QtdSelecionados $dm) -ne 2) { continue }
            $meio = (($A[2] + $B[2]) / 2 - $min) * $esc
            $dd = $null
            try {
                if ($eixo -eq 0) { $dd = X $dm "AddHorizontalDimension2" ([double]($cr.x1 + $meio)) ([double]($o.y1 - $DistCota - 0.008)) 0.0 }
                else { $dd = X $dm "AddVerticalDimension2" ([double]($o.x2 + $DistCota + 0.008)) ([double]($cr.y1 + $meio)) 0.0 }
            } catch { }
            if ($dd) { $n++; $k++ }
        }
    }
    X $dm "ClearSelection2" $true | Out-Null
    if ($n -gt 0) { Log "   $n cota(s) de aba (distância entre dobras) na vista de perfil" "DarkGray" }
    return $n
}
# notas "PARA CIMA/BAIXO 90° R..." do mesmo tamanho das cotas e centralizadas entre as extremidades da peça
function AjustarNotasDobra($dm, $v) {
    if (-not $v) { return }
    try {
        $alt = 0.0
        try {
            foreach ($an in @(X $v "GetAnnotations")) { if ($an -and [int](X $an "GetType") -eq $AnnDim) { $alt = [double](XG (X $an "GetTextFormat" 0) "CharHeight"); break } }
        } catch { }
        if ($alt -le 0) { $alt = 0.0025 }
        $alt = $alt * 0.8   # um pouco menor que o número das cotas
        $cr = CaixaReal $v; $m = 0
        foreach ($nt in @(X $v "GetNotes")) {
            if (-not $nt) { continue }
            $t = [string](X $nt "GetText")
            if ($t -notmatch "(?i)PARA (CIMA|BAIXO)") { continue }
            $an = X $nt "GetAnnotation"
            try { $tf = X $an "GetTextFormat" 0; XS $tf "CharHeight" $alt; X $an "SetTextFormat" 0 $false $tf | Out-Null } catch { }
            Rebuild $dm
            $ang = 0.0; try { $ang = [double](XG $nt "Angle") } catch { }
            $empe = ([math]::Abs([math]::Sin($ang)) -gt 0.7)
            $ex = XD (X $nt "GetExtent"); $p = XD (X $an "GetPosition")
            if (-not $ex -or -not $p) { continue }
            $mx = ($ex[0] + $ex[3]) / 2; $my = ($ex[1] + $ex[4]) / 2
            if ($empe) { $dyy = (($cr.y1 + $cr.y2) / 2) - $my; X $an "SetPosition" $p[0] ($p[1] + $dyy) 0.0 | Out-Null }
            else { $dxx = (($cr.x1 + $cr.x2) / 2) - $mx; X $an "SetPosition" ($p[0] + $dxx) $p[1] 0.0 | Out-Null }
            $m++
        }
        if ($m -gt 0) { Log ("   $m nota(s) de dobra com {0:N1} mm e centralizadas na peça" -f ($alt * 1000)) "DarkGray" }
    } catch { Log "   (notas de dobra: $($_.Exception.Message))" "DarkYellow" }
}
function CotasLaserInterno($dm, $front, $left, $top, $flat) {
    $n = 0
    if ($front) { $n += CotaTotal $dm $front $true $true }
    if ($left) { $n += CotaTotal $dm $left $true $false }
    # vista de baixo: na chapa plana leva comprimento + espessura; nas outras, só a profundidade (se não houver lateral)
    if ($top -and $script:planaAtual) { $n += CotaTotal $dm $top $true $true }
    elseif ($top -and -not $left) { $n += CotaTotal $dm $top $false $true }
    if ($flat) { $n += CotaTotal $dm $flat $true $true }
    # chapa dobrada: espessura + linha de dobra até a extremidade mais próxima + notas de dobra harmonizadas
    if ($flat) {
        $script:vistaPerfil = $null
        $n += CotaEspessura $dm @($front, $left, $top)
        # (cotas de cada aba e da linha de dobra até a extremidade: desligadas a pedido - informação demais)
        # raio de dobra nas vistas dobradas (um de cada tamanho)
        $nr = 0
        foreach ($vv in @($script:vistaPerfil, $front, $left, $top)) {
            if (-not $vv -or $nr -gt 0) { continue }
            try {
                $pm = @(); foreach ($vx in (Entidades $vv "swViewEntityType_Vertex" 3)) { try { $pm += ,([double[]](XD (X $vx "GetPoint"))) } catch { } }
                if ($pm.Count -gt 0) { EscolherModoXf $vv $pm | Out-Null }
                $nr = CotasRaios $dm $vv $true
            } catch { }
        }
        if ($nr -gt 0) { Log "   $nr raio(s) de dobra cotado(s)" "DarkGray" }
        $n += $nr

        Rebuild $dm
        AjustarNotasDobra $dm $flat
    }
    # peça de laser: furos saem do DXF, não leva chamada de furo (só peças usinadas, que usam as cotas do modelo)
    Log "   Cotas de laser/dobra: $n cotas (sem chamada de furo)"
    Rebuild $dm
    ResolverSobreposicoes $dm @($front, $left, $top, $flat, $script:isoAtual) @("dobra", "furo")
}


# centraliza o conjunto de vistas na área útil (com folga para as cotas em volta)
function Centralizar($dm, $vistas, $baseMin) {
    $vs = @($vistas | Where-Object { $_ })
    if ($vs.Count -eq 0) { return }
    $os = @($vs | ForEach-Object { Contorno $_ })
    $x1 = ($os | ForEach-Object { $_.x1 } | Measure-Object -Minimum).Minimum
    $x2 = ($os | ForEach-Object { $_.x2 } | Measure-Object -Maximum).Maximum
    $y1 = ($os | ForEach-Object { $_.y1 } | Measure-Object -Minimum).Minimum
    $y2 = ($os | ForEach-Object { $_.y2 } | Measure-Object -Maximum).Maximum
    $dx = (($AreaL + $AreaR) / 2) - (($x1 + $x2) / 2)
    $dy = (($baseMin + $AreaT) / 2) - (($y1 + $y2) / 2)
    # não deixa encostar nas bordas (folga mínima de 1 cm)
    $dx = [math]::Max([math]::Min($dx, $AreaR - $x2), $AreaL - $x1)
    $dy = [math]::Max([math]::Min($dy, $AreaT - $y2), $baseMin - $y1)
    if ([math]::Abs($dx) -lt 0.002 -and [math]::Abs($dy) -lt 0.002) { return }
    $antes = @{}
    foreach ($v in $vs) { $antes[[string](X $v "GetName2")] = PosVista $v }
    foreach ($v in $vs) {
        $p0 = $antes[[string](X $v "GetName2")]; $pa = PosVista $v
        $alvoX = $p0[0] + $dx; $alvoY = $p0[1] + $dy
        if ([math]::Abs($pa[0] - $alvoX) -gt 0.0005 -or [math]::Abs($pa[1] - $alvoY) -gt 0.0005) { DefinirPosicao $v $alvoX $alvoY }
    }
    Rebuild $dm
    Log ("   Vistas centralizadas na folha (deslocamento {0:N0} x {1:N0} mm)" -f ($dx * 1000), ($dy * 1000)) "DarkGray"
}
# afasta notas de dobra que ficaram uma em cima da outra (considera texto deitado ou em pé)
function EspalharNotasDobra($dm, $v) {
    if (-not $v) { return }
    try {
        $notas = @(X $v "GetNotes") | Where-Object { $_ }
        $itens = @()
        foreach ($n in $notas) {
            $t = [string](X $n "GetText")
            if ($t -notmatch "(?i)PARA (CIMA|BAIXO)") { continue }
            $an = X $n "GetAnnotation"; $p = XD (X $an "GetPosition")
            $ang = 0.0; try { $ang = [double](XG $n "Angle") } catch { }
            $empe = ([math]::Abs([math]::Sin($ang)) -gt 0.7)
            $L = 0.045; $H = 0.0045
            $w = if ($empe) { $H } else { $L }; $h = if ($empe) { $L } else { $H }
            $itens += ,@($an, $p, $w, $h, $empe)
        }
        $mov = 0
        for ($i = 1; $i -lt $itens.Count; $i++) {
            for ($k = 0; $k -lt $i; $k++) {
                $a = $itens[$k]; $b = $itens[$i]
                $sobre = ([math]::Abs($a[1][0] - $b[1][0]) -lt ($a[2] + $b[2]) / 2) -and ([math]::Abs($a[1][1] - $b[1][1]) -lt ($a[3] + $b[3]) / 2)
                if ($sobre) {
                    if ($b[4]) { $nx = $b[1][0]; $ny = $a[1][1] - $b[3] - 0.004 } else { $nx = $a[1][0] + $b[2] + 0.004; $ny = $b[1][1] }
                    X $b[0] "SetPosition" $nx $ny 0.0 | Out-Null
                    $itens[$i][1] = @($nx, $ny, 0.0); $mov++
                }
            }
        }
        if ($mov -gt 0) { Log "   $mov nota(s) de dobra afastada(s)" "DarkGray" }
    } catch { Log "   (não consegui afastar as notas de dobra: $($_.Exception.Message))" "DarkYellow" }
}


# ---------------------------------------------------------------- anti-sobreposição de textos
# Lê o retângulo real de cada nota (chamadas de furo, notas de dobra, balões) e afasta as que
# encostam em outra nota ou em outra vista. Vale para todos os desenhos.
function AnnOf($n) { try { $a = X $n "GetAnnotation"; if ($a) { return $a } } catch { }; return $n }
function RetNota($n) {
    try { $e = XD (X $n "GetExtent"); if ($e -and $e.Count -ge 5) { return [pscustomobject]@{ x1 = [math]::Min($e[0], $e[3]); y1 = [math]::Min($e[1], $e[4]); x2 = [math]::Max($e[0], $e[3]); y2 = [math]::Max($e[1], $e[4]) } } } catch { }
    # chamada de furo não informa o tamanho: estima pelo texto (≈ 2 mm por caractere x 4,5 mm por linha) a partir da posição
    try {
        $p = XD (X (AnnOf $n) "GetPosition")
        $t = ""; try { $t = [string](X $n "GetText") } catch { }
        $linhas = 3; $larg = 0.058
        if ($t) { $ls = @($t -split "`n"); $linhas = [math]::Max(1, $ls.Count); $larg = [math]::Min(0.09, [math]::Max(0.03, (($ls | Measure-Object -Property Length -Maximum).Maximum) * 0.0019)) }
        return [pscustomobject]@{ x1 = $p[0] - 0.004; y1 = $p[1] - $linhas * 0.0048 - 0.001; x2 = $p[0] + $larg; y2 = $p[1] + 0.001 }
    } catch { }
    return $null
}
function Bate($a, $b, $folga) { return -not ($a.x2 + $folga -le $b.x1 -or $b.x2 + $folga -le $a.x1 -or $a.y2 + $folga -le $b.y1 -or $b.y2 + $folga -le $a.y1) }
function MoverNota($n, $dx, $dy) {
    $an = AnnOf $n; $p = XD (X $an "GetPosition")
    X $an "SetPosition" ($p[0] + $dx) ($p[1] + $dy) 0.0 | Out-Null
}
function TipoNota($n) {
    try { if (X $n "IsBomBalloon") { return "balao" } } catch { }
    $t = ""; try { $t = [string](X $n "GetText") } catch { }
    if ($t -match "(?i)PARA (CIMA|BAIXO)") { return "dobra" }
    if ($t -match "(?i)PASSANTE|MOD-DIAM|Ø|<HOLE|x\s*<") { return "furo" }
    return "outra"
}
function ResolverSobreposicoes($dm, $vistas, [string[]]$tiposMoveis, $extras = @()) {
    $vs = @($vistas | Where-Object { $_ })
    $notas = @()
    foreach ($v in $vs) {
        try { foreach ($n in @(X $v "GetNotes")) { if ($n) { $tp = TipoNota $n; if ($tp -eq "furo" -and $script:chamadas.Count -gt 0) { $tp = "outra" }; $notas += ,@($n, $v, $tp) } } } catch { }
    }
    if ($tiposMoveis -contains "furo") { foreach ($c in $script:chamadas) { $notas += ,@($c[0], $c[1], "furo") } }
    $cont = @{}; foreach ($it in $notas) { $cont[$it[2]] = 1 + [int]$cont[$it[2]] }
    Log ("   [dbg] textos encontrados: " + (($cont.Keys | ForEach-Object { "$_=$($cont[$_])" }) -join ", ")) "DarkGray"
    if ($notas.Count -eq 0) { return }
    $limite = [pscustomobject]@{ x1 = $AreaL - 0.008; y1 = $AreaB - 0.004; x2 = $AreaR + 0.003; y2 = $AreaT + 0.008 }
    $fixos = @($extras | Where-Object { $_ })      # retângulos já ocupados (ex.: lista de materiais)
    $fixosTexto = @()
    $moveis = @()
    foreach ($it in $notas) { if ($tiposMoveis -contains $it[2]) { $moveis += ,$it } else { $r = RetNota $it[0]; if ($r) { $fixos += $r; $fixosTexto += $r } } }
    $moveis = @($moveis | Sort-Object { [array]::IndexOf($tiposMoveis, $_[2]) })   # notas de dobra antes das chamadas de furo
    $outl = @{}; foreach ($v in $vs) { $outl[[string](X $v "GetName2")] = Contorno $v }
    # faixas das cotas totais (acima e à esquerda de cada vista com cota) também são ocupadas
    foreach ($v in $vs) {
        try { $nd = 0; $dd = X $v "GetFirstDisplayDimension5"; while ($dd -and $nd -lt 50) { $nd++; $dd = X $dd "GetNext5" } } catch { $nd = 1 }
        if ($nd -gt 0) {
            $o = Contorno $v
            $fixos += [pscustomobject]@{ x1 = $o.x1; y1 = $o.y2; x2 = $o.x2; y2 = $o.y2 + 0.013 }
            $fixos += [pscustomobject]@{ x1 = $o.x1 - 0.013; y1 = $o.y1; x2 = $o.x1; y2 = $o.y2 }
        }
    }
    $mov = 0
    # passos de deslocamento: para cima/baixo primeiro (balões e notas), depois para os lados
    $passos = @(@(0, 1), @(0, -1), @(1, 0), @(-1, 0), @(1, 1), @(-1, 1), @(1, -1), @(-1, -1))
    foreach ($it in $moveis) {
        $n = $it[0]; $minha = [string](X $it[1] "GetName2")
        $r = RetNota $n; if (-not $r) { Log "   [dbg] sem retângulo para um texto do tipo $($it[2])" "DarkGray"; continue }
        # nota de dobra só desvia de outros textos e anda pouco (tem que ficar junto da linha de dobra)
        $obst = @(); if ($it[2] -eq "dobra") { $obst += $fixosTexto } else { $obst += $fixos }   # sempre lista (1 item só virava objeto solto e o += quebrava)
        $maxDist = if ($it[2] -eq "dobra") { 3 } else { 8 }
        if ($it[2] -ne "dobra") { foreach ($k in $outl.Keys) { $obst += $outl[$k] } }   # chamada de furo e balão também não cobrem a própria vista
        $folga = if ($it[2] -eq "furo") { 0.003 } else { 0.0015 }
        $colide = { param($q) foreach ($o in $obst) { if (Bate $q $o $folga) { return $true } }; return (-not ($q.x1 -ge $limite.x1 -and $q.x2 -le $limite.x2 -and $q.y1 -ge $limite.y1 -and $q.y2 -le $limite.y2)) }
        if (& $colide $r) {
            $w = $r.x2 - $r.x1; $h = $r.y2 - $r.y1
            $achou = $false
            for ($dist = 1; $dist -le $maxDist -and -not $achou; $dist++) {
                foreach ($ps in $passos) {
                    $dx = $ps[0] * $dist * ([math]::Max($w * 0.5, 0.006)); $dy = $ps[1] * $dist * ($h + 0.002)
                    $q = [pscustomobject]@{ x1 = $r.x1 + $dx; y1 = $r.y1 + $dy; x2 = $r.x2 + $dx; y2 = $r.y2 + $dy }
                    if (-not (& $colide $q)) { MoverNota $n $dx $dy; $r = RetNota $n; if (-not $r) { $r = $q }; $mov++; $achou = $true; break }
                }
            }
        }
        $fixos += $r; $fixosTexto += $r
    }
    if ($mov -gt 0) { Log "   $mov texto(s) afastado(s) para não encostar ($($tiposMoveis -join ', '))" "DarkGray" }
}

# ---------------------------------------------------------------- layout peça
function LayoutPeca($dm, $front, $left, $top, $iso, $flat) {
    $m = $script:MargemCotas
    MoverPara $front ($AreaL + $m) ($AreaT - $m)
    $of = Contorno $front
    if ($left) { MoverPara $left ($of.x2 + $Gap) ($AreaT - $m) }
    if ($top) { MoverPara $top ($AreaL + $m) ($of.y1 - $Gap) }
    if ($iso) { $oi = Contorno $iso; MoverPara $iso ($AreaR - $m - $oi.w) ($AreaT - $m) }
    if ($flat) {
        $of = Contorno $front
        $ref = if ($top) { Contorno $top } else { $of }
        $baseX = [math]::Max($ref.x2, $of.x2) + $Gap
        $topoY = if ($top) { $ref.y2 } else { $of.y1 - $Gap }
        if ($left) { $topoY = [math]::Min($topoY, (Contorno $left).y1 - $Gap) }
        $op = Contorno $flat
        if ($iso) { $oi = Contorno $iso; if ($baseX + $op.w -gt $oi.x1) { $topoY = [math]::Min($topoY, $oi.y1 - $Gap) } }
        MoverPara $flat $baseX $topoY
    }
    Rebuild $dm
    $os = @(@($front, $left, $top, $iso, $flat) | Where-Object { $_ } | ForEach-Object { Contorno $_ })
    foreach ($x in $os) { if (-not (DentroDaArea $x $AreaB)) { return $false } }
    for ($i = 0; $i -lt $os.Count; $i++) { for ($j = $i + 1; $j -lt $os.Count; $j++) { if (Sobrepoe $os[$i] $os[$j]) { return $false } } }
    return $true
}

# peça longa: frontal, superior e planificada uma embaixo da outra; lateral à direita da frontal; isométrica embaixo à direita
function LayoutPecaLonga($dm, $front, $left, $top, $iso, $flat) {
    $m = $script:MargemCotas
    MoverPara $front ($AreaL + $m) ($AreaT - $m)
    $of = Contorno $front
    if ($left) { MoverPara $left ($of.x2 + $Gap * 0.6) ($AreaT - $m) }
    $y = $of.y1 - $Gap
    if ($left) { $y = [math]::Min($y, (Contorno $left).y1 - $Gap) }
    if ($top) { MoverPara $top ($AreaL + $m) $y; $y = (Contorno $top).y1 - $Gap }
    if ($flat) { MoverPara $flat ($AreaL + $m) $y; $y = (Contorno $flat).y1 - $Gap }
    if ($iso) { $oi = Contorno $iso; MoverPara $iso ($AreaR - $m - $oi.w) ($AreaB + $m + $oi.h + 0.002) }
    Rebuild $dm
    return (ConfereLayout @($front, $left, $top, $iso, $flat))
}
function ConfereLayout($vistas) {
    $vs = @($vistas | Where-Object { $_ })
    $os = @($vs | ForEach-Object { Contorno $_ })
    for ($i = 0; $i -lt $os.Count; $i++) {
        $x = $os[$i]
        if (-not (DentroDaArea $x $AreaB)) { Log ("   [dbg] {0} fora da área: ({1:N3};{2:N3})-({3:N3};{4:N3})" -f (X $vs[$i] "GetName2"), $x.x1, $x.y1, $x.x2, $x.y2) "DarkGray"; return $false }
    }
    for ($i = 0; $i -lt $os.Count; $i++) { for ($j = $i + 1; $j -lt $os.Count; $j++) { if (Sobrepoe $os[$i] $os[$j]) { Log "   [dbg] $(X $vs[$i] 'GetName2') sobrepõe $(X $vs[$j] 'GetName2')" "DarkGray"; return $false } } }
    return $true
}
# ---------------------------------------------------------------- METALON (tubo retangular/quadrado) - padrão ProEstamp, ex.: 02123721
# vista lateral comprida embaixo (com QUEBRAS entre os furos para aumentar a escala), cota total em cima,
# cotas em cadeia da posição dos furos, altura do furo à esquerda, chamada "14 x Ø9,50 PASSANTE",
# vista de topo do perfil à direita (largura, altura e parede) e isométrica grande em cima
$script:gapQuebra = 0.006
$script:mq = @{ on = $false }
function EhMetalon($desc) { return ([string]$desc -match '(?i)METAL[OÃ][NM]') }
function ApagarVista($dm, $v) { try { Selecionar $dm $v | Out-Null; X $dm "EditDelete" | Out-Null } catch { } }
# limites da peça no plano da vista (caixa do modelo girada): [[umin,umax],[vmin,vmax]]
function LimitesNaVista($v) {
    $a = DadosXf $v; $cb = $script:caixaPeca; $lim = @(@(1e9, -1e9), @(1e9, -1e9))
    foreach ($cx in $cb[0], $cb[3]) { foreach ($cy in $cb[1], $cb[4]) { foreach ($cz in $cb[2], $cb[5]) {
        $r = Rot $a @($cx, $cy, $cz)
        for ($i = 0; $i -lt 2; $i++) { $lim[$i][0] = [math]::Min($lim[$i][0], $r[$i]); $lim[$i][1] = [math]::Max($lim[$i][1], $r[$i]) }
    } } }
    return ,$lim
}
function DesfazerQuebras($dm, $v) {
    try { Selecionar $dm $v | Out-Null; X $dm "UnBreakView" | Out-Null } catch { }
    $bls = $null; try { $bls = X $v "GetBreakLines" } catch { }
    foreach ($bl in @($bls)) {
        if (-not $bl) { continue }
        try { X $dm "ClearSelection2" $true | Out-Null } catch { }
        $sel = $false
        try { $sel = X $bl "Select" $false } catch { }
        if (-not $sel) { try { $sel = X $bl "Select2" $false 0 } catch { } }
        try { X $dm "EditDelete" | Out-Null } catch { }
    }
    Rebuild $dm
}
# insere as quebras (pares u1,u2 no eixo horizontal da vista, em metros do modelo).
# Cria as linhas (InsertBreak2/InsertBreak; se não der, InsertBreakVertical na vista selecionada), depois
# acerta a posição com IBreakLine.SetPosition testando o sistema de coordenadas e confere pela largura da vista.
function LinhasQuebra($v) {
    $r = $null; try { $r = X $v "GetBreakLines" } catch { }
    $res = @(); foreach ($x in @($r)) { if ($x) { $res += ,$x } }
    return ,$res
}
function PosConv($conv, $u, $esc, $xc, $uc, $px) {
    switch ($conv) {
        0 { return $u }
        1 { return $u * $esc }
        2 { return $xc + ($u - $uc) * $esc }
        3 { return $xc + ($u - $uc) * $esc - $px }
        4 { return ($u - $uc) }
        5 { return ($u - $uc) * $esc }
    }
}
function QuebrarVista($dm, $v, $cortes, $lim) {
    $nb = [int]($cortes.Count / 2)
    if ($nb -lt 1) { return $false }
    $ori = K "swBreakLineOrientation_e" @("swBreakLineVertical") 0
    $est = K "swBreakLineStyle_e" @("swBreakLine_ZigZag") 1
    $pg = K "swUserPreferenceDoubleValue_e" @("swDetailingBreakLineGap") -1
    if ($pg -ge 0) { try { X (XG $dm "Extension") "SetUserPreferenceDouble" $pg 0 $script:gapQuebra | Out-Null } catch { } }
    $esc = 1.0; try { $esc = [double](XG $v "ScaleDecimal") } catch { }
    $o = Contorno $v; $p = PosVista $v
    $uc = ($lim[0][0] + $lim[0][1]) / 2; $xc = ($o.x1 + $o.x2) / 2
    $w0 = $o.w
    $rem = 0.0; for ($i = 0; $i -lt $nb; $i++) { $rem += $cortes[2 * $i + 1] - $cortes[2 * $i] }
    $nomes = @("modelo", "modelo x escala", "folha", "folha relativa à vista", "modelo a partir do centro", "modelo x escala a partir do centro")
    # o InsertBreak devolve vazio quando a posição cai fora da vista: o sistema certo é o que aceita TODAS as quebras
    foreach ($cv in 5, 4, 1, 0, 2, 3) {
        $criadas = 0
        for ($i = 0; $i -lt $nb; $i++) {
            $p1 = PosConv $cv ([double]$cortes[2 * $i]) $esc $xc $uc $p[0]; $p2 = PosConv $cv ([double]$cortes[2 * $i + 1]) $esc $xc $uc $p[0]
            $bl = $null; try { $bl = X $v "InsertBreak" ([int]$ori) ([double]$p1) ([double]$p2) ([int]$est) } catch { }
            if ($bl) { $criadas++ }
        }
        Log "   [dbg] quebras ($($nomes[$cv])): $criadas de $nb aceitas" "DarkGray"
        if ($criadas -lt $nb) { if ($criadas -gt 0) { DesfazerQuebras $dm $v }; continue }
        Selecionar $dm $v | Out-Null
        try { X $dm "BreakView" | Out-Null } catch { Log "   [dbg] BreakView: $($_.Exception.Message)" "DarkGray" }
        Rebuild $dm
        $w1 = (Contorno $v).w
        $nl = (LinhasQuebra $v).Count
        Log ("   [dbg] quebras ({0}): {1} linha(s) na vista; contorno {2:N1} -> {3:N1} mm (esperado ~{4:N1})" -f $nomes[$cv], $nl, ($w0 * 1000), ($w1 * 1000), (($w0 - $esc * $rem + $nb * $script:gapQuebra) * 1000)) "DarkGray"
        $script:mq = @{ on = $true; nb = $nb; rem = $rem; L = ($lim[0][1] - $lim[0][0]); alt = ($lim[1][1] - $lim[1][0]); encolhe = ($w1 -lt $w0 - 0.3 * $esc * $rem) }
        if (-not $script:mq.encolhe) { Log "   [dbg] o contorno da vista não mudou com a quebra; uso a largura calculada" "DarkGray" }
        Log "   Vista principal quebrada em $nb ponto(s) (padrão de metalon)" "DarkGray"
        return $true
    }
    Log "   Aviso: o SolidWorks não aceitou as quebras do metalon; vista inteira (escala menor)." "Yellow"
    return $false
}
# contorno da principal do metalon: se o SolidWorks não atualizar o contorno depois da quebra, calcula a largura (centrada)
function ContornoM($v) {
    $o = Contorno $v
    if (-not $script:mq.on -or $script:mq.encolhe) { return $o }
    $esc = 1.0; try { $esc = [double](XG $v "ScaleDecimal") } catch { }
    $pad = [math]::Max(0.0, ($o.h - $script:mq.alt * $esc) / 2)
    if ($o.w -lt 0.85 * (2 * $pad + $script:mq.L * $esc)) { return $o }   # o SolidWorks já devolve o contorno quebrado
    $wb = 2 * $pad + ($script:mq.L - $script:mq.rem) * $esc + $script:mq.nb * $script:gapQuebra
    $xc = ($o.x1 + $o.x2) / 2
    return [pscustomobject]@{ x1 = $xc - $wb / 2; y1 = $o.y1; x2 = $xc + $wb / 2; y2 = $o.y2; w = $wb; h = $o.h }
}
# onde cortar: nos vãos grandes entre furos (e no meio, se não tiver furo), deixando um pedaço de cada lado
function CortesMetalon($us, $uMin, $uMax, $alt) {
    # regra ProEstamp: furos aos pares ao longo do metalon; uma quebra a cada dois furos
    # (entre o 2º e o 3º, entre o 4º e o 5º...), deixando um pedaço do tubo de cada lado
    $cortes = @()
    $keep = [math]::Max(0.015, 0.4 * $alt)
    if ($us.Count -eq 0) {
        $keep = [math]::Max(0.080, 1.5 * $alt)
        if (($uMax - $uMin) -gt 2 * $keep + $alt) { $cortes = @(($uMin + $keep), ($uMax - $keep)) }
        return ,$cortes
    }
    for ($i = 1; $i + 1 -lt $us.Count; $i += 2) {
        $a = [math]::Min([double]$us[$i], [double]$us[$i + 1]); $b = [math]::Max([double]$us[$i], [double]$us[$i + 1])
        $k = $keep
        if (($b - $a - 2 * $k) -lt 0.3 * $alt) { $k = ($b - $a - 0.3 * $alt) / 2 }
        if ($k -lt 0.008) { continue }   # furos muito perto: não cabe quebra
        $cortes += ,@(($a + $k), ($b - $k))
    }
    # pares em ordem crescente, achatados (u1,u2,u1,u2...)
    $res = @(); foreach ($c in ($cortes | Sort-Object { $_[0] })) { $res += $c[0]; $res += $c[1] }
    return ,$res
}
# posição na folha (x) de um ponto u do modelo, descontando os pedaços removidos pelas quebras
function XFolhaQuebrada($u, $cortes, $X0, $esc, $uMin, $g) {
    $x = $X0 + ($u - $uMin) * $esc
    for ($i = 0; $i -lt $cortes.Count / 2; $i++) {
        $c1 = $cortes[2 * $i]; $c2 = $cortes[2 * $i + 1]
        if ($u -ge $c2) { $x -= ($c2 - $c1) * $esc; $x += $g }
    }
    return $x
}
function LayoutMetalon($dm, $front, $end, $dx) {
    # MoverPara usa o contorno do SolidWorks; desloca pela diferença para o contorno calculado
    $oc = ContornoM $front; $or = Contorno $front
    MoverPara $front ($AreaL + 0.016 + $dx + ($or.x1 - $oc.x1)) ($AreaB + 0.030 + $or.h)
    Rebuild $dm
    $of = ContornoM $front
    if ($end) {
        $oe = Contorno $end
        MoverPara $end ($of.x2 + 0.038) ((($of.y1 + $of.y2) / 2) + $oe.h / 2)
        Rebuild $dm
        $oe = Contorno $end
        $dir = $oe.x2
    } else { $dir = $of.x2 }
    return ($dir -le $AreaR - 0.008 -and $of.y2 + $script:alturaCotasMetalon + 0.010 -le $AreaT - 0.004)
}
# em que lado (min/max) do eixo k da peça estão os furos: conta as faces cilíndricas pequenas com eixo k
function LadosFuros($peca, [int]$k) {
    $cb = $script:caixaPeca; $mid = ($cb[$k] + $cb[$k + 3]) / 2
    $nMin = 0; $nMax = 0
    $bodies = $null; try { $bodies = X $peca "GetBodies2" 0 $true } catch { }
    foreach ($b in @($bodies)) {
        if (-not $b) { continue }
        $f = $null; try { $f = X $b "GetFirstFace" } catch { }
        $guarda = 0
        while ($f -and $guarda -lt 5000) {
            $guarda++
            try {
                $sf = X $f "GetSurface"
                if (X $sf "IsCylinder") {
                    $cp = XD (XG $sf "CylinderParams")
                    if ([math]::Abs($cp[3 + $k]) -gt 0.99 -and $cp[6] -lt 0.02) {
                        $bx = XD (X $f "GetBox"); $t = ($bx[$k] + $bx[$k + 3]) / 2
                        if ($t -gt $mid) { $nMax++ } else { $nMin++ }
                    }
                }
            } catch { }
            try { $f = X $f "GetNextFace" } catch { $f = $null }
        }
    }
    return ,@($nMin, $nMax)
}
# cria na peça uma vista nomeada isométrica olhando para o lado dos furos; devolve o nome (ou $null = usar a isométrica padrão)
function IsoDosFuros($peca, $dm, [int]$k) {
    $lados = LadosFuros $peca $k
    $eixos = @("X", "Y", "Z")
    Log "   [dbg] furos no eixo $($eixos[$k]): $($lados[0]) face(s) do lado negativo, $($lados[1]) do lado positivo" "DarkGray"
    if ($lados[1] -gt 0 -or $lados[0] -eq 0) { return $null }   # a isométrica padrão (+X +Y +Z) já mostra os furos
    $d = @(1.0, 1.0, 1.0); $d[$k] = -1.0
    $tituloDrw = Titulo $dm
    try {
        try { X $sw "ActivateDoc" (Titulo $peca) | Out-Null } catch { }
        $mv = XG $peca "ActiveView"
        if (-not $mv) { Log "   (peça sem janela: isométrica padrão)" "DarkGray"; return $null }
        X $peca "ShowNamedView2" "*Isometric" 7 | Out-Null
        $A = XD (XG (XG $mv "Orientation3") "ArrayData")
        # matriz de orientação para a direção d (z da tela = d; "para cima" = Y do modelo)
        function MatrizVista([double[]]$dir) {
            $l = [math]::Sqrt($dir[0] * $dir[0] + $dir[1] * $dir[1] + $dir[2] * $dir[2]); $z = @(($dir[0] / $l), ($dir[1] / $l), ($dir[2] / $l))
            $up = @(0.0, 1.0, 0.0); if ([math]::Abs($z[1]) -gt 0.99) { $up = @(0.0, 0.0, -1.0) }
            $x = @(($up[1] * $z[2] - $up[2] * $z[1]), ($up[2] * $z[0] - $up[0] * $z[2]), ($up[0] * $z[1] - $up[1] * $z[0]))
            $lx = [math]::Sqrt($x[0] * $x[0] + $x[1] * $x[1] + $x[2] * $x[2]); $x = @(($x[0] / $lx), ($x[1] / $lx), ($x[2] / $lx))
            $y = @(($z[1] * $x[2] - $z[2] * $x[1]), ($z[2] * $x[0] - $z[0] * $x[2]), ($z[0] * $x[1] - $z[1] * $x[0]))
            return ,@($x, $y, $z)
        }
        $m0 = MatrizVista @(1.0, 1.0, 1.0)
        $col = @($m0[0][0], $m0[1][0], $m0[2][0], $m0[0][1], $m0[1][1], $m0[2][1], $m0[0][2], $m0[1][2], $m0[2][2])
        $lin = @($m0[0][0], $m0[0][1], $m0[0][2], $m0[1][0], $m0[1][1], $m0[1][2], $m0[2][0], $m0[2][1], $m0[2][2])
        $eC = 0.0; $eL = 0.0; for ($i = 0; $i -lt 9; $i++) { $eC += [math]::Abs($A[$i] - $col[$i]); $eL += [math]::Abs($A[$i] - $lin[$i]) }
        Log ("   [dbg] orientação da isométrica padrão confere: colunas {0:N3} / linhas {1:N3}" -f $eC, $eL) "DarkGray"
        if ([math]::Min($eC, $eL) -gt 0.05) { Log "   (orientação da isométrica não reconhecida: isométrica padrão)" "DarkGray"; return $null }
        $m = MatrizVista $d
        $arr = if ($eC -le $eL) { @($m[0][0], $m[1][0], $m[2][0], $m[0][1], $m[1][1], $m[2][1], $m[0][2], $m[1][2], $m[2][2]) } else { @($m[0][0], $m[0][1], $m[0][2], $m[1][0], $m[1][1], $m[1][2], $m[2][0], $m[2][1], $m[2][2]) }
        $arr += @($A[9], $A[10], $A[11], $A[12], $A[13], $A[14], $A[15])
        $mu = X $sw "GetMathUtility"
        $tr = X $mu "CreateTransform" ([double[]]$arr)
        XS $mv "Orientation3" $tr
        try { X $peca "GraphicsRedraw2" | Out-Null } catch { }
        $B = XD (XG (XG $mv "Orientation3") "ArrayData")
        $eB = 0.0; for ($i = 0; $i -lt 9; $i++) { $eB += [math]::Abs($B[$i] - $arr[$i]) }
        if ($eB -gt 0.05) { Log "   (não consegui girar a vista da peça: isométrica padrão)" "DarkGray"; return $null }
        $nome = "ISO FUROS"
        try { X $peca "DeleteNamedView" $nome | Out-Null } catch { }
        X $peca "NameView" $nome | Out-Null
        Log "   Isométrica virada para o lado dos furos (eixo $($eixos[$k]) negativo)" "DarkGray"
        return $nome
    } finally { try { X $sw "ActivateDoc" $tituloDrw | Out-Null } catch { } }
}
function DetalharMetalon($caminho, $peca, $X, $Y, $Z, $desc) {
    $mx = [math]::Max($X, [math]::Max($Y, $Z))
    # vistas que mostram o comprimento (olham perpendicular ao eixo comprido)
    # as 4 faces compridas (os furos podem estar só de um lado do tubo: a vista do lado oposto não mostra nada)
    if ($X -ge $Y -and $X -ge $Z) { $cands = @(@("*Frontal", "*Front"), @("*Superior", "*Top"), @("*Posterior", "*Back"), @("*Inferior", "*Bottom")) }
    elseif ($Y -ge $Z) { $cands = @(@("*Frontal", "*Front"), @("*Esquerda", "*Left"), @("*Posterior", "*Back"), @("*Direita", "*Right")) }
    else { $cands = @(@("*Superior", "*Top"), @("*Esquerda", "*Left"), @("*Inferior", "*Bottom"), @("*Direita", "*Right")) }
    # espessura da parede pela descrição quando não tem "ESP": 30X70X2MM X 3388MM (3º número pequeno = parede)
    if ($script:espessura -le 0) {
        $mP = [regex]::Match([string]$desc, "(?i)(\d+(?:[\.,]\d+)?)\s*X\s*(\d+(?:[\.,]\d+)?)\s*X\s*(\d+(?:[\.,]\d+)?)")
        if ($mP.Success) { $t3 = [double]($mP.Groups[3].Value.Replace(",", ".")); if ($t3 -gt 0 -and $t3 -lt 12) { $script:espessura = $t3 / 1000; Log ("   Parede do metalon pela descrição: {0} mm" -f $t3) "DarkGray" } }
    }
    $dm = NovoDesenho
    $i0 = EscalaInicial ($mx * 1.2) ($mx * 0.5)
    DefinirEscala $dm $Escalas[$i0][0] $Escalas[$i0][1]
    # a principal é a face onde os furos aparecem de frente (empate: a que mostra o lado maior do perfil)
    $front = $null; $nMelhor = -1; $hMelhor = 0
    foreach ($nm in $cands) {
        $v = VistaModelo $dm $caminho $nm 0.15 0.12
        if (-not $v) { continue }
        Deitar $dm $v
        $script:xfCache = @{}; $script:xfModo = @{}
        Rebuild $dm
        $nf = 0; try { $fv = FurosDaVista $v; $nf = $fv.Count } catch { }
        $lim = LimitesNaVista $v; $h = $lim[1][1] - $lim[1][0]
        Log ("   [dbg] metalon: vista {0} mostra {1} furo(s), perfil {2:N1} mm" -f $nm[0], $nf, ($h * 1000)) "DarkGray"
        if ($nf -gt $nMelhor -or ($nf -eq $nMelhor -and $h -gt $hMelhor + 0.0005)) {
            if ($front) { ApagarVista $dm $front }
            $front = $v; $nMelhor = $nf; $hMelhor = $h
            $script:eixoFuros = if ($nm[0] -like "*Frontal" -or $nm[0] -like "*Posterior") { 2 } elseif ($nm[0] -like "*Superior" -or $nm[0] -like "*Inferior") { 1 } else { 0 }
        } else { ApagarVista $dm $v }
    }
    if (-not $front) { throw "não consegui criar a vista principal do metalon" }
    if ($nMelhor -le 0) {
        # nenhuma vista mostrou furo: diz no log se o 3D tem furos (faces cilíndricas pequenas) e em que eixo
        $tx = @(); foreach ($k in 0, 1, 2) { try { $l = LadosFuros $peca $k; $tx += ("{0}: {1}/{2}" -f @("X", "Y", "Z")[$k], $l[0], $l[1]) } catch { } }
        Log ("   Aviso: nenhuma vista mostrou furos. Faces de furo no 3D por eixo (lado -/+): " + ($tx -join "  ")) "Yellow"
    }
    $script:xfCache = @{}; $script:xfModo = @{}
    $script:mq = @{ on = $false }
    $end = $null
    try { Selecionar $dm $front | Out-Null; $end = X $dm "CreateUnfoldedViewAt3" 0.27 0.12 0.0 $false } catch { Log "   (vista do perfil falhou: $($_.Exception.Message))" "DarkYellow" }
    # isométrica olhando para a face que tem os furos (se os furos estão só do lado "de trás", inverte o lado da vista)
    $iso = $null
    $nomeIso = $null
    if ($nMelhor -gt 0) { try { $nomeIso = IsoDosFuros $peca $dm ([int]$script:eixoFuros) } catch { Log "   (isométrica dos furos: $($_.Exception.Message))" "DarkYellow" } }
    if ($nomeIso) { $iso = VistaModelo $dm $caminho @($nomeIso) 0.15 0.17 }
    if (-not $iso) { $iso = VistaModelo $dm $caminho @("*Isométrica", "*Isometric") 0.15 0.17 }
    Modo $front $DispHidden $true
    if ($end) { Modo $end $DispHidden $true }
    if ($iso) { Modo $iso $DispShaded $true }
    Rebuild $dm
    Log ("   Metalon: vista lateral comprida + perfil" + $(if ($end) { " ok" } else { " FALHOU" }) + " + isométrica" + $(if ($iso) { " ok" } else { " FALHOU" }))

    # furos e quebras
    $lim = LimitesNaVista $front
    $uMin = $lim[0][0]; $uMax = $lim[0][1]; $alt = $lim[1][1] - $lim[1][0]
    $furos = FurosDaVista $front
    $us = @(); foreach ($h in ($furos | Sort-Object { $_[2][0] })) { if (-not ($us | Where-Object { [math]::Abs($_ - $h[2][0]) -lt 0.0002 })) { $us += $h[2][0] } }
    # ponta de referência: a que fica com o 1º furo mais perto de 23 mm (padrão ProEstamp); os pares de furos contam a partir dela
    $script:metalonDir = $false
    if ($us.Count -gt 0) { $script:metalonDir = ([math]::Abs(($uMax - $us[$us.Count - 1]) - 0.023) -lt [math]::Abs(($us[0] - $uMin) - 0.023)) }
    $usRef = if ($script:metalonDir) { @($us | Sort-Object -Descending) } else { $us }
    $cortes = CortesMetalon $usRef $uMin $uMax $alt
    # cotas dos furos empilhadas acima da vista (todas a partir da mesma ponta) + comprimento total no topo
    # cotas dos furos todas na mesma linha; acima delas o comprimento total (e, se precisar, a distância dentro de um par diferente)
    $script:passoCotasMetalon = 0.0075
    $script:alturaCotasMetalon = $DistCota + 2 * $script:passoCotasMetalon + 0.006
    Log ("   [dbg] metalon: {0} furo(s) em {1} posição(ões) ao longo do comprimento; {2} quebra(s) planejada(s)" -f $furos.Count, $us.Count, [int]($cortes.Count / 2)) "DarkGray"
    $quebrada = $false
    if ($cortes.Count -ge 2) { $quebrada = QuebrarVista $dm $front $cortes $lim }
    if (-not $quebrada) { $cortes = @() }
    $rem = 0.0; for ($i = 0; $i -lt $cortes.Count / 2; $i++) { $rem += $cortes[2 * $i + 1] - $cortes[2 * $i] }

    # escala: a maior em que a principal (quebrada) + o perfil cabem na largura; a isométrica ocupa o espaço de cima
    $sAtual = [double]$Escalas[$i0][0] / $Escalas[$i0][1]
    try { $sAtual = [double](XG $front "ScaleDecimal") } catch { }
    # largura necessária = folgas + comprimento que sobra depois das quebras x escala + vãos das quebras + perfil
    $oF = Contorno $front; $padF = [math]::Max(0.0, ($oF.h - $alt * $sAtual) / 2)
    $nbq = [int]($cortes.Count / 2); $remq = 0.0; for ($i = 0; $i -lt $nbq; $i++) { $remq += $cortes[2 * $i + 1] - $cortes[2 * $i] }
    $profW = 0.0; $padE = 0.0
    if ($end) { $oE = Contorno $end; $profW = [math]::Min($lim[1][1] - $lim[1][0], $oE.w / $sAtual); $padE = [math]::Max(0.0, ($oE.h - $alt * $sAtual) / 2); $profW = [math]::Max(0.0, ($oE.w - 2 * $padE) / $sAtual) }
    $livre = ($AreaR - 0.008) - ($AreaL + 0.016) - 2 * $padF - $nbq * $script:gapQuebra - $(if ($end) { 2 * $padE + 0.038 } else { 0 })
    $sEst = $livre / [math]::Max(($uMax - $uMin) - $remq + $profW, 0.001)
    Log ("   [dbg] metalon: comprimento visível {0:N0} mm; escala estimada 1:{1:N1}" -f ((($uMax - $uMin) - $remq) * 1000), (1 / [math]::Max($sEst, 1e-6))) "DarkGray"
    $iE = $Escalas.Count - 1
    for ($i = 0; $i -lt $Escalas.Count; $i++) { if (($Escalas[$i][0] / $Escalas[$i][1]) -le $sEst * 1.02) { $iE = $i; break } }
    $ok = $false
    for ($i = $iE; $i -lt $Escalas.Count -and -not $ok; $i++) {
        DefinirEscala $dm $Escalas[$i][0] $Escalas[$i][1]
        if (LayoutMetalon $dm $front $end 0) { $ok = $true; $sAtual = [double]$Escalas[$i][0] / $Escalas[$i][1]; Log "   Escala $($Escalas[$i][0]):$($Escalas[$i][1]) (metalon$(if ($quebrada) { ' com quebras' }))" }
    }
    if (-not $ok) { Log "   Aviso: as vistas do metalon não couberam perfeitamente; confira a disposição." "Yellow" }
    # centraliza o conjunto principal + perfil na largura
    $of = ContornoM $front; $dirX = if ($end) { (Contorno $end).x2 } else { $of.x2 }
    $sobra = ($AreaR - 0.008) - $dirX
    if ($sobra -gt 0.004) { LayoutMetalon $dm $front $end ($sobra / 2) | Out-Null }
    $cr = Contorno $front; $cm = ContornoM $front
    Log ("   [dbg] principal: contorno SolidWorks x {0:N1}..{1:N1} mm; calculado {2:N1}..{3:N1} mm" -f ($cr.x1 * 1000), ($cr.x2 * 1000), ($cm.x1 * 1000), ($cm.x2 * 1000)) "DarkGray"

    # isométrica: o maior possível no espaço acima das cotas
    if ($iso) {
        try {
            $of = Contorno $front; $topo = $of.y2
            if ($end) { $topo = [math]::Max($topo, (Contorno $end).y2) }
            $y1 = (Contorno $front).y2 + $script:alturaCotasMetalon + 0.006; if ($end) { $y1 = [math]::Max($y1, (Contorno $end).y2 + 0.020) }; $y2 = $AreaT - 0.004
            $wD = ($AreaR - $AreaL) - 0.020; $hD = [math]::Max($y2 - $y1, 0.025)
            try { XS $iso "UseSheetScale" $false } catch { try { XS $iso "UseSheetScale" 0 } catch { } }
            $si = $sAtual * 0.5; try { XS $iso "ScaleDecimal" $si } catch { }
            Rebuild $dm
            $oi = Contorno $iso
            $f = [math]::Min($wD / [math]::Max($oi.w, 0.001), $hD / [math]::Max($oi.h, 0.001)) * 0.95
            $si = [math]::Min($si * $f, $sAtual)
            XS $iso "ScaleDecimal" $si; Rebuild $dm
            $oi = Contorno $iso
            MoverPara $iso ((($AreaL + $AreaR) / 2) - $oi.w / 2) $y2
            Rebuild $dm
        } catch { Log "   (isométrica do metalon: $($_.Exception.Message))" "DarkYellow" }
    }
    $script:isoAtual = $iso

    if ($InserirCotas) {
        $tgl = K "swUserPreferenceToggle_e" @("swInputDimValOnCreate") 10
        $antes = $null
        try { $antes = X $sw "GetUserPreferenceToggle" $tgl; X $sw "SetUserPreferenceToggle" $tgl $false | Out-Null } catch { }
        try { CotasMetalon $dm $front $end $cortes $quebrada } catch { Log "   Aviso: cotas do metalon falharam ($($_.Exception.Message))" "Yellow" }
        finally { if ($null -ne $antes) { try { X $sw "SetUserPreferenceToggle" $tgl ([bool]$antes) | Out-Null } catch { } } }
    }
    return $dm
}
function CentroTexto($dd) {
    if (-not $dd) { return }
    try { XS $dd "CenterText" $true } catch { }
}
# põe o texto de cada cota no meio das suas linhas de chamada e todas na mesma altura.
# Os pontos medidos vêm da própria cota (IDimension.ReferencePoints, já na folha e já considerando as quebras).
function PontosCota($dd) {
    try {
        $dim = X $dd "GetDimension2" 0
        $rp = XG $dim "ReferencePoints"
        $res = @()
        foreach ($mp in @($rp)) { if ($mp) { $res += ,([double[]](XD (XG $mp "ArrayData"))) } }
        return ,$res
    } catch { return ,@() }
}
function AlinharCotas($dm, $linha, $y, [bool]$pontaDireita) {
    $ok = 0; $dbg = $true
    foreach ($it in $linha) {
        $dd = $it[0]; $daPonta = [bool]$it[1]
        # posição na folha dos dois pontos medidos, calculada com as quebras (o contorno da vista já vem quebrado)
        $xa = [double]$it[2]; $xb = [double]$it[3]
        if ($dbg) { Log ("   [dbg] 1ª cota: pontos em x = {0:N1} e {1:N1} mm" -f ($xa * 1000), ($xb * 1000)) "DarkGray"; $dbg = $false }
        $x = ($xa + $xb) / 2
        $vao = [math]::Abs($xb - $xa)
        # cota curta (ex.: 23 da ponta): texto do lado de fora, na direção da ponta
        if ($vao -lt 0.009 -and $daPonta) {
            $ext = if ($pontaDireita) { [math]::Max($xa, $xb) + 0.006 } else { [math]::Min($xa, $xb) - 0.006 }
            $x = $ext
        }
        try { $an = X $dd "GetAnnotation"; X $an "SetPosition" ([double]$x) ([double]$y) 0.0 | Out-Null; $ok++ } catch { }
    }
    Log "   Cotas dos furos alinhadas/centralizadas: $ok de $($linha.Count)" "DarkGray"
}
function CotasMetalon($dm, $front, $end, $cortes, $quebrada) {
    $script:xfCache = @{}; $script:xfModo = @{}
    $a = DadosXf $front
    $lim = LimitesNaVista $front
    $uMin = $lim[0][0]; $uMax = $lim[0][1]; $vMin = $lim[1][0]; $vMax = $lim[1][1]
    $esc = [double](XG $front "ScaleDecimal")
    $o = ContornoM $front
    # folga do contorno (igual nos 4 lados) e tamanho do vão de cada quebra, na folha
    $pad = [math]::Max(0.0, ($o.h - ($vMax - $vMin) * $esc) / 2)
    $nb = [int]($cortes.Count / 2); $rem = 0.0; for ($i = 0; $i -lt $nb; $i++) { $rem += $cortes[2 * $i + 1] - $cortes[2 * $i] }
    $g = 0.0; if ($nb -gt 0) { $g = [math]::Max(0.0, ($o.w - 2 * $pad - (($uMax - $uMin) - $rem) * $esc) / $nb) }
    if ($nb -gt 0 -and ($g -le 0 -or $g -gt 0.03)) { $g = $script:gapQuebra }
    $X0 = $o.x1 + $pad
    $topoPeca = $o.y2 - $pad; $esqPeca = $o.x1 + $pad
    # vértices (cantos das pontas do tubo)
    $pts = @()
    foreach ($vx in (Entidades $front "swViewEntityType_Vertex" 3)) { try { $pm = [double[]](XD (X $vx "GetPoint")); $pts += ,@($vx, (Rot $a $pm)) } catch { } }
    $n = 0; $tol = 0.0003
    if ($pts.Count -ge 2) {
        $minU = ($pts | ForEach-Object { $_[1][0] } | Measure-Object -Minimum).Minimum
        $maxU = ($pts | ForEach-Object { $_[1][0] } | Measure-Object -Maximum).Maximum
        $esqAlto = @($pts | Where-Object { $_[1][0] -le $minU + $tol } | Sort-Object { $_[1][1] })[-1]
        $esqBaixo = @($pts | Where-Object { $_[1][0] -le $minU + $tol } | Sort-Object { $_[1][1] })[0]
        $dirAlto = @($pts | Where-Object { $_[1][0] -ge $maxU - $tol } | Sort-Object { $_[1][1] })[-1]
        $furos = FurosDaVista $front
        $pos = @()
        foreach ($h in ($furos | Sort-Object { $_[2][0] })) { if (-not ($pos | Where-Object { [math]::Abs($_[2][0] - $h[2][0]) -lt 0.0002 })) { $pos += ,$h } }
        $passo = [double]$script:passoCotasMetalon; if ($passo -le 0) { $passo = 0.0075 }
        $usaDir = [bool]$script:metalonDir
        if ($pos.Count -gt 0) { Log ("   [dbg] metalon: 1º furo a {0:N1} mm da ponta esquerda e {1:N1} mm da direita; referência = ponta {2}" -f (($pos[0][2][0] - $minU) * 1000), (($maxU - $pos[$pos.Count - 1][2][0]) * 1000), $(if ($usaDir) { "direita" } else { "esquerda" })) "DarkGray" }
        $refE = if ($usaDir) { $dirAlto[0] } else { $esqAlto[0] }
        $refU = if ($usaDir) { $maxU } else { $minU }
        $ordem = if ($usaDir) { @($pos | Sort-Object { -$_[2][0] }) } else { @($pos) }
        # padrão ProEstamp (gabarito de furação 250/500/1000): ponta -> 1º furo, 1º -> 2º (o par),
        # e depois do 2º furo de um par ao 2º furo do par seguinte; tudo numa linha só
        $alvos = @()
        if ($ordem.Count -ge 1) { $alvos += 0 }
        if ($ordem.Count -ge 2) { $alvos += 1 }
        for ($t = 3; $t -lt $ordem.Count; $t += 2) { $alvos += $t }
        if ($ordem.Count -gt 2 -and ($alvos -notcontains ($ordem.Count - 1))) { $alvos += ($ordem.Count - 1) }
        $yLinha = $topoPeca + $DistCota
        $linha = @()
        $nc = 0; $antE = $refE; $antU = $refU
        foreach ($t in $alvos) {
            $h = $ordem[$t]
            X $dm "ClearSelection2" $true | Out-Null
            SelecionarEntidade $dm $front $antE $false | Out-Null; SelecionarEntidade $dm $front $h[0] $true | Out-Null
            if ((QtdSelecionados $dm) -eq 2) {
                $xa = XFolhaQuebrada $antU $cortes $X0 $esc $uMin $g; $xb = XFolhaQuebrada $h[2][0] $cortes $X0 $esc $uMin $g
                try { $dd = X $dm "AddHorizontalDimension2" ([double](($xa + $xb) / 2)) ([double]$yLinha) 0.0; if ($dd) { $n++; $nc++; CentroTexto $dd; $linha += ,@($dd, ($nc -eq 1), $xa, $xb) } } catch { }
            }
            $antE = $h[0]; $antU = $h[2][0]
        }
        AlinharCotas $dm $linha $yLinha $usaDir
        # par com distância diferente do 1º par: cota a distância dentro dele numa 2ª linha
        $nPar = 0; $yPar = $yLinha + $passo
        if ($ordem.Count -ge 2) {
            $d0 = [math]::Abs($ordem[1][2][0] - $ordem[0][2][0])
            for ($t = 2; $t + 1 -lt $ordem.Count; $t += 2) {
                $dk = [math]::Abs($ordem[$t + 1][2][0] - $ordem[$t][2][0])
                if ([math]::Abs($dk - $d0) -lt 0.0003) { continue }
                X $dm "ClearSelection2" $true | Out-Null
                SelecionarEntidade $dm $front $ordem[$t][0] $false | Out-Null; SelecionarEntidade $dm $front $ordem[$t + 1][0] $true | Out-Null
                if ((QtdSelecionados $dm) -ne 2) { continue }
                $xa = XFolhaQuebrada $ordem[$t][2][0] $cortes $X0 $esc $uMin $g; $xb = XFolhaQuebrada $ordem[$t + 1][2][0] $cortes $X0 $esc $uMin $g
                try { $dd = X $dm "AddHorizontalDimension2" ([double](($xa + $xb) / 2)) ([double]$yPar) 0.0; if ($dd) { $n++; $nPar++; CentroTexto $dd } } catch { }
            }
        }
        # comprimento total acima
        $yTot = $yLinha + $(if ($nc -gt 0) { $passo } else { 0 }) + $(if ($nPar -gt 0) { $passo } else { 0 })
        X $dm "ClearSelection2" $true | Out-Null
        SelecionarEntidade $dm $front $esqAlto[0] $false | Out-Null; SelecionarEntidade $dm $front $dirAlto[0] $true | Out-Null
        if ((QtdSelecionados $dm) -eq 2) { try { $dd = X $dm "AddHorizontalDimension2" ([double](($o.x1 + $o.x2) / 2)) ([double]$yTot) 0.0; if ($dd) { $n++; CentroTexto $dd } } catch { } }
        # altura do(s) furo(s): na ponta de referência, a partir da aresta (de baixo ou de cima) mais perto do furo
        $dirBaixo = @($pts | Where-Object { $_[1][0] -ge $maxU - $tol } | Sort-Object { $_[1][1] })[0]
        $xPonta = if ($usaDir) { (XFolhaQuebrada $maxU $cortes $X0 $esc $uMin $g) } else { $esqPeca }
        $vs = @()
        foreach ($h in ($furos | Sort-Object { $_[2][1] })) { if (-not ($vs | Where-Object { [math]::Abs($_[2][1] - $h[2][1]) -lt 0.0002 })) { $vs += ,$h } }
        $k = 0
        foreach ($h in $vs) {
            X $dm "ClearSelection2" $true | Out-Null
            $deBaixo = (($h[2][1] - $vMin) -le ($vMax - $h[2][1]))
            $vtx = if ($usaDir) { if ($deBaixo) { $dirBaixo } else { $dirAlto } } else { if ($deBaixo) { $esqBaixo } else { $esqAlto } }
            SelecionarEntidade $dm $front $vtx[0] $false | Out-Null; SelecionarEntidade $dm $front $h[0] $true | Out-Null
            if ((QtdSelecionados $dm) -ne 2) { continue }
            $yb = $o.y1 + $pad; $yt = $o.y2 - $pad; $yh = $yb + ($h[2][1] - $vMin) * $esc
            $yRef = if ($deBaixo) { $yb } else { $yt }
            $xc = if ($usaDir) { $xPonta + $DistCota + $k * 0.008 } else { $xPonta - $DistCota - $k * 0.008 }
            try { $dd = X $dm "AddVerticalDimension2" ([double]$xc) ([double](($yRef + $yh) / 2)) 0.0; if ($dd) { $n++; $k++; CentroTexto $dd } } catch { }
        }
        Log "   Cotas do metalon: comprimento + $nc na linha dos furos (ponta, par e passo entre pares)$(if ($nPar) { " + $nPar de par diferente" }) + $k altura(s) de furo"
    } else { $n += CotaTotal $dm $front $true $false }
    X $dm "ClearSelection2" $true | Out-Null
    # chamada de furo embaixo à esquerda ("14 x Ø9,50 PASSANTE")
    $f = 0; try { $f = ChamadasFuro $dm $front } catch { Log "   (chamada de furo: $($_.Exception.Message))" "DarkYellow" }
    # perfil: largura (em cima), altura (à esquerda) e parede (embaixo)
    if ($end) {
        $ne = 0
        try { $ne = CotaTotal $dm $end $true $true } catch { }
        $ep = 0; try { $ep = CotaEspessura $dm @($end) } catch { }
        Log "   Perfil do metalon: $ne cota(s) + $(if ($ep) { 'parede' } else { 'SEM parede (espessura não achada)' })"
    }
    Log "   Chamada(s) de furo: $f"
    Rebuild $dm
    ResolverSobreposicoes $dm @($front, $end, $script:isoAtual) @("furo")
}

function DetalharPeca($caminho, $peca) {
    $script:xfCache = @{}; $script:xfModo = @{}   # nomes de vista se repetem entre desenhos
    $script:chamadas = @()
    $cod = Codigo $caminho
    $desc = Prop $peca $PropDesc
    $laser = EhLaser $desc
    $chapa = TemChapa $peca
    Log "   Descrição: $desc | laser: $laser | chapa metálica: $chapa"
    $destDir = PastaDestino $caminho
    $drwPath = Join-Path $destDir "$cod.SLDDRW"
    if ((Test-Path $drwPath) -and -not $Sobrescrever) { Log "   Já existe $drwPath (Sobrescrever=não). Pulando criação." "Yellow"; Relatorio $caminho "peça" "detalhar" "pulado" "desenho já existe"; return }

    $b = XD (X $peca "GetPartBox" $true)
    $script:caixaPeca = $b
    $script:espessura = 0.0
    try {
        $ft = X $peca "FirstFeature"
        while ($ft) {
            if ([string](X $ft "GetTypeName2") -eq "SheetMetal") { $df = X $ft "GetDefinition"; $script:espessura = [double](XG $df "Thickness"); break }
            $ft = X $ft "GetNextFeature"
        }
    } catch { }
    if ($script:espessura -le 0) {
        $mEsp = [regex]::Match([string]$desc, "(?i)ESP\.?\s*([0-9]+(?:[\.,][0-9]+)?)")
        if ($mEsp.Success) { $script:espessura = [double]($mEsp.Groups[1].Value.Replace(",", ".")) / 1000 }
    }
    $X = [math]::Abs($b[3] - $b[0]); $Y = [math]::Abs($b[4] - $b[1]); $Z = [math]::Abs($b[5] - $b[2])
    Log ("   Caixa da peça (mm): {0:N1} x {1:N1} x {2:N1}" -f ($X * 1000), ($Y * 1000), ($Z * 1000))
    try { $real = [string](X $peca "GetPathName"); if ($real) { $caminho = $real } } catch { }
    $mx = [math]::Max($X, [math]::Max($Y, $Z))
    $mn = [math]::Min($X, [math]::Min($Y, $Z))
    if (EhMetalon $desc) {
        # METALON / METALOM: detalhamento próprio (padrão 02123721)
        Log "   Metalon: vista lateral com quebras + perfil + isométrica" "DarkGray"
        $laser = $false
        $dm = DetalharMetalon $caminho $peca $X $Y $Z $desc
    } else {
    # chapa plana (sem recurso de chapa metálica): nem sempre foi desenhada no plano frontal.
    # a vista principal é a que olha na direção da ESPESSURA (mostra a face de maior área)
    $plana = ($mn -lt 0.1 * $mx) -and ($laser -or $mn -le 0.0065)
    # chapa metálica: plana só se a menor medida da peça for a própria espessura (sem dobra);
    # com dobra a caixa fica mais alta que a espessura (aba) -> detalhamento de chapa dobrada (planificada, raio, notas)
    if ($chapa -and $script:espessura -gt 0) {
        $plana = ($mn -le $script:espessura * 1.1 + 0.0001)
        Log ("   Chapa metálica {0} (menor medida {1:N1} mm, espessura {2:N1} mm)" -f $(if ($plana) { "PLANA - sem dobra" } else { "DOBRADA" }), ($mn * 1000), ($script:espessura * 1000)) "DarkGray"
    }
    $nomesFrente = @($VistaFrontal, "*Frontal", "*Front")
    $script:planaAtual = $plana
    # peça USINADA prismática (bloco, placa grossa, guia...): padrão ProEstamp = frontal (face maior) + vista de baixo + isométrica,
    # cotas totais, posição dos furos, raios e chamada de furo. Peça de torno (redonda) continua com as cotas do modelo.
    $usinCedo = TemUsinagem $peca
    $redondaCedo = (-not $laser) -and (([math]::Abs($Y - $Z) -lt 0.01 * $mx) -or ([math]::Abs($X - $Z) -lt 0.01 * $mx))
    $usinPrisma = $usinCedo -and -not $laser -and -not $redondaCedo -and -not $plana
    $script:usinPrisma = $usinPrisma
    if ($usinPrisma) {
        if ($mn -eq $Z) { $nomesFrente = @("*Frontal", "*Front"); $pl = "frontal" }
        elseif ($mn -eq $Y) { $nomesFrente = @("*Superior", "*Top"); $pl = "superior" }
        else { $nomesFrente = @("*Esquerda", "*Left"); $pl = "lateral" }
        Log "   Peça usinada: vista principal = $pl (face maior) + vista de baixo + isométrica" "DarkGray"
    }
    if ($plana) {
        if ($mn -eq $Z) { $nomesFrente = @("*Frontal", "*Front") ; $pl = "frontal" }
        elseif ($mn -eq $Y) { $nomesFrente = @("*Superior", "*Top"); $pl = "superior" }
        else { $nomesFrente = @("*Esquerda", "*Left"); $pl = "lateral" }
        Log ("   Chapa plana (espessura {0:N1} mm): vista principal = {1} (face maior)" -f ($mn * 1000), $pl) "DarkGray"
    }
    $dm = NovoDesenho
    $front = VistaModelo $dm $caminho $nomesFrente 0.08 0.15
    if (-not $front) { throw "não consegui criar a vista frontal" }
    if ($plana -or $usinPrisma) { Deitar $dm $front }   # peça comprida em pé: gira a principal antes de projetar as outras
    $left = $null; $top = $null; $iso = $null; $flat = $null
    if (-not $usinPrisma) { try { Selecionar $dm $front | Out-Null; $left = X $dm "CreateUnfoldedViewAt3" 0.20 0.15 0.0 $false } catch { Log "   (vista lateral falhou: $($_.Exception.Message))" "DarkYellow" } }
    $redonda = (-not $laser) -and (([math]::Abs($Y - $Z) -lt 0.01 * $mx) -or ([math]::Abs($X - $Z) -lt 0.01 * $mx))
    if ($plana) { Log "   Chapa plana: principal + lateral + vista de baixo mostrando a espessura" "DarkGray" }
    if ($redonda -and -not $plana) { Log "   Peça de revolução: sem vista superior (repetiria a frontal)" "DarkGray" }
    else { try { Selecionar $dm $front | Out-Null; $top = X $dm "CreateUnfoldedViewAt3" 0.08 0.07 0.0 $false } catch { Log "   (vista superior falhou: $($_.Exception.Message))" "DarkYellow" } }
    $iso = VistaModelo $dm $caminho @("*Isométrica", "*Isometric") 0.25 0.17
    if ($laser -and $chapa -and -not $plana) {
        try { $flat = X $dm "CreateFlatPatternViewFromModelView3" $caminho (NomeConfig $peca) 0.2 0.07 0.0 $false $false } catch { }
        if (-not $flat) { Log "   Aviso: não criei a vista planificada no desenho." "Yellow" }
    }
    Log ("   Vistas: frontal ok" + $(if ($left) { ", lateral ok" } else { ", SEM lateral" }) + $(if ($top) { ", superior ok" } else { ", SEM superior" }) + $(if ($iso) { ", isométrica ok" } else { ", SEM isométrica" }) + $(if ($flat) { ", planificada ok" } else { "" }))
    foreach ($v in @($front, $left, $top, $flat)) { if ($v) { Modo $v $DispHidden $true } }
    if ($iso) { Modo $iso $DispShaded $true }
    # vista principal = a que mostra o comprimento maior na horizontal (como nos detalhamentos da ProEstamp)
    $cand = @(@($front, "*Frontal", "frontal"), @($left, "*Esquerda", "lateral"), @($top, "*Superior", "superior")) | Where-Object { $_[0] }
    $melhor = $cand | Sort-Object { -(Contorno $_[0]).w } | Select-Object -First 1
    if (-not $plana -and -not $usinPrisma -and $melhor[2] -ne "frontal" -and (Contorno $melhor[0]).w -gt 1.5 * (Contorno $front).w) {
        Log "   Vista principal trocada para $($melhor[1]) (comprimento na horizontal)" "DarkGray"
        foreach ($v in @($front, $left, $top)) { if ($v) { try { Selecionar $dm $v | Out-Null; X $dm "EditDelete" | Out-Null } catch { } } }
        $front = VistaModelo $dm $caminho @($melhor[1]) 0.08 0.15
        if (-not $front) { throw "não consegui recriar a vista principal" }
        $left = $null; $top = $null
        try { Selecionar $dm $front | Out-Null; $left = X $dm "CreateUnfoldedViewAt3" 0.20 0.15 0.0 $false } catch { }
        if (-not $redonda) { try { Selecionar $dm $front | Out-Null; $top = X $dm "CreateUnfoldedViewAt3" 0.08 0.07 0.0 $false } catch { } }
        foreach ($v in @($front, $left, $top)) { if ($v) { Modo $v $DispHidden $true } }
        Rebuild $dm
    }
    Deitar $dm $flat
    $of0 = Contorno $front
    $longa = ($of0.w -gt 2.5 * $of0.h)
    if ($longa) { Log "   Disposição para peça longa (vistas empilhadas)" "DarkGray" }

    # folga em volta das vistas para as cotas: maior quando entram as cotas do modelo (usinagem)
    $script:MargemCotas = if ($laser -and -not (TemUsinagem $peca)) { 0.010 } else { 0.018 }
    if ($usinPrisma) { $script:MargemCotas = 0.011; $Gap = 0.020 }   # usinada: cotas só em volta da principal, vistas mais próximas = escala maior
    # escala inicial pelo tamanho REAL das vistas (já com a orientação escolhida), sem contar a isométrica;
    # depois desce escala por escala até caber, tentando 3 arranjos: normal, isométrica menor e vistas empilhadas
    $esc0 = 1.0; try { $esc0 = [double](XG $front "ScaleDecimal") } catch { }
    if ($esc0 -le 0) { $esc0 = 1.0 }
    $cF = Contorno $front
    $lf = $cF.w; $hf = $cF.h
    if ($left) { $lf += (Contorno $left).w }
    if ($top) { $hf += (Contorno $top).h }
    if ($flat) { $lf = [math]::Max($lf, $cF.w + (Contorno $flat).w) }
    $lf = $lf / $esc0; $hf = $hf / $esc0
    $i0 = EscalaInicial $lf $hf
    if ($i0 -gt 0) { $i0-- }   # otimista: a disposição confere se coube
    $idx11 = 3   # posição de 1:1 na lista de escalas
    if ($mx -gt 0.040 -and $i0 -lt $idx11) { $i0 = $idx11 }
    $arranjos = if ($longa) { @("longa", "longa-iso") } else { @("normal", "iso", "longa", "longa-iso") }
    $ok = $false
    for ($i = $i0; $i -lt $Escalas.Count -and -not $ok; $i++) {
        $num = $Escalas[$i][0]; $den = $Escalas[$i][1]
        DefinirEscala $dm $num $den
        foreach ($arr in $arranjos) {
            $fi = switch ($arr) { "normal" { $FatorIso } "iso" { $FatorIso * 0.5 } "longa" { 0.35 } default { 0.2 } }
            if ($iso) { try { XS $iso "UseSheetScale" $false } catch { try { XS $iso "UseSheetScale" 0 } catch { } }; try { XS $iso "ScaleDecimal" (($num / $den) * $fi) } catch { } }
            Rebuild $dm
            $cabe = if ($arr -like "longa*") { LayoutPecaLonga $dm $front $left $top $iso $flat } else { LayoutPeca $dm $front $left $top $iso $flat }
            if ($cabe) { $ok = $true; Log "   Escala $num`:$den (arranjo $arr)"; break }
        }
    }
    if (-not $ok) { Log "   Aviso: as vistas não couberam perfeitamente; confira a disposição." "Yellow" }
    else { Centralizar $dm @($front, $left, $top, $flat, $iso) $AreaB }
    EspalharNotasDobra $dm $flat
    $script:isoAtual = $iso

    $usinagem = TemUsinagem $peca
    Log "   Processo: $(if ($laser) { 'laser' } else { 'fabricada' })$(if ($usinagem) { ' + usinagem' } else { '' })"
    if ($InserirCotas -and $laser -and -not $usinagem) {
        try { CotasLaser $dm $front $left $top $flat } catch { Log "   Aviso: cotas de laser falharam ($($_.Exception.Message))" "Yellow" }
    } elseif ($InserirCotas -and $usinPrisma) {
        try { CotasUsinagem $dm $front $top } catch { Log "   Aviso: cotas de usinagem falharam ($($_.Exception.Message))" "Yellow" }
    } elseif ($InserirCotas) {
        try {
            X $dm "ClearSelection2" $true | Out-Null
            $ann = X $dm "InsertModelAnnotations3" 0 ($InsDims + $InsHoleCallout) $true $false $false $false
            $n = 0; if ($ann) { $n = @($ann).Count }
            Log "   Cotas do modelo inseridas (peça com usinagem): $n"
        } catch { Log "   Aviso: não inseri cotas ($($_.Exception.Message))" "Yellow" }
    }
    }   # fim: peça que não é metalon
    TrocarDesenhista $dm
    Rebuild $dm

    SalvarComo $dm $drwPath $SaveSilent
    Log "   Desenho: $drwPath" "Green"
    $pdf = Join-Path $destDir "$cod.PDF"
    $pdfMsg = ""
    if ($script:FazPdf) { if (PdfProtegido $destDir $cod) { $pdfMsg = " (PDF mantido: existe APR)" } else { SalvarComo $dm $pdf ($SaveSilent + $SaveCopy); Log "   PDF: $pdf" "Green"; $pdfMsg = " + PDF" } }
    $dxfMsg = ""
    $fazDxf = if ($script:FazDxf -eq "auto") { $laser } else { [bool]$script:FazDxf }
    if ($fazDxf) { $dxf = Join-Path $destDir "$cod.DXF"; GerarDxf $caminho $peca $dxf $desc; Log "   DXF: $dxf" "Green"; $dxfMsg = " + DXF" }
    if ($FecharDesenho) { Fechar $dm }
    Relatorio $caminho "peça" "detalhar" "ok" ("desenho" + $pdfMsg + $dxfMsg)
}

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
    if (-not (EhPastaSolda $caminho)) { Log "   Aviso: não está numa pasta de SOLDA; vou detalhar igual (isométrica + lista)." "Yellow" }

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
            try { XS $op "IgnoreMultiple" $false } catch { }   # um balão para cada peça, mesmo repetida (padrão ProEstamp)
            try { XS $op "Style" (K "swBalloonStyle_e" @("swBS_None") 0) } catch { }
            try { XS $op "UpperTextContent" (K "swBalloonTextContent_e" @("swBalloonTextCustomProperties") 3) } catch { }
            try { XS $op "UpperText" "SW-Nome de arquivo(File Name)" } catch { }
            $bl = X $dm "AutoBalloon5" $op
            $nb = 0; if ($bl) { $nb = @($bl).Count }
            if ($nb -eq 0) { Log "   Aviso: o SolidWorks não colocou nenhum balão (desenho não estava ativo?)" "Yellow" } else { Log "   Balões com o Nº DA PEÇA: $nb" }
            if ($nb -gt 0) { Rebuild $dm; try { OrganizarBaloes $dm $v @($bl) } catch { Log "   (organizar balões: $($_.Exception.Message))" "DarkYellow" } }
        } catch { Log "   Aviso: não coloquei balões ($($_.Exception.Message))" "Yellow" }
    }
    Rebuild $dm
    # balões já organizados em fileiras (OrganizarBaloes); não passam mais pelo "afastar" genérico
    TrocarDesenhista $dm
    Rebuild $dm
    SalvarComo $dm $drwPath $SaveSilent
    Log "   Desenho: $drwPath" "Green"
    $pdf = Join-Path $destDir "$cod.PDF"
    $pdfMsg = ""
    if ($script:FazPdf) { if (PdfProtegido $destDir $cod) { $pdfMsg = " (PDF mantido: existe APR)" } else { SalvarComo $dm $pdf ($SaveSilent + $SaveCopy); Log "   PDF: $pdf" "Green"; $pdfMsg = " + PDF" } }
    if ($FecharDesenho) { Fechar $dm }
    Relatorio $caminho "montagem" "detalhar" "ok" ("desenho" + $pdfMsg)
}

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
            if (EhLaser $desc) { $dxf = Join-Path $destDir "$cod.DXF"; GerarDxf $prt $peca $dxf $desc; Log "   DXF: $dxf" "Green"; $msg = "PDF + DXF" }
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
        $dxf = Join-Path $destDir "$cod.DXF"
        GerarDxf $arq $peca $dxf $desc; Log "   DXF: $dxf" "Green"; $feito += "DXF"
    }
    Relatorio $arq "" "gerar" "ok" ($feito -join " + ")
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
    } elseif (Test-Path $a) { $lista += (Resolve-Path $a).Path }
}
Log "==================== $Modo : $($lista.Count) arquivo(s) ====================" "Cyan"
if ($PastaSaida -ne "") { Log "Saída de TESTE: $PastaSaida (o servidor não é alterado)" "Cyan" }

$nOk = 0; $nErro = 0
foreach ($arq in $lista) {
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
        Log ("   ERRO: " + $_.Exception.Message + " (linha " + $_.InvocationInfo.ScriptLineNumber + ")") "Red"
        Relatorio $arq "" $Modo "erro" $_.Exception.Message
    } finally {
        if ($FecharDesenho) { foreach ($d in $script:novosDesenhos) { try { X $sw "CloseDoc" (Titulo $d) | Out-Null } catch { } } }
        $script:novosDesenhos = @()
        FecharAbertos
    }
}
Log "Concluído: $nOk ok, $nErro com erro. Log: $LogFile" "Cyan"
if ($Modo -eq "gerar") {
    if ($nErro -gt 0) { Write-Host ""; Write-Host "Deu erro (veja acima). Pressione Enter para fechar." -ForegroundColor Yellow; [void](Read-Host) }
    else { Start-Sleep -Seconds 2 }
}
