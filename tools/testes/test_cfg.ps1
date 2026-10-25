Add-Type -Path /home/claude/MonitorSW/src/Core.cs -ReferencedAssemblies System.Xml.ReaderWriter,System.IO.Compression,System.Linq,System.Collections,System.Console,System.Threading,System.Threading.Thread,System.Runtime,System.Text.Encoding.Extensions,System.Text.RegularExpressions,System.Net.Primitives,System.Runtime.Extensions
$d='/tmp/claude-0/-home-claude/9d0769be-0aae-5054-8dcf-1a40c501878e/scratchpad/cfgtest'; Remove-Item -Recurse -Force $d -ea 0; mkdir $d | Out-Null
# config do PC do usuario (anterior a v1.4) + um no formato v1.4
Copy-Item '/mnt/user-data/uploads/Documents/MonitorSW/config.ini' "$d/a.ini"
"RaizServidor=X:\SOLIDWORKS`nPastasSolda=1301|1304`nColunasLista=ACABAMENTO|QDT.`nIndiceAtivo=sim`nIndicePastasMaquinas=01 (MONTAGEM)`nProjeto=X:\SOLIDWORKS\a.SLDASM" | Set-Content "$d/b.ini"
foreach($f in 'a.ini','b.ini'){ $c=[MonitorSW.Config]::Load("$d/$f"); "{0}: raizes={1} maquinas={2} ignora={3} projetos={4}" -f $f,($c.IndexRoots -join ','),($c.IndexMachineFolders -join ','),($c.IndexSkip -join ','),$c.Projects.Count }
Select-String -Path "$d/a.ini" -Pattern 'Indice' | % { $_.Line }
