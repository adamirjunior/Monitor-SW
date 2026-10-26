# Compara os valores padrão das constantes K "enum" @("nome") padrão do gerador com a biblioteca swconst do SolidWorks.
param([string]$Pasta = "C:\Users\adami\Documents\Monitor-SW\Detalhamento", [string]$Dll = "D:\SOLIDWORKS\api\redist\SolidWorks.Interop.swconst.dll")
$a = [Reflection.Assembly]::LoadFrom($Dll)
$rx = [regex]'K\s+"(?<e>sw\w+)"\s+@\((?<n>[^)]*)\)\s+(?<d>-?\d+)'
$vistos = @{}
foreach ($f in Get-ChildItem $Pasta -Recurse -Filter *.ps1) {
    foreach ($m in $rx.Matches((Get-Content $f.FullName -Raw))) {
        $e = $m.Groups['e'].Value; $d = [int]$m.Groups['d'].Value
        $nomes = @([regex]::Matches($m.Groups['n'].Value, '"([^"]+)"') | ForEach-Object { $_.Groups[1].Value })
        $k = "$e/$($nomes -join ',')/$d"; if ($vistos[$k]) { continue }; $vistos[$k] = 1
        $t = $a.GetType("SolidWorks.Interop.swconst.$e"); $real = $null
        if ($t) { foreach ($n in $nomes) { try { $real = [int][Enum]::Parse($t, $n); break } catch { } } }
        $st = if ($null -eq $real) { "SEM NOME" } elseif ($real -eq $d) { "ok" } else { "ERRADO (real $real)" }
        "{0,-12} {1}.{2} padrão {3}  [{4}]" -f $st, $e, ($nomes -join '|'), $d, $f.Name
    }
}
