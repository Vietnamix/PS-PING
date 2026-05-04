# ============================================================
# SCRIPT  : Novo Nordisk Ping Monitor
# VERSION : 3.1
# AUTEUR  : Novo Nordisk IT - EGUI
# DATE    : 2025
# DESCRIPTION : Outil de monitoring de ping en temps réel
#               avec interface graphique Windows Forms.
#               Permet de visualiser la latence réseau,
#               les timeouts, les statistiques et l'historique
#               complet des pings vers une cible définie.
# ============================================================

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

# --- Configuration initiale ---
$Target      = "NPSQLGITOFRCH02"
$MaxPoints   = 60
$Interval    = 1000
$StartTime   = Get-Date
$IconPath    = ""

# Historique complet
$allPingData  = New-Object System.Collections.Generic.List[int]
$allPingTimes = New-Object System.Collections.Generic.List[datetime]
$scrollOffset = 0

$script:liveMode = $true

# Hauteurs panel
$panelExpanded  = 155
$panelCollapsed = 42

# ============================================================
# --- Fenêtre principale ---
# ============================================================
$form = New-Object System.Windows.Forms.Form
$form.Text            = "Novo Nordisk Ping Monitor v3.1 - $Target"
$form.Size            = New-Object System.Drawing.Size(1000, 500)
$form.BackColor       = [System.Drawing.Color]::FromArgb(30, 30, 30)
$form.StartPosition   = "CenterScreen"
$form.FormBorderStyle = "Sizable"
$form.MinimumSize     = New-Object System.Drawing.Size(600, 280)

# ✅ Chargement icône sans Test-Path (pipeline-free)
if ($IconPath -ne "") {
    try {
        $iconFile = [System.IO.File]::Exists($IconPath)
        if ($iconFile) {
            $form.Icon = New-Object System.Drawing.Icon($IconPath)
        }
    } catch {}
}

# ============================================================
# --- Panel de contrôle (bas) ---
# ============================================================
$panelControl           = New-Object System.Windows.Forms.Panel
$panelControl.BackColor = [System.Drawing.Color]::FromArgb(45, 45, 45)
$panelControl.Dock      = [System.Windows.Forms.DockStyle]::Bottom
$panelControl.Height    = $panelExpanded
$form.Controls.Add($panelControl)

# ============================================================
# --- Scrollbar horizontale sombre ---
# ============================================================
$scrollPanel           = New-Object System.Windows.Forms.Panel
$scrollPanel.BackColor = [System.Drawing.Color]::FromArgb(20, 20, 20)
$scrollPanel.Height    = 18
$scrollPanel.Dock      = [System.Windows.Forms.DockStyle]::None
$form.Controls.Add($scrollPanel)

$scrollBar             = New-Object System.Windows.Forms.HScrollBar
$scrollBar.Minimum     = 0
$scrollBar.Maximum     = 0
$scrollBar.Value       = 0
$scrollBar.SmallChange = 1
$scrollBar.LargeChange = 10
$scrollBar.Dock        = [System.Windows.Forms.DockStyle]::Fill
$scrollBar.BackColor   = [System.Drawing.Color]::FromArgb(20, 20, 20)
$scrollPanel.Controls.Add($scrollBar)

# ============================================================
# --- Labels entête ---
# ============================================================
$lblTitle           = New-Object System.Windows.Forms.Label
$lblTitle.Text      = "Novo Nordisk Ping Monitor v3.1 — $Target"
$lblTitle.ForeColor = [System.Drawing.Color]::White
$lblTitle.Font      = New-Object System.Drawing.Font("Segoe UI", 12, [System.Drawing.FontStyle]::Bold)
$lblTitle.Location  = New-Object System.Drawing.Point(10, 8)
$lblTitle.Size      = New-Object System.Drawing.Size(620, 28)
$lblTitle.BackColor = [System.Drawing.Color]::Transparent
$form.Controls.Add($lblTitle)

$lblUptime           = New-Object System.Windows.Forms.Label
$lblUptime.Text      = ""
$lblUptime.ForeColor = [System.Drawing.Color]::LightGreen
$lblUptime.Font      = New-Object System.Drawing.Font("Consolas", 11, [System.Drawing.FontStyle]::Bold)
$lblUptime.Size      = New-Object System.Drawing.Size(180, 24)
$lblUptime.BackColor = [System.Drawing.Color]::Transparent
$lblUptime.TextAlign = [System.Drawing.ContentAlignment]::MiddleRight
$lblUptime.Anchor    = (
    [System.Windows.Forms.AnchorStyles]::Top -bor
    [System.Windows.Forms.AnchorStyles]::Right
)
$form.Controls.Add($lblUptime)

