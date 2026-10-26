# Salva um documento aberto no SolidWorks como PDF (cópia) para conferir o resultado de um teste.
# -Titulo "Desenho*" escolhe pelo título (padrão: o documento ativo).
param([string]$Saida = "$env:USERPROFILE\Documents\teste_ativo.pdf", [string]$Titulo = "", [string]$Pasta = "C:\Users\adami\Documents\Monitor-SW\Detalhamento")
$ErrorActionPreference = "Stop"
$Modo = "diag"; $Saidas = ""; $Destino = ""; $Desenhista = ""; $Recriar = $false
$LogFile = Join-Path $env:TEMP "diag_pdf.log"; $RelFile = Join-Path $env:TEMP "diag_rel.csv"
foreach ($m in 'Nucleo\Config','Nucleo\SwCom','Nucleo\Utilidades') { . (Join-Path $Pasta "Modulos\$m.ps1") }
$dm = XG $sw "ActiveDoc"
if ($Titulo) {
    $d = X $sw "GetFirstDocument"
    while ($d) { $t = Titulo $d; "aberto: $t"; if ($t -like $Titulo) { $dm = $d }; $d = X $d "GetNext" }
}
"Usando: " + (Titulo $dm)
if (Test-Path $Saida) { Remove-Item $Saida -Force }
X $dm "SaveAs3" $Saida 0 3 | Out-Null
"PDF: " + (Test-Path $Saida)
