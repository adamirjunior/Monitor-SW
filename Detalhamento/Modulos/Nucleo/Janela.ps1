# Janela.ps1 - janelinha "Gerando detalhamento" (sempre por cima, canto inferior direito) com animação em movimento
# e a etapa atual (última linha do log). Roda numa thread própria para continuar animando enquanto o SolidWorks trabalha.
# Carregado pelo DetalharSW.ps1 (dot-source). Não rodar sozinho.

$script:ui = $null
$script:uiPs = $null
$MostrarJanela = Sim (C "JanelaGerando" "sim")

function AbrirJanelaStatus {
    if (-not $MostrarJanela -or $script:ui) { return }
    try {
        $script:ui = [hashtable]::Synchronized(@{ Texto = "Iniciando..."; Peca = ""; Fechar = $false; Erro = $false })
        $rs = [runspacefactory]::CreateRunspace()
        $rs.ApartmentState = "STA"; $rs.ThreadOptions = "ReuseThread"; $rs.Open()
        $rs.SessionStateProxy.SetVariable("ui", $script:ui)
        $ps = [powershell]::Create(); $ps.Runspace = $rs
        [void]$ps.AddScript({
            Add-Type -AssemblyName System.Windows.Forms, System.Drawing
            [System.Windows.Forms.Application]::EnableVisualStyles()
            $fundo = [System.Drawing.Color]::FromArgb(24, 33, 43)
            $cor = [System.Drawing.Color]::FromArgb(79, 179, 209)
            $f = New-Object System.Windows.Forms.Form
            $f.FormBorderStyle = "None"; $f.TopMost = $true; $f.ShowInTaskbar = $false; $f.StartPosition = "Manual"
            $f.Size = New-Object System.Drawing.Size(380, 104); $f.BackColor = $fundo
            $wa = [System.Windows.Forms.Screen]::PrimaryScreen.WorkingArea
            $f.Location = New-Object System.Drawing.Point(($wa.Right - $f.Width - 16), ($wa.Bottom - $f.Height - 16))
            $t = New-Object System.Windows.Forms.Label
            $t.Text = "Gerando detalhamento"; $t.ForeColor = [System.Drawing.Color]::White
            $t.Font = New-Object System.Drawing.Font("Segoe UI", 12, [System.Drawing.FontStyle]::Bold)
            $t.Location = New-Object System.Drawing.Point(16, 10); $t.AutoSize = $true
            $p = New-Object System.Windows.Forms.Label
            $p.ForeColor = $cor; $p.Font = New-Object System.Drawing.Font("Segoe UI", 9.5, [System.Drawing.FontStyle]::Bold)
            $p.Location = New-Object System.Drawing.Point(16, 36); $p.Size = New-Object System.Drawing.Size(350, 18); $p.AutoEllipsis = $true
            $s = New-Object System.Windows.Forms.Label
            $s.ForeColor = [System.Drawing.Color]::FromArgb(160, 175, 190); $s.Font = New-Object System.Drawing.Font("Segoe UI", 8.5)
            $s.Location = New-Object System.Drawing.Point(16, 56); $s.Size = New-Object System.Drawing.Size(350, 18); $s.AutoEllipsis = $true
            # trilho + bloco que corre de um lado para o outro
            $trilho = New-Object System.Windows.Forms.Panel
            $trilho.BackColor = [System.Drawing.Color]::FromArgb(42, 55, 66); $trilho.Location = New-Object System.Drawing.Point(16, 84); $trilho.Size = New-Object System.Drawing.Size(348, 6)
            $bloco = New-Object System.Windows.Forms.Panel
            $bloco.BackColor = $cor; $bloco.Size = New-Object System.Drawing.Size(90, 6); $bloco.Location = New-Object System.Drawing.Point(-90, 0)
            $trilho.Controls.Add($bloco)
            $f.Controls.AddRange(@($t, $p, $s, $trilho))
            $script:pontos = 0; $script:tick = 0
            $tm = New-Object System.Windows.Forms.Timer; $tm.Interval = 30
            $tm.Add_Tick({
                $x = $bloco.Left + 6; if ($x -gt $trilho.Width) { $x = -$bloco.Width }; $bloco.Left = $x
                $script:tick++
                if ($script:tick % 12 -eq 0) { $script:pontos = ($script:pontos + 1) % 4; $t.Text = "Gerando detalhamento" + ("." * $script:pontos) }
                $p.Text = [string]$ui.Peca; $s.Text = [string]$ui.Texto
                if ($ui.Erro) { $bloco.BackColor = [System.Drawing.Color]::FromArgb(255, 107, 107) }
                if ($ui.Fechar) { $tm.Stop(); $f.Close() }
            })
            $f.Add_Shown({ $tm.Start() })
            [System.Windows.Forms.Application]::Run($f)
        })
        $script:uiPs = $ps
        [void]$ps.BeginInvoke()
    } catch { $script:ui = $null; Log "   (janela de status não abriu: $($_.Exception.Message))" "DarkYellow" }
}
function StatusPeca([string]$texto) { if ($script:ui) { $script:ui.Peca = $texto } }
function FecharJanelaStatus([bool]$erro = $false) {
    if (-not $script:ui) { return }
    try {
        if ($erro) { $script:ui.Erro = $true; $script:ui.Texto = "Terminou com erro - veja o aviso do Monitor / log.txt"; Start-Sleep -Milliseconds 1500 }
        $script:ui.Fechar = $true
        Start-Sleep -Milliseconds 400
    } catch { }
    $script:ui = $null
}
