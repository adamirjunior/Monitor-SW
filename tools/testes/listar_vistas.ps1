# Abre um desenho e lista as vistas (contorno na folha) e os segmentos de esboço de cada uma (diagnóstico de traço solto).
param([Parameter(Mandatory = $true)][string]$Desenho, [string]$Pasta = "C:\Users\adami\Documents\Monitor-SW\Detalhamento", [switch]$Fechar)
$ErrorActionPreference = "Stop"
$Modo = "diag"; $Saidas = ""; $Destino = ""; $Desenhista = ""; $Recriar = $false
$LogFile = Join-Path $env:TEMP "diag_vistas.log"; $RelFile = Join-Path $env:TEMP "diag_rel.csv"
foreach ($m in 'Nucleo\Config','Nucleo\SwCom','Nucleo\Utilidades') { . (Join-Path $Pasta "Modulos\$m.ps1") }
$d = AbrirDoc $Desenho 3
if (-not $d) { "não abriu $Desenho"; exit 1 }
$v = X $d "GetFirstView"
while ($v) {
    $o = XD (X $v "GetOutline")
    "{0} | {1:N4};{2:N4} - {3:N4};{4:N4}" -f (X $v "GetName2"), $o[0], $o[1], $o[2], $o[3]
    try {
        $sk = X $v "GetSketch"
        if ($sk) {
            foreach ($s in @(X $sk "GetSketchSegments")) {
                if (-not $s) { continue }
                $t = X $s "GetType"
                $txt = "   segmento tipo $t"
                if ($t -eq 0) { try { $p1 = X $s "GetStartPoint2"; $p2 = X $s "GetEndPoint2"; $txt += (" ({0:N4};{1:N4})-({2:N4};{3:N4})" -f (XG $p1 "X"), (XG $p1 "Y"), (XG $p2 "X"), (XG $p2 "Y")) } catch { } }
                $txt
            }
        }
    } catch { "   (esboço: $($_.Exception.Message))" }
    try { "   anotações: " + (X $v "GetAnnotationCount") } catch { }
    $v = X $v "GetNextView"
}
if ($Fechar) { FecharAbertos }
