# Peca.ps1 - DetalharPeca: classifica a peça e chama o detalhamento do tipo
# Carregado pelo DetalharSW.ps1 (dot-source). Não rodar sozinho.

function DetalharPeca($caminho, $peca) {
    $script:xfCache = @{}; $script:xfModo = @{}   # nomes de vista se repetem entre desenhos
    $script:chamadas = @()
    $cod = Codigo $caminho
    # 1) análise rápida: qual é o tipo da peça (regras em Nucleo\Classificar.ps1)
    ValidarPropriedades $peca $caminho   # DESCRIÇÃO, ACABAMENTO e um processo preenchidos (senão avisa e não detalha)
    $cls = ClassificarPeca $caminho $peca
    if ($cls.Laser) { ConferirEspessuraLaser $peca $caminho }   # laser: espessura da descrição = espessura do 3D
    $script:classeAtual = $cls
    $script:tipoPeca = $cls.Classe + " " + $cls.Fluxo
    # saídas: pelo botão do Monitor vale o que o usuário marcou (desenho / PDF / DXF);
    # arrastando sobre o DETALHAR.bat segue a regra do setor (laser: desenho + PDF + DXF; demais: desenho + PDF)
    if ($Modo -ne "gerar") { $script:FazPdf = $true; $script:FazDxf = [bool]$cls.FazDxf }
    $desc = $cls.Descricao; $laser = $cls.Laser; $chapa = $cls.Chapa
    $destDir = PastaDestino $caminho
    $drwPath = Join-Path $destDir "$cod.SLDDRW"
    if ((Test-Path $drwPath) -and -not $Sobrescrever) { Log "   Já existe $drwPath (Sobrescrever=não). Pulando criação." "Yellow"; Relatorio $caminho "peça" "detalhar" "pulado" "desenho já existe"; return }
    $b = $cls.Caixa
    $script:caixaPeca = $b
    $script:espessura = $cls.Espessura
    $X = $cls.X; $Y = $cls.Y; $Z = $cls.Z
    try { $real = [string](X $peca "GetPathName"); if ($real) { $caminho = $real } } catch { }
    $mx = $cls.Maior
    $mn = $cls.Menor
    # 2) detalhamento do tipo
    if ($cls.Fluxo -eq "metalon") {
        # METALON / METALOM: detalhamento próprio (padrão 02123721) - Tipos\Metalon.ps1
        Log "   Metalon: vista lateral com quebras + perfil + isométrica" "DarkGray"
        $laser = $false
        $dm = DetalharMetalon $caminho $peca $X $Y $Z $desc
    } else {
    # chapa / torneada / usinada / genérica: fluxo padrão abaixo (usinada com muitos furos -> Tipos\UsinadaTabelaFuros.ps1)
    $plana = $cls.Plana
    if ($chapa -and $script:espessura -gt 0) {
        Log ("   Chapa metálica {0} (menor medida {1:N1} mm, espessura {2:N1} mm)" -f $(if ($plana) { "PLANA - sem dobra" } else { "DOBRADA" }), ($mn * 1000), ($script:espessura * 1000)) "DarkGray"
    }
    $nomesFrente = @($VistaFrontal, "*Frontal", "*Front")
    $script:planaAtual = $plana
    $usinPrisma = $cls.UsinPrisma
    $script:usinPrisma = $usinPrisma
    if ($usinPrisma) {
        if ($mn -eq $Z) { $nomesFrente = @("*Frontal", "*Front"); $pl = "frontal" }
        elseif ($mn -eq $Y) { $nomesFrente = @("*Superior", "*Top"); $pl = "superior" }
        else { $nomesFrente = @("*Esquerda", "*Left"); $pl = "lateral" }
        Log "   Peça usinada: vista principal = $pl (face maior) + vista de baixo + isométrica" "DarkGray"
    }
    if ($plana) {
        if ($mn -eq $Z) { $nomesFrente = @("*Frontal", "*Front") ; $pl = "frontal" }
        elseif ($mn -eq $Y) { $nomesFrente = @("*Superior", "*Top"); $pl = "superior" }
        else { $nomesFrente = @("*Esquerda", "*Left"); $pl = "lateral" }
        Log ("   Chapa plana (espessura {0:N1} mm): vista principal = {1} (face maior)" -f ($mn * 1000), $pl) "DarkGray"
    }
    $dm = NovoDesenho
    $front = VistaModelo $dm $caminho $nomesFrente 0.08 0.15
    if (-not $front) { throw "não consegui criar a vista frontal" }
    # peça comprida em pé: gira a principal antes de projetar as outras (chapa plana: sempre deitada, lado maior na horizontal)
    # chapa dobrada (1.2): comprimento também na horizontal (ex.: 02204262, comprida no eixo Y do modelo)
    if ($plana) { Deitar $dm $front 1.02 } elseif ($usinPrisma -or ($chapa -and $laser)) { Deitar $dm $front }
    # usinada com muitos furos: padrão ProEstamp com TABELA DE FUROS (ex.: 02124106)
    $tabelaFuros = $false
    if ($usinPrisma) {
        Rebuild $dm; $script:xfCache = @{}; $script:xfModo = @{}
        $nfur = 0; try { $nfur = (FurosDaVista $front).Count } catch { }
        if ($nfur -ge $FurosParaTabela) { $tabelaFuros = $true; $script:tipoPeca = "usinada-tabela-furos"; Log "   Usinada com $nfur furos: detalhamento com tabela de furos (5 vistas + isométrica)" "DarkGray" }
    }
    if ($tabelaFuros) { DetalharUsinagemTabela $dm $front $caminho $peca } else {
    $left = $null; $top = $null; $iso = $null; $flat = $null
    if (-not $usinPrisma) { try { Selecionar $dm $front | Out-Null; $left = X $dm "CreateUnfoldedViewAt3" 0.20 0.15 0.0 $false } catch { Log "   (vista lateral falhou: $($_.Exception.Message))" "DarkYellow" } }
    $redonda = (-not $laser) -and (([math]::Abs($Y - $Z) -lt 0.01 * $mx) -or ([math]::Abs($X - $Z) -lt 0.01 * $mx))
    if ($plana) { Log "   Chapa plana: principal + lateral + vista de baixo mostrando a espessura" "DarkGray" }
    if ($redonda -and -not $plana) { Log "   Peça de revolução: sem vista superior (repetiria a frontal)" "DarkGray" }
    else { try { Selecionar $dm $front | Out-Null; $top = X $dm "CreateUnfoldedViewAt3" 0.08 0.07 0.0 $false } catch { Log "   (vista superior falhou: $($_.Exception.Message))" "DarkYellow" } }
    $iso = VistaModelo $dm $caminho @("*Isométrica", "*Isometric") 0.25 0.17
    if ($laser -and $chapa -and -not $plana) {
        try { $flat = X $dm "CreateFlatPatternViewFromModelView3" $caminho (NomeConfig $peca) 0.2 0.07 0.0 $false $false } catch { }
        if (-not $flat) { Log "   Aviso: não criei a vista planificada no desenho." "Yellow" }
    }
    Log ("   Vistas: frontal ok" + $(if ($left) { ", lateral ok" } else { ", SEM lateral" }) + $(if ($top) { ", superior ok" } else { ", SEM superior" }) + $(if ($iso) { ", isométrica ok" } else { ", SEM isométrica" }) + $(if ($flat) { ", planificada ok" } else { "" }))
    foreach ($v in @($front, $left, $top, $flat)) { if ($v) { Modo $v $DispHidden $true } }
    if ($iso) { Modo $iso $DispShaded $true }
    # vista principal = a que mostra o comprimento maior na horizontal (como nos detalhamentos da ProEstamp)
    $cand = @(@($front, "*Frontal", "frontal"), @($left, "*Esquerda", "lateral"), @($top, "*Superior", "superior")) | Where-Object { $_[0] }
    $melhor = $cand | Sort-Object { -(Contorno $_[0]).w } | Select-Object -First 1
    if (-not $plana -and -not $usinPrisma -and $melhor[2] -ne "frontal" -and (Contorno $melhor[0]).w -gt 1.5 * (Contorno $front).w) {
        Log "   Vista principal trocada para $($melhor[1]) (comprimento na horizontal)" "DarkGray"
        foreach ($v in @($front, $left, $top)) { if ($v) { try { Selecionar $dm $v | Out-Null; X $dm "EditDelete" | Out-Null } catch { } } }
        $front = VistaModelo $dm $caminho @($melhor[1]) 0.08 0.15
        if (-not $front) { throw "não consegui recriar a vista principal" }
        Deitar $dm $front
        $left = $null; $top = $null
        try { Selecionar $dm $front | Out-Null; $left = X $dm "CreateUnfoldedViewAt3" 0.20 0.15 0.0 $false } catch { }
        if (-not $redonda) { try { Selecionar $dm $front | Out-Null; $top = X $dm "CreateUnfoldedViewAt3" 0.08 0.07 0.0 $false } catch { } }
        foreach ($v in @($front, $left, $top)) { if ($v) { Modo $v $DispHidden $true } }
        Rebuild $dm
    }
    # 1.2/1.2.1: vista principal = PERFIL DA DOBRA (mostra como a peça foi dobrada; ex.: 02124099), a face da chapa
    # vai embaixo dela; a lateral só repetiria a largura (a planificada mostra a aba de frente) e sai
    $script:perfilPrincipal = $false
    if ($laser -and $chapa -and -not $plana -and $flat) {
        try {
            Rebuild $dm; $script:xfCache = @{}; $script:xfModo = @{}
            $cands = @(@($front, $left, $top) | Where-Object { $_ } | ForEach-Object { ,@($_, (ArcosDeDobra $_)) })
            $pf = @($cands | Sort-Object { -$_[1] })[0]
            if ($pf -and $pf[1] -gt 0) {
                if (-not [object]::ReferenceEquals($pf[0], $front)) {
                    $nmP = OrientacaoDaVista $pf[0]
                    if ($nmP) {
                        Log "   Vista principal = perfil da dobra ($nmP)" "DarkGray"
                        foreach ($v in @($front, $left, $top)) { if ($v) { try { Selecionar $dm $v | Out-Null; X $dm "EditDelete" | Out-Null } catch { } } }
                        $front = VistaModelo $dm $caminho @($nmP) 0.08 0.15
                        if (-not $front) { throw "não consegui recriar a vista principal (perfil)" }
                        Deitar $dm $front
                        $left = $null; $top = $null
                        try { Selecionar $dm $front | Out-Null; $left = X $dm "CreateUnfoldedViewAt3" 0.20 0.15 0.0 $false } catch { }
                        try { Selecionar $dm $front | Out-Null; $top = X $dm "CreateUnfoldedViewAt3" 0.08 0.07 0.0 $false } catch { }
                        foreach ($v in @($front, $left, $top)) { if ($v) { Modo $v $DispHidden $true } }
                        Rebuild $dm; $script:xfCache = @{}; $script:xfModo = @{}
                    }
                }
                if ((ArcosDeDobra $front) -gt 0) {
                    $script:perfilPrincipal = $true
                    # lateral: sai, a não ser no 1.2.1 com furos que só ela mostra
                    $furosL = 0; if ($left -and $cls.Usinagem) { try { $furosL = (FurosDaVista $left).Count } catch { } }
                    if ($left -and $furosL -eq 0) { try { Selecionar $dm $left | Out-Null; X $dm "EditDelete" | Out-Null; $left = $null; Rebuild $dm; Log "   Dobrada: sem vista lateral (perfil + face + planificada mostram tudo)" "DarkGray" } catch { } }
                }
            }
        } catch { Log "   (vista de perfil: $($_.Exception.Message))" "DarkYellow" }
    }
    Deitar $dm $flat
    AlinharPlanificada $dm $front $flat
    $of0 = Contorno $front
    $longa = ($of0.w -gt 2.5 * $of0.h)
    # perfil como principal: arranjo normal (perfil em cima, face embaixo, isométrica em cima à direita, planificada embaixo
    # à direita - 02124099, perfil 2,5x mais largo que alto); só empilha se for MUITO comprida (02204262, 676 x 27)
    if ($script:perfilPrincipal -and $of0.w -le 4 * $of0.h) { $longa = $false }
    if ($longa) { Log "   Disposição para peça longa (vistas empilhadas)" "DarkGray" }
    # chapa dobrada longa: principal + vista de baixo + planificada já mostram tudo; a lateral só repetiria a largura
    # (e ficaria sem cota - nenhuma vista pode ficar sem cota)
    if ($longa -and $left -and $top -and $laser -and $chapa -and -not $plana) {
        try { Selecionar $dm $left | Out-Null; X $dm "EditDelete" | Out-Null; $left = $null; Rebuild $dm; Log "   Peça longa dobrada: sem vista lateral (largura cotada na vista de baixo)" "DarkGray" } catch { }
    }

    # folga em volta das vistas para as cotas: maior quando entram as cotas do modelo (usinagem)
    $script:MargemCotas = if ($laser -and -not $cls.Usinagem) { 0.010 } else { 0.018 }
    if ($usinPrisma) { $script:MargemCotas = 0.011; $Gap = 0.020 }   # usinada: cotas só em volta da principal, vistas mais próximas = escala maior
    elseif ($plana) { $script:MargemCotas = 0.010; $Gap = 0.014 }    # chapa plana: vistas da espessura são finas, ficam perto da principal = escala maior
    elseif ($longa -and $laser -and $chapa) { $Gap = 0.020 }          # dobrada longa: vistas empilhadas mais próximas = escala maior (02204262)
    # escala inicial pelo tamanho REAL das vistas (já com a orientação escolhida), sem contar a isométrica;
    # depois desce escala por escala até caber, tentando 3 arranjos: normal, isométrica menor e vistas empilhadas
    $esc0 = 1.0; try { $esc0 = [double](XG $front "ScaleDecimal") } catch { }
    if ($esc0 -le 0) { $esc0 = 1.0 }
    $cF = Contorno $front
    $lf = $cF.w; $hf = $cF.h
    if ($left) { $lf += (Contorno $left).w }
    if ($top) { $hf += (Contorno $top).h }
    if ($flat) { $lf = [math]::Max($lf, $cF.w + (Contorno $flat).w) }
    if ($longa) {
        # vistas empilhadas: largura = a maior linha; altura = soma das vistas (a planificada vai embaixo, não ao lado)
        $lf = $cF.w; if ($left) { $lf += (Contorno $left).w }
        if ($top) { $lf = [math]::Max($lf, (Contorno $top).w) }
        if ($flat) { $lf = [math]::Max($lf, (Contorno $flat).w); $hf += (Contorno $flat).h }
    }
    $lf = $lf / $esc0; $hf = $hf / $esc0
    $i0 = EscalaInicial $lf $hf
    if ($i0 -gt 0) { $i0-- }   # otimista: a disposição confere se coube
    $idx11 = 3   # posição de 1:1 na lista de escalas
    if ($mx -gt 0.040 -and $i0 -lt $idx11) { $i0 = $idx11 }
    $arranjos = if ($longa) { @("longa", "longa-iso") } else { @("normal", "iso", "longa", "longa-iso") }
    $ok = $false
    for ($i = $i0; $i -lt $Escalas.Count -and -not $ok; $i++) {
        $num = $Escalas[$i][0]; $den = $Escalas[$i][1]
        DefinirEscala $dm $num $den
        foreach ($arr in $arranjos) {
            $fi = switch ($arr) { "normal" { $FatorIso } "iso" { $FatorIso * 0.5 } "longa" { 0.35 } default { 0.2 } }
            if ($iso) { try { XS $iso "UseSheetScale" $false } catch { try { XS $iso "UseSheetScale" 0 } catch { } }; try { XS $iso "ScaleDecimal" (($num / $den) * $fi) } catch { } }
            Rebuild $dm
            $cabe = if ($arr -like "longa*") { LayoutPecaLonga $dm $front $left $top $iso $flat } else { LayoutPeca $dm $front $left $top $iso $flat }
            if ($cabe) { $ok = $true; Log "   Escala $num`:$den (arranjo $arr)"; break }
        }
    }
    if (-not $ok) { Log "   Aviso: as vistas não couberam perfeitamente; confira a disposição." "Yellow" }
    else { Centralizar $dm @($front, $left, $top, $flat, $iso) $AreaB }
    EspalharNotasDobra $dm $flat
    $script:isoAtual = $iso

    $usinagem = $cls.Usinagem
    Log "   Processo: $(if ($laser) { 'laser' } else { 'fabricada' })$(if ($usinagem) { ' + usinagem' } else { '' }) (classe $($cls.Classe))"
    if ($InserirCotas -and $laser -and -not $usinPrisma) {
        # 1.1 / 1.2 (e 1.2.1): cotas totais; furos sem rosca/rebaixo e sem usinagem NÃO são cotados
        try { CotasLaser $dm $front $left $top $flat } catch { Log "   Aviso: cotas de laser falharam ($($_.Exception.Message))" "Yellow" }
        # vista dos furos: a principal; com o perfil da dobra como principal, a vista com mais furos (face da chapa)
        $vFuros = $front
        if ($script:perfilPrincipal) {
            $mf = -1
            foreach ($vv in @($front, $top, $left)) { if ($vv) { $nf = 0; try { $script:xfCache = @{}; $script:xfModo = @{}; $nf = (FurosDaVista $vv).Count } catch { }; if ($nf -gt $mf) { $mf = $nf; $vFuros = $vv } } }
            $script:xfCache = @{}; $script:xfModo = @{}
        }
        # furos roscados ou com rebaixo: chamada de furo (detalhe do furo)
        if ($cls.Furos.Roscados + $cls.Furos.Rebaixos -gt 0) {
            try { ChamadasFuro $dm $vFuros | Out-Null } catch { Log "   Aviso: chamadas de furo falharam ($($_.Exception.Message))" "Yellow" }
        }
        # 1.2.1: dobrada com usinagem -> posição dos furos também
        if ($usinagem) {
            try { CotasPosicaoFuros $dm $vFuros | Out-Null } catch { Log "   Aviso: cotas dos furos falharam ($($_.Exception.Message))" "Yellow" }
            # oblongos (rasgos) em qualquer vista dobrada: raio, comprimento e posição
            $nob = 0
            foreach ($vo in @($front, $left, $top)) { if ($vo) { try { $script:xfCache = @{}; $script:xfModo = @{}; $nob += CotasOblongo $dm $vo } catch { Log "   (oblongo: $($_.Exception.Message))" "DarkYellow" } } }
            if ($nob -gt 0) { Log "   Oblongo(s): $nob cota(s)" "DarkGray" }
        }
    } elseif ($InserirCotas -and $usinPrisma) {
        try { CotasUsinagem $dm $front $top } catch { Log "   Aviso: cotas de usinagem falharam ($($_.Exception.Message))" "Yellow" }
    } elseif ($InserirCotas) {
        try {
            X $dm "ClearSelection2" $true | Out-Null
            $ann = X $dm "InsertModelAnnotations3" 0 ($InsDims + $InsHoleCallout) $true $false $false $false
            $n = 0; if ($ann) { $n = @($ann).Count }
            Log "   Cotas do modelo inseridas (peça com usinagem): $n"
        } catch { Log "   Aviso: não inseri cotas ($($_.Exception.Message))" "Yellow" }
    }
    }   # fim: sem tabela de furos
    }   # fim: peça que não é metalon
    CentralizarTextosCotas $dm         # valor de cada cota no meio da linha de cota
    AvisosDesenho $dm @($cls.Avisos)   # balões vermelhos (ex.: usinagem -> acabamento e precisões)
    TrocarDesenhista $dm
    Rebuild $dm

    AtivarDesenho $dm | Out-Null; try { X $dm "ViewZoomtofit2" | Out-Null } catch { }   # folha inteira na tela para conferir
    SalvarComo $dm $drwPath $SaveSilent
    Log "   Desenho: $drwPath" "Green"
    $pdf = Join-Path $destDir "$cod.PDF"
    $pdfMsg = ""
    if ($script:FazPdf) { if (PdfProtegido $destDir $cod) { $pdfMsg = " (PDF mantido: existe APR)" } else { SalvarComo $dm $pdf ($SaveSilent + $SaveCopy); Log "   PDF: $pdf" "Green"; $pdfMsg = " + PDF" } }
    $dxfMsg = ""
    $fazDxf = if ($script:FazDxf -eq "auto") { $laser } else { [bool]$script:FazDxf }
    if ($fazDxf) { $dxf = Join-Path $destDir "$cod.DXF"; GerarDxf $caminho $peca $dxf $desc; Log "   DXF: $dxf" "Green"; AbrirAutoCAD $dxf; $dxfMsg = " + DXF" }
    if ($FecharDesenho) { Fechar $dm }
    Relatorio $caminho "peça" "detalhar" "ok" ("desenho" + $pdfMsg + $dxfMsg)
}
