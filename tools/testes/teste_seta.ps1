# teste: aplica SetasNoCentro no desenho ATIVO (não salva) e mostra a ponta da seta antes/depois
param([string]$Pasta = "C:\Users\adami\Documents\Monitor-SW\Detalhamento")
$ErrorActionPreference = "Stop"
$Modo = "diag"; $Saidas = ""; $Destino = ""; $Desenhista = ""; $Recriar = $false
$LogFile = Join-Path $env:TEMP "diag_baloes.log"; $RelFile = Join-Path $env:TEMP "diag_rel.csv"
foreach ($m in 'Nucleo\Config','Nucleo\SwCom','Nucleo\Utilidades','Nucleo\Cotas','Nucleo\Layout','Tipos\Solda') { . (Join-Path $Pasta "Modulos\$m.ps1") }
$script:xfCache = @{}; $script:xfModo = @{}
$dm = XG $sw "ActiveDoc"
$v = X (X $dm "GetFirstView") "GetNextView"
$ns = @(X $v "GetNotes") | ? { $_ }
foreach ($n in $ns) { $lp = XD (X (X $n "GetAnnotation") "GetLeaderPointsAtIndex" 0); "antes  " + (X $n "GetText") + ": " + ($lp[-3..-2] -join ";") }
$ns = SetasNoCentro $dm $v $ns
X $dm "GraphicsRedraw2" | Out-Null
foreach ($n in $ns) { $lp = XD (X (X $n "GetAnnotation") "GetLeaderPointsAtIndex" 0); "depois " + (X $n "GetText") + ": " + ($lp[-3..-2] -join ";") }
