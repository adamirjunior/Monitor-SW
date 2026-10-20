$ErrorActionPreference='Stop'
$refDir='/home/claude/mono/reference-assemblies/v4.5'
$asm=[AppDomain]::CurrentDomain.GetAssemblies() | ? { $_.GetName().Name -eq 'Microsoft.CodeAnalysis.CSharp' }
if(-not $asm){ Add-Type -AssemblyName Microsoft.CodeAnalysis.CSharp }
$opts=[Microsoft.CodeAnalysis.CSharp.CSharpParseOptions]::new([Microsoft.CodeAnalysis.CSharp.LanguageVersion]::CSharp5)
$enc=[Text.Encoding]::UTF8
$trees=@()
foreach($f in 'src/Core.cs','src/Indexer.cs','src/SwWriter.cs','src/Preview.cs','src/Conferencia.cs','src/Xlsx.cs','src/Email.cs','src/Ui.cs'){ $trees+=[Microsoft.CodeAnalysis.CSharp.CSharpSyntaxTree]::ParseText([IO.File]::ReadAllText((Resolve-Path $f)),$opts,$f,$enc) }
$refs=@()
foreach($r in 'mscorlib','System','System.Core','System.Xml','System.Drawing','System.Windows.Forms','System.IO.Compression'){ $refs+=[Microsoft.CodeAnalysis.MetadataReference]::CreateFromFile("$refDir/$r.dll") }
$co=[Microsoft.CodeAnalysis.CSharp.CSharpCompilationOptions]::new([Microsoft.CodeAnalysis.OutputKind]::WindowsApplication)
$co=$co.WithPlatform([Microsoft.CodeAnalysis.Platform]::AnyCpu).WithOptimizationLevel([Microsoft.CodeAnalysis.OptimizationLevel]::Release)
$comp=[Microsoft.CodeAnalysis.CSharp.CSharpCompilation]::Create('Monitor',[Microsoft.CodeAnalysis.SyntaxTree[]]$trees,[Microsoft.CodeAnalysis.MetadataReference[]]$refs,$co)
$ico=[IO.File]::OpenRead((Resolve-Path 'src/monitor.ico'))
$res=$comp.CreateDefaultWin32Resources($true,$false,$null,$ico)
New-Item -ItemType Directory -Force out | Out-Null
$fs=[IO.File]::Create((Join-Path (Get-Location) 'out/Monitor.exe'))
$r=$comp.Emit($fs,$null,$null,$res)
$fs.Close(); $ico.Close()
$r.Diagnostics | ? { $_.Severity -ne 'Hidden' } | % { $_.ToString() }
"SUCESSO=" + $r.Success