$lblStats           = New-Object System.Windows.Forms.Label
$lblStats.ForeColor = [System.Drawing.Color]::LightGreen
$lblStats.Font      = New-Object System.Drawing.Font("Consolas", 9)
$lblStats.Location  = New-Object System.Drawing.Point(10, 42)
$lblStats.Size      = New-Object System.Drawing.Size(970, 18)
$lblStats.BackColor = [System.Drawing.Color]::Transparent
$form.Controls.Add($lblStats)

# --- Canvas ---
$canvas           = New-Object System.Windows.Forms.PictureBox
$canvas.BackColor = [System.Drawing.Color]::FromArgb(20, 20, 20)
$canvas.Anchor    = (
    [System.Windows.Forms.AnchorStyles]::Top    -bor
    [System.Windows.Forms.AnchorStyles]::Bottom -bor
    [System.Windows.Forms.AnchorStyles]::Left   -bor
    [System.Windows.Forms.AnchorStyles]::Right
)
$form.Controls.Add($canvas)

# ============================================================
# Repositionnement dynamique
# ============================================================
function Update-CanvasBounds {
    $topOffset   = 66
    $bottomSpace = $panelControl.Height + $scrollPanel.Height + 6

    $canvasHeight = $form.ClientSize.Height - $topOffset - $bottomSpace
    if ($canvasHeight -lt 20) { $canvasHeight = 20 }

    $canvas.Location = New-Object System.Drawing.Point(10, $topOffset)
    $canvas.Size     = New-Object System.Drawing.Size(
        ([math]::Max($form.ClientSize.Width - 20, 10)),
        $canvasHeight
    )

    $scrollPanel.Location = New-Object System.Drawing.Point(
        0,
        ($form.ClientSize.Height - $panelControl.Height - $scrollPanel.Height - 2)
    )
    $scrollPanel.Width = $form.ClientSize.Width

    $lblUptime.Location = New-Object System.Drawing.Point(
        ($form.ClientSize.Width - $lblUptime.Width - 10), 10
    )
}
Update-CanvasBounds

# ============================================================
# --- Boutons panel ---
# ============================================================
$btnToggle                            = New-Object System.Windows.Forms.Button
$btnToggle.Text                       = "Reduire"
$btnToggle.ForeColor                  = [System.Drawing.Color]::White
$btnToggle.BackColor                  = [System.Drawing.Color]::FromArgb(60, 60, 60)
$btnToggle.FlatStyle                  = [System.Windows.Forms.FlatStyle]::Flat
$btnToggle.FlatAppearance.BorderColor = [System.Drawing.Color]::FromArgb(90, 90, 90)
$btnToggle.Font                       = New-Object System.Drawing.Font("Segoe UI", 9, [System.Drawing.FontStyle]::Bold)
$btnToggle.Location                   = New-Object System.Drawing.Point(10, 7)
$btnToggle.Size                       = New-Object System.Drawing.Size(90, 26)
$panelControl.Controls.Add($btnToggle)

$btnLive                            = New-Object System.Windows.Forms.Button
$btnLive.Text                       = ">> Live"
$btnLive.ForeColor                  = [System.Drawing.Color]::White
$btnLive.BackColor                  = [System.Drawing.Color]::FromArgb(30, 90, 40)
$btnLive.FlatStyle                  = [System.Windows.Forms.FlatStyle]::Flat
$btnLive.FlatAppearance.BorderColor = [System.Drawing.Color]::FromArgb(50, 140, 60)
$btnLive.Font                       = New-Object System.Drawing.Font("Segoe UI", 9, [System.Drawing.FontStyle]::Bold)
$btnLive.Location                   = New-Object System.Drawing.Point(110, 7)
$btnLive.Size                       = New-Object System.Drawing.Size(110, 26)
$panelControl.Controls.Add($btnLive)

$btnReset                             = New-Object System.Windows.Forms.Button
$btnReset.Text                        = "Reset"
$btnReset.ForeColor                   = [System.Drawing.Color]::White
$btnReset.BackColor                   = [System.Drawing.Color]::FromArgb(100, 40, 40)
$btnReset.FlatStyle                   = [System.Windows.Forms.FlatStyle]::Flat
$btnReset.FlatAppearance.BorderColor  = [System.Drawing.Color]::FromArgb(150, 60, 60)
$btnReset.Font                        = New-Object System.Drawing.Font("Segoe UI", 9, [System.Drawing.FontStyle]::Bold)
$btnReset.Size                        = New-Object System.Drawing.Size(90, 26)
$btnReset.Anchor                      = (
    [System.Windows.Forms.AnchorStyles]::Top -bor
    [System.Windows.Forms.AnchorStyles]::Right
)
$btnReset.Location = New-Object System.Drawing.Point(($panelControl.Width - 100), 7)
$panelControl.Controls.Add($btnReset)

