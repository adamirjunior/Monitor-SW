param([string]$Pasta = "C:\Users\adami\Documents\Monitor-SW\Detalhamento")
$ErrorActionPreference = "Stop"
$Modo = "diag"; $Saidas = ""; $Destino = ""; $Desenhista = ""; $Recriar = $false
$LogFile = Join-Path $env:TEMP "diag_baloes.log"; $RelFile = Join-Path $env:TEMP "diag_rel.csv"
foreach ($m in 'Nucleo\Config','Nucleo\SwCom','Nucleo\Utilidades','Nucleo\Cotas') { . (Join-Path $Pasta "Modulos\$m.ps1") }
$dm = XG $sw "ActiveDoc"; $ext = XG $dm "Extension"; $sm = XG $dm "SelectionManager"
foreach ($t in @("FACE", "EDGE", "")) { foreach ($pt in @(@(0.1047, 0.1571), @(0.1100, 0.1500), @(0.1200, 0.1450))) {
  X $dm "ClearSelection2" $true | Out-Null
  $r = "erro"
  try { $r = X $ext "SelectByID2" "" $t $pt[0] $pt[1] 0.0 $false 0 $null 0 } catch { $r = "EXC " + $_.Exception.Message }
  $q = 0; try { $q = X $sm "GetSelectedObjectCount2" -1 } catch { }
  $tp = ""; try { $tp = X $sm "GetSelectedObjectType3" 1 -1 } catch { }
  "SelectByID2 tipo '$t' em ($($pt -join ';')): $r | selecionados $q tipo $tp"
} }
try { X $dm "ClearSelection2" $true | Out-Null; $r = X $dm "SelectByID" "" "FACE" 0.1100 0.1500 0.0; "SelectByID antigo: $r  sel=" + (X $sm "GetSelectedObjectCount2" -1) } catch { "SelectByID EXC " + $_.Exception.Message }
X $dm "ClearSelection2" $true | Out-Null
