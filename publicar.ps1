<#
  publicar.ps1 - compila o Monitor SW no PC e publica SO o necessario no servidor.
  Uso (PowerShell na pasta do repositorio):
      .\publicar.ps1                    # publica em X:\MonitorSW
      .\publicar.ps1 -Servidor Y:\Pasta # outro destino
      .\publicar.ps1 -SoGerador         # so o DetalharSW.ps1 e templates (sem recompilar)
  Codigo-fonte, testes, CLAUDE.md e este script NUNCA vao para o servidor.
#>
param(
    [string]$Servidor = 'X:\MonitorSW',
    [switch]$SoGerador,
    [switch]$SemAssinar
)
$ErrorActionPreference = 'Stop'
$raiz = $PSScriptRoot
function Passo($t) { Write-Host "`n== $t" -ForegroundColor Cyan }

if (-not (Test-Path $Servidor)) { throw "Servidor nao encontrado: $Servidor" }

# 1) verifica o gerador e todos os modulos (sintaxe) antes de qualquer copia
Passo 'Verificando DetalharSW.ps1 e Modulos'
$gerador = Join-Path $raiz 'Detalhamento\DetalharSW.ps1'
$modulos = @(Get-ChildItem (Join-Path $raiz 'Detalhamento\Modulos') -Recurse -Filter *.ps1)
foreach ($f in @($gerador) + @($modulos | % FullName)) {
    $tok = $null; $err = $null
    [System.Management.Automation.Language.Parser]::ParseFile($f, [ref]$tok, [ref]$err) | Out-Null
    if ($err.Count) { $err | % { Write-Host $_ -ForegroundColor Red }; throw "$f com erro de sintaxe - nada foi publicado." }
}
Write-Host ("OK (gerador + {0} modulos)" -f $modulos.Count)

# 2) compila em Release com o MSBuild do Visual Studio
$exe = $null
if (-not $SoGerador) {
    Passo 'Compilando (Release)'
    $vswhere = "${env:ProgramFiles(x86)}\Microsoft Visual Studio\Installer\vswhere.exe"
    if (-not (Test-Path $vswhere)) { throw 'Visual Studio nao encontrado (instale o Visual Studio 2022 Community).' }
    $msbuild = & $vswhere -latest -requires Microsoft.Component.MSBuild -find 'MSBuild\**\Bin\MSBuild.exe' | Select-Object -First 1
    if (-not $msbuild) { throw 'MSBuild nao encontrado.' }
    & $msbuild (Join-Path $raiz 'Monitor.sln') /p:Configuration=Release /m /v:minimal /nologo
    if ($LASTEXITCODE) { throw 'Falha na compilacao - nada foi publicado.' }
    $exe = Join-Path $raiz 'out\Release\Monitor.exe'
    Write-Host ("Versao " + (Get-Item $exe).VersionInfo.FileVersion)
}

# 3) assinatura digital (se houver certificado de assinatura de codigo no Windows)
if (-not $SemAssinar) {
    $cert = Get-ChildItem Cert:\CurrentUser\My -CodeSigningCert -ErrorAction SilentlyContinue | Sort-Object NotAfter -Descending | Select-Object -First 1
    if ($cert) {
        Passo "Assinando com $($cert.Subject)"
        $alvos = @($gerador) + @($modulos | % FullName); if ($exe) { $alvos += $exe }
        foreach ($a in $alvos) { Set-AuthenticodeSignature $a $cert -HashAlgorithm SHA256 | Out-Null; Write-Host "assinado: $a" }
    } else { Write-Host "`n(sem certificado de assinatura - publicando sem assinar)" -ForegroundColor Yellow }
}

# 4) copia so o necessario
Passo "Publicando em $Servidor"
$det = Join-Path $Servidor 'Detalhamento'
New-Item -ItemType Directory -Force $det | Out-Null
$copias = @(
    @{ de = $gerador; para = $det },
    @{ de = (Join-Path $raiz 'Detalhamento\DETALHAR.bat'); para = $det },
    @{ de = (Join-Path $raiz 'Detalhamento\EXPORTAR_PDF_DXF.bat'); para = $det },
    @{ de = (Join-Path $raiz 'Detalhamento\LEIA-ME.txt'); para = $det }
)
# detalhamento.ini e templates: so copia se ainda nao existir no servidor (as configuracoes do servidor mandam)
foreach ($f in Get-ChildItem (Join-Path $raiz 'Detalhamento') -Include *.ini,*.sldbomtbt,*.sldholtbt) {
    if (-not (Test-Path (Join-Path $det $f.Name))) { $copias += @{ de = $f.FullName; para = $det } }
}
# modulos do gerador (Nucleo\ e Tipos\): espelha a pasta inteira
$modDest = Join-Path $det 'Modulos'
foreach ($m in $modulos) {
    $rel = $m.FullName.Substring((Join-Path $raiz 'Detalhamento\Modulos').Length + 1)
    $alvo = Join-Path $modDest $rel
    New-Item -ItemType Directory -Force (Split-Path $alvo) | Out-Null
    Copy-Item $m.FullName $alvo -Force
}
Write-Host ("copiado: Modulos ({0} arquivos)" -f $modulos.Count)
foreach ($c in $copias) { if (Test-Path $c.de) { Copy-Item $c.de $c.para -Force; Write-Host ("copiado: " + (Split-Path $c.de -Leaf)) } }
if ($exe) {
    # o Monitor aberto nos PCs troca sozinho para a versao nova em ~20 s
    Copy-Item $exe (Join-Path $Servidor 'Monitor_atualizacao.exe') -Force
    Write-Host 'copiado: Monitor_atualizacao.exe (atualizacao automatica)'
}

# 5) aviso se sobrou codigo-fonte no servidor
$sobra = Get-ChildItem $Servidor -Recurse -Include *.cs,*.csproj,*.sln,build.ps1,publicar.ps1,CLAUDE.md -ErrorAction SilentlyContinue
if ($sobra) { Write-Host "`nAtencao: ha arquivos de codigo-fonte no servidor:" -ForegroundColor Yellow; $sobra | % { Write-Host "  $($_.FullName)" } }
Write-Host "`nPublicacao concluida." -ForegroundColor Green