# ============================================================
# --- Contenu foldable ---
# ============================================================
$panelContent           = New-Object System.Windows.Forms.Panel
$panelContent.BackColor = [System.Drawing.Color]::Transparent
$panelContent.Location  = New-Object System.Drawing.Point(0, 42)
$panelContent.Size      = New-Object System.Drawing.Size(980, 110)
$panelContent.Anchor    = (
    [System.Windows.Forms.AnchorStyles]::Left  -bor
    [System.Windows.Forms.AnchorStyles]::Right -bor
    [System.Windows.Forms.AnchorStyles]::Top
)
$panelControl.Controls.Add($panelContent)

# ---------- Cible ----------
$lblTarget           = New-Object System.Windows.Forms.Label
$lblTarget.Text      = "Cible (IP / Hostname) :"
$lblTarget.ForeColor = [System.Drawing.Color]::White
$lblTarget.Font      = New-Object System.Drawing.Font("Segoe UI", 10)
$lblTarget.Location  = New-Object System.Drawing.Point(10, 4)
$lblTarget.Size      = New-Object System.Drawing.Size(180, 22)
$lblTarget.BackColor = [System.Drawing.Color]::Transparent
$panelContent.Controls.Add($lblTarget)

$txtTarget             = New-Object System.Windows.Forms.TextBox
$txtTarget.Text        = $Target
$txtTarget.ForeColor   = [System.Drawing.Color]::LightSkyBlue
$txtTarget.BackColor   = [System.Drawing.Color]::FromArgb(35, 35, 45)
$txtTarget.Font        = New-Object System.Drawing.Font("Consolas", 10, [System.Drawing.FontStyle]::Bold)
$txtTarget.Location    = New-Object System.Drawing.Point(195, 2)
$txtTarget.Size        = New-Object System.Drawing.Size(220, 24)
$txtTarget.BorderStyle = [System.Windows.Forms.BorderStyle]::FixedSingle
$panelContent.Controls.Add($txtTarget)

$btnApplyTarget                            = New-Object System.Windows.Forms.Button
$btnApplyTarget.Text                       = "Appliquer"
$btnApplyTarget.ForeColor                  = [System.Drawing.Color]::White
$btnApplyTarget.BackColor                  = [System.Drawing.Color]::FromArgb(40, 80, 120)
$btnApplyTarget.FlatStyle                  = [System.Windows.Forms.FlatStyle]::Flat
$btnApplyTarget.FlatAppearance.BorderColor = [System.Drawing.Color]::FromArgb(60, 120, 180)
$btnApplyTarget.Font                       = New-Object System.Drawing.Font("Segoe UI", 9)
$btnApplyTarget.Location                   = New-Object System.Drawing.Point(420, 1)
$btnApplyTarget.Size                       = New-Object System.Drawing.Size(90, 26)
$panelContent.Controls.Add($btnApplyTarget)

$lblSep           = New-Object System.Windows.Forms.Label
$lblSep.BackColor = [System.Drawing.Color]::FromArgb(70, 70, 80)
$lblSep.Location  = New-Object System.Drawing.Point(10, 32)
$lblSep.Size      = New-Object System.Drawing.Size(960, 1)
$panelContent.Controls.Add($lblSep)

# ---------- Intervalle ----------
$lblInterval           = New-Object System.Windows.Forms.Label
$lblInterval.Text      = "Intervalle :"
$lblInterval.ForeColor = [System.Drawing.Color]::White
$lblInterval.Font      = New-Object System.Drawing.Font("Segoe UI", 10)
$lblInterval.Location  = New-Object System.Drawing.Point(10, 38)
$lblInterval.Size      = New-Object System.Drawing.Size(100, 22)
$lblInterval.BackColor = [System.Drawing.Color]::Transparent
$panelContent.Controls.Add($lblInterval)

$lblIntervalVal           = New-Object System.Windows.Forms.Label
$lblIntervalVal.Text      = "${Interval} ms"
$lblIntervalVal.ForeColor = [System.Drawing.Color]::LightSkyBlue
$lblIntervalVal.Font      = New-Object System.Drawing.Font("Consolas", 10, [System.Drawing.FontStyle]::Bold)
$lblIntervalVal.Location  = New-Object System.Drawing.Point(110, 38)
$lblIntervalVal.Size      = New-Object System.Drawing.Size(80, 22)
$lblIntervalVal.BackColor = [System.Drawing.Color]::Transparent
$panelContent.Controls.Add($lblIntervalVal)

$sliderInterval               = New-Object System.Windows.Forms.TrackBar
$sliderInterval.Minimum       = 200
$sliderInterval.Maximum       = 5000
$sliderInterval.Value         = $Interval
$sliderInterval.TickFrequency = 500
$sliderInterval.SmallChange   = 100
$sliderInterval.LargeChange   = 500
$sliderInterval.Location      = New-Object System.Drawing.Point(10, 58)
$sliderInterval.Size          = New-Object System.Drawing.Size(280, 38)
$sliderInterval.BackColor     = [System.Drawing.Color]::FromArgb(45, 45, 45)
$panelContent.Controls.Add($sliderInterval)

