$ErrorActionPreference='Stop'
Add-Type -Path /home/claude/MonitorSW/src/Core.cs -ReferencedAssemblies System.Xml.ReaderWriter,System.IO.Compression,System.Linq,System.Collections,System.Console,System.Threading,System.Threading.Thread,System.Runtime,System.Text.Encoding.Extensions,System.Text.RegularExpressions,System.Net.Primitives,System.Runtime.Extensions
$staged='/mnt/user-data/uploads/SOLIDWORKS/01 (MONTAGEM)/0155 (CUP)/0155023 (CUP-400 V1)/0155023 CUP-400 V1.SLDASM'
$m=[MonitorSW.SwReader]::Read($staged,$true)
$root=$null
$t=[MonitorSW.SwReader]::ParseTree($m.TreeXml,[ref]$root)
$kids=$t[$root]
$parts=@($kids | ? { $_.Child -notlike '*.SLDASM' }); $asms=@($kids | ? { $_.Child -like '*.SLDASM' })
$n=0; foreach($k in ($parts+$asms)){ $n++; if($n -le 12 -or $n -ge 57){ "{0,3} {1,-60} x{2}" -f $n,($k.Child.Split('\')[-1]),$k.Qty } }
"--- 13023104"
$sub=$t.Keys | ? { $_ -like '*13023104.SLDASM' }
$k2=$t[$sub]; $p2=@($k2 | ? { $_.Child -notlike '*.SLDASM' }); $a2=@($k2 | ? { $_.Child -like '*.SLDASM' })
$i=0; foreach($k in ($p2+$a2)){ $i++; if($i -le 8 -or $k.Child -like '*ASM'){ "59.{0,-3} {1,-50} x{2}" -f $i,($k.Child.Split('\')[-1]),$k.Qty } }
