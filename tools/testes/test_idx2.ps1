$ErrorActionPreference='Stop'
Add-Type -Path /home/claude/MonitorSW/src/Core.cs,/home/claude/MonitorSW/src/Indexer.cs -ReferencedAssemblies System.Xml.ReaderWriter,System.IO.Compression,System.Linq,System.Collections,System.Console,System.Threading,System.Threading.Thread,System.Runtime,System.Text.Encoding.Extensions,System.Text.RegularExpressions,System.Net.Primitives,System.Runtime.Extensions
$up='/mnt/user-data/uploads/SOLIDWORKS/01 (MONTAGEM)/'
$global:map=@{
 'X:\SOLIDWORKS\01 (MONTAGEM)\01121 (CUP-600 COM TROCA)\01121001 CUP-600 V1.SLDASM'=$up+'01121 (CUP-600 COM TROCA)/01121001 CUP-600 V1.SLDASM';
 'X:\SOLIDWORKS\01 (MONTAGEM)\01121 (CUP-600 COM TROCA)\SUBMONTAGENS\01121001_001 CONJUNTO XYZ.SLDASM'=$up+'01121 (CUP-600 COM TROCA)/SUBMONTAGENS/01121001_001 CONJUNTO XYZ.SLDASM';
 'X:\SOLIDWORKS\01 (MONTAGEM)\0151 (CUP-400 COM TROCA)\0151001 CUP-400.SLDASM'=$up+'0151 (CUP-400 COM TROCA)/0151001 CUP-400.SLDASM';
 'X:\SOLIDWORKS\01 (MONTAGEM)\0151 (CUP-400 COM TROCA)\0151003 CUP-400 V3\0151003 CUP-400 V3.SLDASM'=$up+'0151 (CUP-400 COM TROCA)/0151003 CUP-400 V3/0151003 CUP-400 V3.SLDASM';
 'X:\SOLIDWORKS\01 (MONTAGEM)\0154 (CUP-1500 COM TROCA)\0154002 CUP-1500 COM TROCA V2\0154002 CUP-1500 COM TROCA V2.SLDASM'=$up+'0154 (CUP-1500 COM TROCA)/0154002 CUP-1500 COM TROCA V2/0154002 CUP-1500 COM TROCA V2.SLDASM';
 'X:\SOLIDWORKS\01 (MONTAGEM)\0155 (CUP)\0155023 (CUP-400 V1)\0155023 CUP-400 V1.SLDASM'=$up+'0155 (CUP)/0155023 (CUP-400 V1)/0155023 CUP-400 V1.SLDASM';
 'X:\SOLIDWORKS\01 (MONTAGEM)\01124 (MUXARABI)\01124001 - PPA-100 (PRENSA MUXARABI AUTOMATIZADA)\01124001 - PPA-100 (PRENSA MUXARABI AUTOMATIZADA).SLDASM'=$up+'01124 (MUXARABI)/01124001 - PPA-100 (PRENSA MUXARABI AUTOMATIZADA)/01124001 - PPA-100 (PRENSA MUXARABI AUTOMATIZADA).SLDASM'
}
[MonitorSW.Util]::OpenHook=[Func[string,string]]{ param($p) $v=$global:map[$p]; if($v){$v}else{'/nonexistent'} }
[MonitorSW.Util]::MTimeHook=[Func[string,datetime]]{ param($p) if($global:map.ContainsKey($p)){[datetime]'2026-10-01'} else {[datetime]'2026-01-01'} }
$global:extra=@('X:\SOLIDWORKS\02 (COMPONENTES DE ESTAMPO)\0227 (ACOPLAMENTO)\0227009.SLDPRT','X:\SOLIDWORKS\02 (COMPONENTES DE ESTAMPO)\0227 (ACOPLAMENTO)\0227009.PDF','X:\SOLIDWORKS\02 (COMPONENTES DE ESTAMPO)\0299 (SOLTAS)\0299001 PECA SOLTA.SLDPRT','X:\SOLIDWORKS\13 ( SUBMONTAGEM )\1301 ( SUBMONTAGEM SOLDA )\13019999.SLDASM')
[MonitorSW.Indexer]::EnumHook=[Func[string,Collections.Generic.List[string]]]{ param($d) $global:enumDir=$d; $l=[Collections.Generic.List[string]]::new(); foreach($k in $global:map.Keys){ $l.Add($k) }; foreach($k in $global:extra){ $l.Add($k) }; ,$l }
$app='/tmp/claude-0/-home-claude/9d0769be-0aae-5054-8dcf-1a40c501878e/scratchpad/apptest_idx'; Remove-Item -Recurse -Force $app -ea 0; mkdir $app | Out-Null
[MonitorSW.Util]::AppDir=$app
$cfg=[MonitorSW.Config]::Load((Join-Path $app 'config.ini'))
$ix=[MonitorSW.Indexer]::new([Func[MonitorSW.Config]]{ $cfg }.GetNewClosure())
$sw=[Diagnostics.Stopwatch]::StartNew()
$ix.RunOnce()
"tempo 1a vez: {0:N1}s  maquinas={1} codigos={2}" -f ($sw.ElapsedMilliseconds/1000),$ix.Machines,$ix.Codes
$sw.Restart(); $ix.RunOnce(); "tempo 2a vez (nada mudou): {0:N2}s" -f ($sw.ElapsedMilliseconds/1000)
"--- busca LUBRIFIL"
$ix.Search('LUBRIFIL',20) | % { "{0} | {1} | qtd {2} | {3}" -f $_.Code,$_.Machine,$_.Qty,$_.Chains }
"--- busca 0227009"
$ix.Search('0227009',20) | % { "{0} | {1} | qtd {2} | {3}" -f $_.Code,$_.Machine,$_.Qty,$_.Chains }
"raiz listada: $global:enumDir"; "IndexRoots: " + ($cfg.IndexRoots -join ",") + " | maquinas: " + ($cfg.IndexMachineFolders -join ",")
"--- arquivos"
Get-ChildItem -Recurse $app/indice | % { "{0,10}  {1}" -f $_.Length,$_.FullName.Replace($app,'') }
"--- status.txt"; Get-Content $app/indice/status.txt
"--- codigos.tsv (LUBRIFIL)"; Select-String -Path $app/indice/codigos.tsv -Pattern 'LUBRIFIL' | % { $_.Line }
"--- catalogo 0227"; Get-Content $app/indice/catalogo/0227.tsv
"--- catalogo 0299"; Get-Content $app/indice/catalogo/0299.tsv
"--- maquinas.tsv"; Get-Content $app/indice/maquinas.tsv | % { ($_ -split "`t")[0..3] -join ' | ' }