$lblIntervalMin           = New-Object System.Windows.Forms.Label
$lblIntervalMin.Text      = "200ms"
$lblIntervalMin.ForeColor = [System.Drawing.Color]::Gray
$lblIntervalMin.Font      = New-Object System.Drawing.Font("Consolas", 8)
$lblIntervalMin.Location  = New-Object System.Drawing.Point(10, 96)
$lblIntervalMin.Size      = New-Object System.Drawing.Size(55, 16)
$lblIntervalMin.BackColor = [System.Drawing.Color]::Transparent
$panelContent.Controls.Add($lblIntervalMin)

$lblIntervalMax           = New-Object System.Windows.Forms.Label
$lblIntervalMax.Text      = "5000ms"
$lblIntervalMax.ForeColor = [System.Drawing.Color]::Gray
$lblIntervalMax.Font      = New-Object System.Drawing.Font("Consolas", 8)
$lblIntervalMax.Location  = New-Object System.Drawing.Point(238, 96)
$lblIntervalMax.Size      = New-Object System.Drawing.Size(60, 16)
$lblIntervalMax.BackColor = [System.Drawing.Color]::Transparent
$panelContent.Controls.Add($lblIntervalMax)

# ---------- Points affichés (max 3000) ----------
$lblPoints           = New-Object System.Windows.Forms.Label
$lblPoints.Text      = "Points :"
$lblPoints.ForeColor = [System.Drawing.Color]::White
$lblPoints.Font      = New-Object System.Drawing.Font("Segoe UI", 10)
$lblPoints.Location  = New-Object System.Drawing.Point(320, 38)
$lblPoints.Size      = New-Object System.Drawing.Size(80, 22)
$lblPoints.BackColor = [System.Drawing.Color]::Transparent
$panelContent.Controls.Add($lblPoints)

$lblPointsVal           = New-Object System.Windows.Forms.Label
$lblPointsVal.Text      = "$MaxPoints pts"
$lblPointsVal.ForeColor = [System.Drawing.Color]::LightSkyBlue
$lblPointsVal.Font      = New-Object System.Drawing.Font("Consolas", 10, [System.Drawing.FontStyle]::Bold)
$lblPointsVal.Location  = New-Object System.Drawing.Point(400, 38)
$lblPointsVal.Size      = New-Object System.Drawing.Size(80, 22)
$lblPointsVal.BackColor = [System.Drawing.Color]::Transparent
$panelContent.Controls.Add($lblPointsVal)

$sliderPoints               = New-Object System.Windows.Forms.TrackBar
$sliderPoints.Minimum       = 10
$sliderPoints.Maximum       = 3000
$sliderPoints.Value         = $MaxPoints
$sliderPoints.TickFrequency = 200
$sliderPoints.SmallChange   = 10
$sliderPoints.LargeChange   = 100
$sliderPoints.Location      = New-Object System.Drawing.Point(320, 58)
$sliderPoints.Size          = New-Object System.Drawing.Size(280, 38)
$sliderPoints.BackColor     = [System.Drawing.Color]::FromArgb(45, 45, 45)
$panelContent.Controls.Add($sliderPoints)

$lblPointsMin           = New-Object System.Windows.Forms.Label
$lblPointsMin.Text      = "10 pts"
$lblPointsMin.ForeColor = [System.Drawing.Color]::Gray
$lblPointsMin.Font      = New-Object System.Drawing.Font("Consolas", 8)
$lblPointsMin.Location  = New-Object System.Drawing.Point(320, 96)
$lblPointsMin.Size      = New-Object System.Drawing.Size(55, 16)
$lblPointsMin.BackColor = [System.Drawing.Color]::Transparent
$panelContent.Controls.Add($lblPointsMin)

$lblPointsMax           = New-Object System.Windows.Forms.Label
$lblPointsMax.Text      = "3000 pts"
$lblPointsMax.ForeColor = [System.Drawing.Color]::Gray
$lblPointsMax.Font      = New-Object System.Drawing.Font("Consolas", 8)
$lblPointsMax.Location  = New-Object System.Drawing.Point(548, 96)
$lblPointsMax.Size      = New-Object System.Drawing.Size(65, 16)
$lblPointsMax.BackColor = [System.Drawing.Color]::Transparent
$panelContent.Controls.Add($lblPointsMax)

# ============================================================
# --- Logique fold / unfold ---
# ============================================================
$script:isPanelExpanded = $true

function Toggle-Panel {
    if ($script:isPanelExpanded) {
        $panelContent.Visible   = $false
        $panelControl.Height    = $script:panelCollapsed
        $btnToggle.Text         = "Parametres"
        $script:isPanelExpanded = $false
    } else {
        $panelContent.Visible   = $true
        $panelControl.Height    = $script:panelExpanded
        $btnToggle.Text         = "Reduire"
        $script:isPanelExpanded = $true
    }
    Update-CanvasBounds
    Draw-Graph
}
$btnToggle.Add_Click({ Toggle-Panel })

