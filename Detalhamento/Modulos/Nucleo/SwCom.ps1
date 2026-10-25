# SwCom.ps1 - ponte COM com o SolidWorks (X, XG, XS, K...) e constantes
# Carregado pelo DetalharSW.ps1 (dot-source). Não rodar sozinho.

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
