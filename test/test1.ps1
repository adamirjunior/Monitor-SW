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

$cfgPath=Join-Path $app 'config.ini'
$cfg=[MonitorSW.Config]::Load($cfgPath)
"Ignored: " + ($cfg.Ignored -join ',') + " | Projects: " + $cfg.Projects.Count
$eng=[MonitorSW.Engine]::new($cfg)
$p=$eng.Projects[0]
function Show($evs){ "--- eventos: $($evs.Count)"; foreach($e in $evs){ "  [$($e.Kind)] $($e.Item) por '$($e.Who)': $($e.Detail)" } ; "pend=$($p.Pend) info=$($p.Info) ok=$($p.Ok) itens=$($p.Items.Count) erro=$($p.Error)" }
$sw=[Diagnostics.Stopwatch]::StartNew()
Show ($eng.ScanProject($p)); "tempo " + $sw.ElapsedMilliseconds + " ms"
# exemplos de situacao
$p.Items.Values | Where-Object { -not $_.Ignored } | Group-Object Status | Sort-Object Count -desc | ForEach-Object { "  {0,4}  {1}" -f $_.Count,$_.Name }
# escolhe uma peca fabricada dentro de submontagem com PDF ok
$part=$p.Items.Values | Where-Object { -not $_.IsAsm -and -not $_.Ignored -and $_.Status -eq 'OK' -and $_.Parents.Count -gt 0 -and ($_.Parents[0] -like '*13 ( SUBMONTAGEM )*') } | Select-Object -First 1
"Peca teste: $($part.Name) pais: $($part.Parents -join ' | ')"
"Cadeias:"; foreach($c in $p.Chains($part.Key,5)){ "  " + (($c | ForEach-Object { [MonitorSW.Util]::NameOf($_) }) -join ' > ') }
# 2) alguem salva a peca agora
$global:fs[$part.Key.ToUpper()]=[datetime]::Now
Show ($eng.ScanProject($p))
# 3) gera o PDF/DXF
$stem=$part.Key.Substring(0,$part.Key.LastIndexOf('.'))
$global:fs[($stem+'.SLDDRW').ToUpper()]=[datetime]::Now
$global:fs[($stem+'.PDF').ToUpper()]=[datetime]::Now
if($global:fs.ContainsKey(($stem+'.DXF').ToUpper())){ $global:fs[($stem+'.DXF').ToUpper()]=[datetime]::Now }
Show ($eng.ScanProject($p))
# 4) estado salvo e recarregado (monitor reiniciado) e uma alteracao feita com ele fechado
$eng.RunOnce() | Out-Null
$eng2=[MonitorSW.Engine]::new([MonitorSW.Config]::Load($cfgPath)); $p=$eng2.Projects[0]
"estado carregado: $($p.Prev.Count) itens"
$other=$p.Prev.Keys | Where-Object { $_ -like '*0220 (CARENAGEM*' -and $_ -like '*.SLDPRT' } | Select-Object -First 1
$global:fs[$other.ToUpper()]=[datetime]::Now
Show ($eng2.ScanProject($p))
[MonitorSW.Engine]::AppendHistory((Join-Path $app 'historico.csv'), $eng2.ScanProject($p))
'--- config.ini'; Get-Content $cfgPath | Select-Object -First 30