# ============================================================
# --- Bouton Live ---
# ============================================================
function Update-LiveButton {
    if ($script:liveMode) {
        $btnLive.Text      = ">> Live"
        $btnLive.BackColor = [System.Drawing.Color]::FromArgb(30, 90, 40)
        $btnLive.FlatAppearance.BorderColor = [System.Drawing.Color]::FromArgb(50, 140, 60)
    } else {
        $btnLive.Text      = "|| Historique"
        $btnLive.BackColor = [System.Drawing.Color]::FromArgb(80, 60, 20)
        $btnLive.FlatAppearance.BorderColor = [System.Drawing.Color]::FromArgb(140, 110, 30)
    }
}

$btnLive.Add_Click({
    if ($script:liveMode) {
        $script:liveMode = $false
    } else {
        $script:liveMode     = $true
        $total   = $allPingData.Count
        $visible = $script:MaxPoints
        if ($total -gt $visible) {
            $newOffset           = $total - $visible
            $script:scrollOffset = $newOffset
            $scrollBar.Value     = [math]::Min($newOffset, [math]::Max(0, $scrollBar.Maximum - $scrollBar.LargeChange + 1))
        } else {
            $script:scrollOffset = 0
            $scrollBar.Value     = 0
        }
        Draw-Graph
    }
    Update-LiveButton
})

# ============================================================
# --- Fonction Ping .NET (aucun pipeline) ---
# ============================================================
function Get-PingTime {
    param([string]$TargetHost)
    try {
        $pingSender           = New-Object System.Net.NetworkInformation.Ping
        $options              = New-Object System.Net.NetworkInformation.PingOptions
        $options.DontFragment = $true
        $buffer               = [System.Text.Encoding]::ASCII.GetBytes("a" * 32)
        $timeout              = 1000
        $reply                = $pingSender.Send($TargetHost, $timeout, $buffer, $options)

        if ($reply.Status -eq [System.Net.NetworkInformation.IPStatus]::Success) {
            return [int]$reply.RoundtripTime
        } else {
            return -1
        }
    } catch {
        return -1
    }
}

# ============================================================
# --- Fonctions .NET pures (aucun pipeline) ---
# ============================================================
function Get-ValidPings {
    param([System.Collections.Generic.List[int]]$data)
    $result = New-Object System.Collections.Generic.List[int]
    foreach ($v in $data) { if ($v -ge 0) { $result.Add($v) } }
    return $result
}

function Get-TimeoutCount {
    param([System.Collections.Generic.List[int]]$data)
    $count = 0
    foreach ($v in $data) { if ($v -lt 0) { $count++ } }
    return $count
}

function Get-MinValue {
    param([System.Collections.Generic.List[int]]$data)
    $min = [int]::MaxValue
    foreach ($v in $data) { if ($v -lt $min) { $min = $v } }
    return $min
}

function Get-MaxValue {
    param([System.Collections.Generic.List[int]]$data)
    $max = 0
    foreach ($v in $data) { if ($v -gt $max) { $max = $v } }
    return $max
}

function Get-AvgValue {
    param([System.Collections.Generic.List[int]]$data)
    if ($data.Count -eq 0) { return 0 }
    $sum = 0
    foreach ($v in $data) { $sum += $v }
    return [math]::Round($sum / $data.Count, 1)
}

function Get-UptimeColor {
    param([double]$uptime)
    if ($uptime -ge 99)     { return [System.Drawing.Color]::LightGreen }
    elseif ($uptime -ge 90) { return [System.Drawing.Color]::Orange }
    else                    { return [System.Drawing.Color]::OrangeRed }
}

# ============================================================
# ✅ Taille des points selon densité pixels/point
# ============================================================
function Get-DotSize {
    param([int]$pointCount, [int]$drawWidth)
    if ($pointCount -le 0 -or $drawWidth -le 0) { return 0.0 }
    $pxPerPt = $drawWidth / $pointCount
    if ($pxPerPt -ge 12) { return 5.0 }
    if ($pxPerPt -ge 7)  { return 3.5 }
    if ($pxPerPt -ge 4)  { return 2.0 }
    if ($pxPerPt -ge 2)  { return 1.0 }
    return 0.0
}

# ============================================================
# --- Appliquer nouvelle cible ---
# ============================================================
$btnApplyTarget.Add_Click({
    $newTarget = $txtTarget.Text.Trim()
    if ($newTarget -ne "") {
        $script:Target   = $newTarget
        $form.Text       = "Novo Nordisk Ping Monitor v3.1 - $newTarget"
        $lblTitle.Text   = "Novo Nordisk Ping Monitor v3.1 — $newTarget"
        $script:liveMode = $true
        Update-LiveButton

        $allPingData.Clear()
        $allPingTimes.Clear()
        $script:scrollOffset = 0
        $script:StartTime    = Get-Date
        $scrollBar.Value     = 0
        $scrollBar.Maximum   = 9
        $scrollBar.Enabled   = $false
        $lblStats.Text       = ""
        $lblUptime.Text      = ""
        Draw-Graph
    }
})

