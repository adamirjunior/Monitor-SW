$ErrorActionPreference='Stop'
Add-Type -Path /home/claude/MonitorSW/src/Core.cs -ReferencedAssemblies System.Xml.ReaderWriter,System.IO.Compression,System.Linq,System.Collections,System.Console,System.Threading,System.Threading.Thread,System.Runtime,System.Text.Encoding.Extensions
$up='/mnt/user-data/uploads/SOLIDWORKS/'
$global:map=@{
 'X:\SOLIDWORKS\01 (MONTAGEM)\01121 (CUP-600 COM TROCA)\01121001 CUP-600 V1.SLDASM'=$up+'01 (MONTAGEM)/01121 (CUP-600 COM TROCA)/01121001 CUP-600 V1.SLDASM';
 'X:\SOLIDWORKS\01 (MONTAGEM)\01121 (CUP-600 COM TROCA)\SUBMONTAGENS\01121001_001 CONJUNTO XYZ.SLDASM'=$up+'01 (MONTAGEM)/01121 (CUP-600 COM TROCA)/SUBMONTAGENS/01121001_001 CONJUNTO XYZ.SLDASM';
 'X:\SOLIDWORKS\02 (COMPONENTES DE ESTAMPO)\0229 (CHAVE)\0229016.SLDPRT'=$up+'02 (COMPONENTES DE ESTAMPO)/0229 (CHAVE)/0229016.SLDPRT';
 'X:\SOLIDWORKS\02 (COMPONENTES DE ESTAMPO)\0229 (CHAVE)\0229016.SLDDRW'=$up+'02 (COMPONENTES DE ESTAMPO)/0229 (CHAVE)/0229016.SLDDRW'}
[MonitorSW.Util]::OpenHook=[Func[string,string]]{ param($p) $v=$global:map[$p]; if($v){$v}else{'/nonexistent'} }
foreach($k in $global:map.Keys){ $m=[MonitorSW.SwReader]::Read($k,$k.EndsWith('ASM')); "{0}: por={1} arvore={2} erro={3}" -f ([MonitorSW.Util]::NameOf($k)),$m.LastBy,($m.TreeXml -ne $null),$m.Error }
$app='/tmp/claude-0/-home-claude/9d0769be-0aae-5054-8dcf-1a40c501878e/scratchpad/apptest2'; Remove-Item -Recurse -Force $app -ea 0; mkdir $app | Out-Null
[MonitorSW.Util]::AppDir=$app
$global:old=[datetime]'2026-01-01'
$main='X:\SOLIDWORKS\01 (MONTAGEM)\01121 (CUP-600 COM TROCA)\01121001 CUP-600 V1.SLDASM'
$xyz='X:\SOLIDWORKS\01 (MONTAGEM)\01121 (CUP-600 COM TROCA)\SUBMONTAGENS\01121001_001 CONJUNTO XYZ.SLDASM'
[MonitorSW.Util]::MTimeHook=[Func[string,datetime]]{ param($p) if($p -eq $global:xyzK){[datetime]'2026-06-01'} elseif($p -eq $global:mainK){[datetime]'2026-05-01'} elseif($p -match 'SLD(PRT|ASM)$'){$global:old} else {[datetime]::MinValue} }
$global:xyzK=$xyz; $global:mainK=$main
$cfg=[MonitorSW.Config]::Load((Join-Path $app 'config.ini')); $cfg.Projects.Clear(); $cfg.Projects.Add($main)
$eng=[MonitorSW.Engine]::new($cfg); $eng.add_Progress([Action[string]]{ param($s) if($s -like 'Lendo*'){ "  > $s" } })
$p=$eng.Projects[0]; $null=$eng.ScanProject($p)
"itens=$($p.Items.Count) filhos XYZ=$($p.Children[$xyz].Count) fonte XYZ=$($p.ChildrenSrc[$xyz])  pend=$($p.Pend) info=$($p.Info)"
