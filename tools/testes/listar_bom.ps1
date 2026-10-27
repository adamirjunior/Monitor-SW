# Lista as colunas da lista de materiais (BOM) de um desenho: título, propriedade ligada e valores (diagnóstico).
param([Parameter(Mandatory = $true)][string]$Desenho, [string]$Pasta = "C:\Users\adami\Documents\Monitor-SW\Detalhamento", [switch]$Fechar)
$ErrorActionPreference = "Stop"
$Modo = "diag"; $Saidas = ""; $Destino = ""; $Desenhista = ""; $Recriar = $false
$LogFile = Join-Path $env:TEMP "diag_bom.log"; $RelFile = Join-Path $env:TEMP "diag_rel.csv"
foreach ($m in 'Nucleo\Config','Nucleo\SwCom','Nucleo\Utilidades') { . (Join-Path $Pasta "Modulos\$m.ps1") }
$d = AbrirDoc $Desenho 3
if (-not $d) { "não abriu $Desenho"; exit 1 }
$v = X $d "GetFirstView"
while ($v) {
    $tas = $null; try { $tas = X $v "GetTableAnnotations" } catch { }
    foreach ($t in @($tas)) {
        if (-not $t) { continue }
        $tp = -1; try { $tp = [int](XG $t "Type") } catch { }
        $nc = [int](XG $t "ColumnCount"); $nr = [int](XG $t "RowCount")
        "tabela tipo $tp : $nc colunas x $nr linhas (vista $(X $v 'GetName2'))"
        $bom = $null; try { $bom = $t } catch { }
        for ($c = 0; $c -lt $nc; $c++) {
            $tit = ""; try { $tit = [string](X $t "GetColumnTitle2" $c $true) } catch { try { $tit = [string](X $t "GetColumnTitle" $c) } catch { } }
            $prop = ""; try { $prop = [string](X $t "GetColumnCustomProperty" $c) } catch { }
            $ty = ""; try { $ty = [string](X $t "GetColumnType" $c) } catch { }
            $w = 0; try { $w = [double](X $t "GetColumnWidth" $c) } catch { }
            $vals = @(); for ($r = 0; $r -lt [math]::Min($nr, 12); $r++) { try { $vals += [string](X $t "Text" $r $c) } catch { try { $vals += [string](XG $t "Text" $r $c) } catch { $vals += "?" } } }
            "  col {0}: título='{1}' prop='{2}' tipo={3} larg={4:N1}mm | {5}" -f $c, $tit, $prop, $ty, ($w * 1000), ($vals -join " ; ")
        }
    }
    $v = X $v "GetNextView"
}
if ($Fechar) { FecharAbertos }