# ============================================================
# --- Mise à jour scrollbar ---
# ============================================================
function Update-ScrollBar {
    $total   = $allPingData.Count
    $visible = $script:MaxPoints

    if ($total -gt $visible) {
        $scrollBar.Maximum     = $total - $visible + 9
        $scrollBar.LargeChange = 10
        $scrollBar.Enabled     = $true

        if ($script:liveMode) {
            $newVal              = [math]::Max(0, $scrollBar.Maximum - $scrollBar.LargeChange + 1)
            $scrollBar.Value     = $newVal
            $script:scrollOffset = $total - $visible
        }
    } else {
        $scrollBar.Maximum   = 9
        $scrollBar.Value     = 0
        $scrollBar.Enabled   = $false
        $script:scrollOffset = 0
    }
}

# ============================================================
# --- Fonction de dessin ---
# ============================================================
function Draw-Graph {
    if ($canvas.Width -le 0 -or $canvas.Height -le 0) { return }

    $total    = $allPingData.Count
    $visible  = $script:MaxPoints
    $offset   = $script:scrollOffset

    $startIdx = [math]::Max(0, [math]::Min($offset, $total - $visible))
    $endIdx   = [math]::Min($startIdx + $visible, $total)

    $pingData = New-Object System.Collections.Generic.List[int]
    $timeData = New-Object System.Collections.Generic.List[datetime]

    if ($endIdx -gt $startIdx) {
        for ($idx = $startIdx; $idx -lt $endIdx; $idx++) {
            $pingData.Add($allPingData[$idx])
            $timeData.Add($allPingTimes[$idx])
        }
    }

    $bmp = New-Object System.Drawing.Bitmap($canvas.Width, $canvas.Height)
    $g   = [System.Drawing.Graphics]::FromImage($bmp)
    $g.SmoothingMode     = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
    $g.TextRenderingHint = [System.Drawing.Text.TextRenderingHint]::AntiAlias

    $w    = $canvas.Width
    $h    = $canvas.Height
    $padL = 68
    $padR = 10
    $padT = 15
    $padB = 25

    $drawW = $w - $padL - $padR
    $drawH = $h - $padT - $padB

    if ($drawW -le 0 -or $drawH -le 0) {
        $canvas.Image = $bmp
        $g.Dispose()
        return
    }

    # Fond dégradé
    $gradBrush = New-Object System.Drawing.Drawing2D.LinearGradientBrush(
        [System.Drawing.Point]::new(0, 0),
        [System.Drawing.Point]::new(0, $h),
        [System.Drawing.Color]::FromArgb(25, 25, 35),
        [System.Drawing.Color]::FromArgb(15, 15, 20)
    )
    $g.FillRectangle($gradBrush, 0, 0, $w, $h)

    # Grille
    $gridPen  = New-Object System.Drawing.Pen([System.Drawing.Color]::FromArgb(50, 50, 60), 1)
    $fontAxis = New-Object System.Drawing.Font("Consolas", 10, [System.Drawing.FontStyle]::Bold)
    $brushTxt = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(200, 200, 200))

    $gridLines = 5
    for ($i = 0; $i -le $gridLines; $i++) {
        $yPos = $padT + ($i / $gridLines) * $drawH
        $g.DrawLine($gridPen, $padL, $yPos, ($padL + $drawW), $yPos)
    }
    $vLines = 10
    for ($i = 0; $i -le $vLines; $i++) {
        $xPos = $padL + ($i / $vLines) * $drawW
        $g.DrawLine($gridPen, $xPos, $padT, $xPos, ($padT + $drawH))
    }

    # Mode historique
    if (-not $script:liveMode) {
        $fontHist  = New-Object System.Drawing.Font("Segoe UI", 9, [System.Drawing.FontStyle]::Bold)
        $brushHist = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(200, 200, 150, 50))
        $g.DrawString("[ MODE HISTORIQUE ]", $fontHist, $brushHist, ($padL + $drawW - 170), ($padT + 2))
    }

    # Indicateur position
    if ($total -gt $visible) {
        $fontInfo  = New-Object System.Drawing.Font("Consolas", 8)
        $brushInfo = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(150, 150, 200))
        $g.DrawString(
            "Historique : points $($startIdx + 1) a $endIdx / $total",
            $fontInfo, $brushInfo, ($padL + 5), 2
        )
    }

    # Marqueurs de minutes
    if ($timeData.Count -ge 2) {
        $n           = $timeData.Count
        $currentMax  = $script:MaxPoints
        $fontMinute  = New-Object System.Drawing.Font("Consolas", 8, [System.Drawing.FontStyle]::Bold)
        $penMinute   = New-Object System.Drawing.Pen([System.Drawing.Color]::FromArgb(170, 180, 180, 180), 1)
        $brushMinute = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(210, 200, 200, 200))

        for ($i = 1; $i -lt $n; $i++) {
            $prevMin = $timeData[$i - 1].ToString("HH:mm")
            $currMin = $timeData[$i].ToString("HH:mm")

            if ($currMin -ne $prevMin) {
                $x = $padL + ($i / ([math]::Max($currentMax - 1, 1))) * $drawW
                $g.DrawLine($penMinute, $x, $padT, $x, ($padT + $drawH))

                if ($drawH -gt 60) {
                    $labelY = [math]::Min($padT + 80, $padT + $drawH - 5)
                    $g.TranslateTransform($x + 6, $labelY)
                    $g.RotateTransform(-90)
                    $g.DrawString($currMin, $fontMinute, $brushMinute, 0, 0)
                    $g.ResetTransform()
                }
            }
        }
    }

    # Tracé du graphique
    if ($pingData.Count -ge 2) {
        $currentMax = $script:MaxPoints
        $validLocal = Get-ValidPings -data $pingData
        $maxVal     = if ($validLocal.Count -gt 0) {
            [math]::Max((Get-MaxValue -data $validLocal), 10)
        } else { 100 }
        $maxVal = [math]::Ceiling($maxVal / 10) * 10

        for ($i = 0; $i -le $gridLines; $i++) {
            $yPos   = $padT + ($i / $gridLines) * $drawH
            $valLbl = [math]::Round($maxVal * (1 - $i / $gridLines))
            $g.DrawString("${valLbl}ms", $fontAxis, $brushTxt, 0, ($yPos - 8))
        }

        $brushFill    = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(40, 50, 220, 80))
        $penLineGreen = New-Object System.Drawing.Pen([System.Drawing.Color]::FromArgb(220, 80, 255, 100), 2)
        $penLineRed   = New-Object System.Drawing.Pen([System.Drawing.Color]::FromArgb(220, 255, 60, 60), 2)
        $brushDotOK   = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(255, 120, 255, 140))
        $brushDotTO   = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(255, 255, 50, 50))

        $dotSize = Get-DotSize -pointCount $pingData.Count -drawWidth $drawW

        $pts       = New-Object System.Collections.Generic.List[System.Drawing.PointF]
        $fillPts   = New-Object System.Collections.Generic.List[System.Drawing.PointF]
        $isTimeout = New-Object System.Collections.Generic.List[bool]

        $n      = $pingData.Count
        $firstX = $padL + (0 / ([math]::Max($currentMax - 1, 1))) * $drawW
        $fillPts.Add([System.Drawing.PointF]::new($firstX, $padT + $drawH))

        for ($i = 0; $i -lt $n; $i++) {
            $x   = $padL + ($i / ([math]::Max($currentMax - 1, 1))) * $drawW
            $val = $pingData[$i]

            if ($val -lt 0) {
                $yPos = $padT + $drawH
                $pts.Add([System.Drawing.PointF]::new($x, $yPos))
                $fillPts.Add([System.Drawing.PointF]::new($x, $yPos))
                $isTimeout.Add($true)
            } else {
                $ratio = [math]::Min($val / $maxVal, 1.0)
                $yPos  = $padT + $drawH - ($ratio * $drawH)
                $pts.Add([System.Drawing.PointF]::new($x, $yPos))
                $fillPts.Add([System.Drawing.PointF]::new($x, $yPos))
                $isTimeout.Add($false)
            }
        }

        $lastX = $padL + (($n - 1) / ([math]::Max($currentMax - 1, 1))) * $drawW
        $fillPts.Add([System.Drawing.PointF]::new($lastX, $padT + $drawH))

        if ($fillPts.Count -ge 3) { $g.FillPolygon($brushFill, $fillPts.ToArray()) }

        for ($i = 0; $i -lt ($pts.Count - 1); $i++) {
            $ptA = $pts[$i]
            $ptB = $pts[$i + 1]
            if ($isTimeout[$i] -and $isTimeout[$i + 1]) {
                $g.DrawLine($penLineRed, $ptA, $ptB)
            } else {
                $g.DrawLine($penLineGreen, $ptA, $ptB)
            }
        }

        if ($dotSize -gt 0) {
            $half = [float]($dotSize / 2.0)
            for ($i = 0; $i -lt $pts.Count; $i++) {
                $pt = $pts[$i]
                if ($isTimeout[$i]) {
                    $g.FillEllipse($brushDotTO, ($pt.X - $half), ($pt.Y - $half), $dotSize, $dotSize)
                    if ($dotSize -ge 3) {
                        $crossOff = [float]($half * 0.7)
                        $penCross = New-Object System.Drawing.Pen([System.Drawing.Color]::White, 1)
                        $g.DrawLine($penCross,
                            ($pt.X - $crossOff), ($pt.Y - $crossOff),
                            ($pt.X + $crossOff), ($pt.Y + $crossOff))
                        $g.DrawLine($penCross,
                            ($pt.X + $crossOff), ($pt.Y - $crossOff),
                            ($pt.X - $crossOff), ($pt.Y + $crossOff))
                    }
                } else {
                    $g.FillEllipse($brushDotOK, ($pt.X - $half), ($pt.Y - $half), $dotSize, $dotSize)
                }
            }
        }
    }

    $borderPen = New-Object System.Drawing.Pen([System.Drawing.Color]::FromArgb(80, 80, 100), 1)
    $g.DrawRectangle($borderPen, 0, 0, ($w - 1), ($h - 1))

    $canvas.Image = $bmp
    $g.Dispose()
    $gradBrush.Dispose()
}

