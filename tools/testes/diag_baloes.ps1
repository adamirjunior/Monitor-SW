# diagnóstico: balões do desenho ATIVO no SolidWorks (não altera nada)
param([string]$Pasta = "X:\MonitorSW\Detalhamento")
$ErrorActionPreference = "Stop"
$Modo = "diag"; $Saidas = ""; $Destino = ""; $Desenhista = ""; $Recriar = $false
$LogFile = Join-Path $env:TEMP "diag_baloes.log"; $RelFile = Join-Path $env:TEMP "diag_rel.csv"
foreach ($m in 'Nucleo\Config','Nucleo\SwCom','Nucleo\Utilidades','Nucleo\Cotas') { . (Join-Path $Pasta "Modulos\$m.ps1") }
$script:xfCache = @{}; $script:xfModo = @{}
$dm = XG $sw "ActiveDoc"
"doc: " + (X $dm "GetTitle")
$sv = X $dm "GetFirstView"; $v = X $sv "GetNextView"
while ($v) {
  "VISTA " + (X $v "GetName2") + " xf=" + ((XD (XG (XG $v "ModelToViewTransform") "ArrayData")) -join ";")
  $o = Contorno $v; "  contorno x {0:N4}..{1:N4} y {2:N4}..{3:N4}" -f $o.x1,$o.x2,$o.y1,$o.y2
  foreach ($n in @(X $v "GetNotes")) {
    if (-not $n) { continue }
    $an = X $n "GetAnnotation"
    "  NOTA '" + (X $n "GetText") + "'"
    try { "    leader: " + ((XD (X $an "GetLeaderPointsAtIndex" 0)) -join ";") } catch { "    leader ERRO $($_.Exception.Message)" }
    try { "    attachpos: " + ((XD (X $n "GetAttachPos")) -join ";") } catch { }
    $ents = $null; try { $ents = X $an "GetAttachedEntities3" } catch { "    GetAttachedEntities3 ERRO $($_.Exception.Message)" }
    try { $tp = X $an "GetAttachedEntityTypes"; "    tipos: " + (@($tp) -join ",") } catch { }
    foreach ($e in @($ents)) {
      if (-not $e) { "    entidade nula"; continue }
      try { "    curveparams: " + ((XD (X $e "GetCurveParams2"))[0..7] -join ";") } catch { "    curveparams ERRO $($_.Exception.Message)" }
      try { $c = X $e "GetComponent"; "    comp: " + (XG $c "Name2") + " T=" + ((XD (XG (XG $c "Transform2") "ArrayData")) -join ";") } catch { "    comp ERRO $($_.Exception.Message)" }
      try { $fs = @(X $e "GetTwoAdjacentFaces2"); "    faces: " + $fs.Count + " areas " + (($fs | % { "{0:N6}" -f [double](X $_ "GetArea") }) -join ",") } catch { "    faces ERRO $($_.Exception.Message)" }
    }
  }
  $v = X $v "GetNextView"
}
