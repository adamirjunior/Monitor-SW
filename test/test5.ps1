$ErrorActionPreference='Stop'
Add-Type -Path /home/claude/MonitorSW/src/Core.cs -ReferencedAssemblies System.Xml.ReaderWriter,System.IO.Compression,System.Linq,System.Collections,System.Console,System.Threading,System.Threading.Thread,System.Runtime,System.Text.Encoding.Extensions,System.Text.RegularExpressions
$staged='/mnt/user-data/uploads/SOLIDWORKS/01 (MONTAGEM)/0155 (CUP)/0155023 (CUP-400 V1)/0155023 CUP-400 V1.SLDASM'
$main='X:\SOLIDWORKS\01 (MONTAGEM)\0155 (CUP)\0155023 (CUP-400 V1)\0155023 CUP-400 V1.SLDASM'
$app='/tmp/claude-0/-home-claude/9d0769be-0aae-5054-8dcf-1a40c501878e/scratchpad/apptest'
Remove-Item -Recurse -Force $app -ErrorAction SilentlyContinue; New-Item -ItemType Directory $app | Out-Null
[MonitorSW.Util]::AppDir=$app
# sistema de arquivos falso: le a lista de arquivos da arvore real
$fs=@{}
$tree=Get-Content /tmp/claude-0/-home-claude/9d0769be-0aae-5054-8dcf-1a40c501878e/scratchpad/fakefs.tsv
foreach($l in $tree){ $p,$t=$l -split "`t"; $fs[$p.ToUpper()]=[datetime]::Parse($t) }
$global:fs=$fs
[MonitorSW.Util]::MTimeHook=[Func[string,datetime]]{ param($p) $v=$global:fs[$p.ToUpper()]; if($v){$v}else{[datetime]::MinValue} }
$global:main=$main; $global:staged=$staged
[MonitorSW.Util]::OpenHook=[Func[string,string]]{ param($p) if($p -eq $global:main){$global:staged}else{'/nonexistent'} }

[MonitorSW.Util]::ListHook=[Func[string,string,Collections.Generic.List[Collections.Generic.KeyValuePair[string,datetime]]]]{ param($d,$pat)
  $l=[Collections.Generic.List[Collections.Generic.KeyValuePair[string,datetime]]]::new()
  $pre=($d.TrimEnd('\')+'\').ToUpper()
  foreach($k in $global:fs.Keys){ if($k.StartsWith($pre) -and $k.Substring($pre.Length) -notmatch '\\' -and $k -like '*APR*'){ $l.Add([Collections.Generic.KeyValuePair[string,datetime]]::new($k,$global:fs[$k])) } }
  ,$l }
$cfgPath=Join-Path $app 'config.ini'
$cfg=[MonitorSW.Config]::Load($cfgPath)
"Ignored: " + ($cfg.Ignored -join ',') + " | Projects: " + $cfg.Projects.Count
$eng=[MonitorSW.Engine]::new($cfg)
$p=$eng.Projects[0]
function Show($evs){ "--- eventos: $($evs.Count)"; foreach($e in $evs){ "  [$($e.Kind)] $($e.Item) por '$($e.Who)': $($e.Detail)" } ; "pend=$($p.Pend) info=$($p.Info) ok=$($p.Ok) itens=$($p.Items.Count) erro=$($p.Error)" }

$null=$eng.ScanProject($p)
"itens=$($p.Items.Count) pend=$($p.Pend)"
# simula propriedades lidas
$v=[Linq.Enumerable]::ToList($p.Items.Values)
$parts=$v | ? { -not $_.IsAsm -and -not $_.Ignored }
foreach($it in $parts){ $it.PropsKnown=$true; $it.LastByStamp=$it.Model; $it.Desc='TREF. RED. 1020'; $it.IsMach=$true; $it.MachSteps='TORNO CNC' }
$laser=$parts | ? { $_.Folder -like '0220*' } | select -First 3
foreach($it in $laser){ $it.Desc='LASER 1020 - ESP 1.5mm'; $it.IsLaser=$true; $it.IsMach=$false; $it.MachSteps='' }
$laser[0].IsMach=$true
$eng.Reclassify($p)
"--- exemplos"
foreach($it in ($laser + ($parts | ? { $_.Folder -notlike '0220*' } | select -First 2))){ "{0,-12} {1,-18} exige {2,-10} PDF={3,-14} DXF={4,-14} -> {5}" -f $it.Name,$it.Process,$it.Need,$it.PdfSt,$it.DxfSt,$it.Status }
"--- montagens"
$v | ? { $_.IsAsm } | select -First 8 | % { "{0,-28} {1,-9} exige {2,-4} sev={3} {4}  pend.dentro={5}" -f $_.Name,$_.Process,$_.Need,$_.Sev,$_.Status,$_.PendBelow }
"--- quantidades"
$v | ? { $_.Name -in '0303380 M4X10','0313436 VENTILADOR PARA PAINEL 110X110 - 220V','03033704 ARRUELA M12','0303093 PORCA M6' } | % { "{0} total={1}" -f $_.Name,$_.TotQty }
"pend=$($p.Pend) ok=$($p.Ok) info=$($p.Info)"
# peca bloqueada alterada
$b=$parts | ? { $_.Folder -notlike '0220*' } | select -First 1
$b.Blocked='BLOQUEADO'; $b.Aprov='002'
$p.Prev=[MonitorSW.Engine].GetMethod('MakeSnap',[Reflection.BindingFlags]'NonPublic,Static').Invoke($null,@($p))
$global:fs[$b.Key.ToUpper()]=[datetime]::Now
$global:map=@{}
Show ($eng.ScanProject($p))
"--- solda"
[Linq.Enumerable]::ToList($p.Items.Values) | ? { $_.IsWeld } | select -First 5 | % { "{0,-12} {1} exige {2} -> {3} [{4}]" -f $_.Name,$_.Process,$_.Need,$_.Status,$_.Reason }
"solda total: " + ([Linq.Enumerable]::ToList($p.Items.Values) | ? { $_.IsWeld }).Count