# ============================================================
# --- Timer principal ---
# ✅ Bloc entier dans try/catch pour absorber ISE pipeline errors
# ============================================================
$timer          = New-Object System.Windows.Forms.Timer
$timer.Interval = $Interval

$timer.Add_Tick({
    try {
        $time = Get-PingTime -TargetHost $script:Target
        $now  = Get-Date

        $allPingData.Add($time)
        $allPingTimes.Add($now)
        Update-ScrollBar

        $elapsed    = $now - $script:StartTime
        $validAll   = Get-ValidPings   -data $allPingData
        $toCount    = Get-TimeoutCount -data $allPingData
        $totalCount = $allPingData.Count

        $loss      = if ($totalCount -gt 0) { [math]::Round(($toCount / $totalCount) * 100) } else { 0 }
        $uptimePct = [math]::Round(100 - $loss, 1)

        if ($validAll.Count -gt 0) {
            $min  = Get-MinValue -data $validAll
            $max  = Get-MaxValue -data $validAll
            $avg  = Get-AvgValue -data $validAll
            $last = if ($time -ge 0) { "${time} ms" } else { "Timeout !" }

            $lblStats.ForeColor = if ($time -ge 0) {
                [System.Drawing.Color]::LightGreen
            } else {
                [System.Drawing.Color]::OrangeRed
            }

            $lblStats.Text = "Dernier : $last  |  Min : ${min}ms  Max : ${max}ms  Moy : ${avg}ms  |  Perte : ${loss}%  |  Points : ${totalCount}/$($script:MaxPoints)  |  Duree : {0:D2}h {1:D2}m {2:D2}s  |  Total : {3}" -f `
                             $elapsed.Hours, $elapsed.Minutes, $elapsed.Seconds, $totalCount
        }

        $lblUptime.Text      = "UpTime : ${uptimePct}%"
        $lblUptime.ForeColor = Get-UptimeColor -uptime $uptimePct

        Draw-Graph
    } catch {
        # Absorbe silencieusement les erreurs pipeline ISE
    }
})

# ============================================================
# --- Événements ---
# ============================================================
$sliderInterval.Add_ValueChanged({
    $val                 = [math]::Round($sliderInterval.Value / 100) * 100
    $lblIntervalVal.Text = "${val} ms"
    $timer.Interval      = $val
})

$sliderPoints.Add_ValueChanged({
    $val               = $sliderPoints.Value
    $script:MaxPoints  = $val
    $lblPointsVal.Text = "$val pts"
    Update-ScrollBar
    Draw-Graph
})

$btnReset.Add_Click({
    $allPingData.Clear()
    $allPingTimes.Clear()
    $script:scrollOffset = 0
    $script:liveMode     = $true
    Update-LiveButton
    $script:StartTime    = Get-Date
    $scrollBar.Value     = 0
    $scrollBar.Maximum   = 9
    $scrollBar.Enabled   = $false
    $lblStats.Text       = ""
    $lblUptime.Text      = ""
    Draw-Graph
})

$panelControl.Add_Resize({
    $btnReset.Location = New-Object System.Drawing.Point(($panelControl.Width - 100), 7)
})

$scrollBar.Add_Scroll({
    $script:scrollOffset = $scrollBar.Value
    $total   = $allPingData.Count
    $visible = $script:MaxPoints
    $atEnd   = ($script:scrollOffset -ge ($total - $visible))

    if (-not $atEnd -and $script:liveMode) {
        $script:liveMode = $false
        Update-LiveButton
    } elseif ($atEnd -and -not $script:liveMode) {
        $script:liveMode = $true
        Update-LiveButton
    }
    Draw-Graph
})

$form.Add_Resize({
    Update-CanvasBounds
    Draw-Graph
})

$form.Add_Shown({
    Update-LiveButton
    $timer.Start()
})
$form.Add_FormClosing({ $timer.Stop() })

[void]$form.ShowDialog()
