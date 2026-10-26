# Fecha (sem salvar) documentos abertos no SolidWorks cujo título combina com -Titulo (ex.: "Desenho4*") - limpeza depois de testes.
param([Parameter(Mandatory = $true)][string]$Titulo, [string]$Pasta = "C:\Users\adami\Documents\Monitor-SW\Detalhamento")
$ErrorActionPreference = "Stop"
$Modo = "diag"; $Saidas = ""; $Destino = ""; $Desenhista = ""; $Recriar = $false
$LogFile = Join-Path $env:TEMP "diag_fechar.log"; $RelFile = Join-Path $env:TEMP "diag_rel.csv"
foreach ($m in 'Nucleo\Config','Nucleo\SwCom','Nucleo\Utilidades') { . (Join-Path $Pasta "Modulos\$m.ps1") }
$fechar = @()
$d = X $sw "GetFirstDocument"
while ($d) { $t = Titulo $d; if ($t -like $Titulo) { $fechar += $t }; $d = X $d "GetNext" }
foreach ($t in $fechar) { try { X $sw "CloseDoc" $t | Out-Null; "fechado: $t" } catch { "não fechou: $t" } }
