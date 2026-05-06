# ============================================================
# SCRIPT  : Ping Monitor
# VERSION : 4.4
# AUTEUR  : NEric Guiffault
# DATE    : 2026-05
# DESCRIPTION : Monitoring de ping — 100% offline.
#               Chart.js embarque depuis cache local.
#               Compatible ConstrainedLanguage strict.
#               Theme Light/Dark + intervalles configurables.
# ------------------------------------------------------------
# INSTALLATION OFFLINE — Chart.js :
#   1. Telecharger depuis une machine avec internet :
#      https://cdn.jsdelivr.net/npm/chart.js@4.4.0/dist/chart.umd.min.js
#   2. Renommer : chartjs.min.js  (ou chart.min.js)
#   3. Copier dans :
#      %USERPROFILE%\Documents\chartjs.min.js
#      OU %TEMP%\NovoPingMonitor\chartjs.min.js
# ------------------------------------------------------------
# NAVIGATEUR : Edge ou Chrome recommandes (pas IE)
# ============================================================

if ($Host.Name -eq "Windows PowerShell ISE Host") {
    $scriptPath = $null
    if ($psISE -and $psISE.CurrentFile) { $scriptPath = $psISE.CurrentFile.FullPath }
    if ($scriptPath -and (Test-Path -Path $scriptPath -PathType Leaf)) {
        Write-Host "  ISE detecte — Lancement dans powershell.exe..." -ForegroundColor Cyan
        Start-Process -FilePath "powershell.exe" `
                      -ArgumentList "-NoProfile","-ExecutionPolicy","Bypass","-NoExit","-File","`"$scriptPath`"" `
                      -WindowStyle Normal
    } else {
        Write-Host "  Sauvegardez avec Ctrl+S puis relancez." -ForegroundColor Red
    }
    return
}

# ============================================================
# --- Configuration ---
# ============================================================
$Target     = "8.8.8.8"
$Interval   = 1000      # ms entre chaque ping
$MaxKeep    = 3000      # points max en memoire
$WriteEvery = 2         # recriture JS toutes les N secondes

# ============================================================
# --- Dossier temporaire ---
# ============================================================
$scriptTemp = "$env:TEMP\NovoPingMonitor"
if (-not (Test-Path $scriptTemp)) {
    New-Item -ItemType Directory -Path $scriptTemp -Force | Out-Null
}
$htmlFile = "$scriptTemp\ping_monitor.html"
$dataFile = "$scriptTemp\ping_data.js"

# ============================================================
# --- Variables ---
# ============================================================
$script:Target    = $Target
$script:startTime = Get-Date
$script:pingTs    = @()
$script:pingVs    = @()
$script:pingCount = 0

# ============================================================
# ✅ Fonctions compatibles ConstrainedLanguage
# ============================================================
function Round-Int {
    param([double]$n)
    if (($n - [int]$n) -ge 0.5) { return [int]$n + 1 }
    return [int]$n
}
function Get-NowMs { return [long]([double](Get-Date -UFormat %s) * 1000) }
function Get-ElapsedSec { return [int]((Get-Date) - $script:startTime).TotalSeconds }

function Get-PingTime {
    param([string]$TargetHost)
    try {
        $r = Test-Connection -ComputerName $TargetHost -Count 1 `
                             -ErrorAction SilentlyContinue -WarningAction SilentlyContinue
        if ($null -ne $r) {
            $x = $r | Select-Object -First 1
            if ($null -ne $x.ResponseTime) { return [int]$x.ResponseTime }
            if ($null -ne $x.Latency)      { return [int]$x.Latency }
        }
        return -1
    } catch { return -1 }
}

function Calc-Stats {
    $timeouts=0; $sumV=0; $minV=99999; $maxV=0; $validCnt=0
    for ($i=0; $i -lt $script:pingCount; $i++) {
        $v = $script:pingVs[$i]
        if ($v -lt 0) { $timeouts++ }
        else {
            $validCnt++; $sumV += $v
            if ($v -lt $minV) { $minV = $v }
            if ($v -gt $maxV) { $maxV = $v }
        }
    }
    $lossRaw = 0
    if ($script:pingCount -gt 0) { $lossRaw = ($timeouts * 100) / $script:pingCount }
    $loss   = Round-Int $lossRaw
    $avgV   = 0
    if ($validCnt -gt 0) { $avgV = Round-Int ($sumV / $validCnt) }
    $lastV  = -1
    if ($script:pingCount -gt 0) { $lastV = $script:pingVs[$script:pingCount - 1] }
    $minStr = "-1"; if ($validCnt -gt 0) { $minStr = "$minV" }
    $maxStr = "-1"; if ($validCnt -gt 0) { $maxStr = "$maxV" }
    return @{ loss=$loss; uptime=(100-$loss); avgV=$avgV; lastV=$lastV; minStr=$minStr; maxStr=$maxStr }
}

function Write-DataJs {
    $parts = @()
    for ($i=0; $i -lt $script:pingCount; $i++) {
        $parts += "{t:$($script:pingTs[$i]),v:$($script:pingVs[$i])}"
    }
    $st      = Calc-Stats
    $elapsed = Get-ElapsedSec
    $hh = [int]($elapsed/3600); $mm = [int](($elapsed%3600)/60); $ss = $elapsed%60
    $js = "window.PD={items:[" + ($parts -join ",") + "]," +
          "target:`"$($script:Target)`",startMs:$($script:startMs)," +
          "total:$($script:pingCount),loss:$($st.loss),uptime:$($st.uptime)," +
          "lastV:$($st.lastV),minV:$($st.minStr),maxV:$($st.maxStr),avgV:$($st.avgV)," +
          "dur:`"$("{0:D2}h {1:D2}m {2:D2}s"-f $hh,$mm,$ss)`"," +
          "now:`"$(Get-Date -Format "HH:mm:ss")`"};"
    try { $js | Set-Content -Path $dataFile -Encoding UTF8 -ErrorAction Stop } catch {}
}

function Get-ChartJsTag {
    $candidates = @(
        "$scriptTemp\chartjs.min.js",
        "$scriptTemp\chart.min.js",
        "$env:USERPROFILE\Documents\chartjs.min.js",
        "$env:USERPROFILE\Documents\chart.min.js",
        "$env:USERPROFILE\Desktop\chartjs.min.js",
        "$env:USERPROFILE\Desktop\chart.min.js",
        "C:\Users\adminEGUI\Documents\chartjs.min.js",
        "C:\Users\adminEGUI\Documents\chart.min.js",
        "C:\Users\adminEGUI\AppData\Local\Temp\3\NovoPingMonitor\chartjs.min.js",
        "C:\Users\adminEGUI\AppData\Local\Temp\3\NovoPingMonitor\chart.min.js"
    )
    Write-Host "  Chart.js : recherche locale..." -ForegroundColor Cyan
    foreach ($c in $candidates) {
        if (-not $c) { continue }
        if (Test-Path $c) {
            $src = Get-Content -Path $c -Raw -ErrorAction SilentlyContinue
            if ($src -and $src.Length -gt 10000) {
                Write-Host "  Chart.js : OK — $c ($([int]($src.Length/1024)) KB)" -ForegroundColor Green
                if ($c -ne "$scriptTemp\chartjs.min.js") {
                    try { $src | Set-Content -Path "$scriptTemp\chartjs.min.js" -Encoding UTF8 -ErrorAction SilentlyContinue } catch {}
                }
                return "<script>`n$src`n</script>"
            }
        }
    }
    Write-Host "  Chart.js : tentative telechargement..." -ForegroundColor Yellow
    try {
        $wc = New-Object System.Net.WebClient
        $wc.Headers.Add("User-Agent","PowerShell/5.1")
        $src = $wc.DownloadString("https://cdn.jsdelivr.net/npm/chart.js@4.4.0/dist/chart.umd.min.js")
        if ($src -and $src.Length -gt 10000) {
            $src | Set-Content -Path "$scriptTemp\chartjs.min.js" -Encoding UTF8 -ErrorAction SilentlyContinue
            Write-Host "  Chart.js : telecharge OK ($([int]($src.Length/1024)) KB)" -ForegroundColor Green
            return "<script>`n$src`n</script>"
        }
    } catch { Write-Host "  Chart.js : telechargement impossible" -ForegroundColor Red }
    Write-Host "  Chart.js : fallback CDN" -ForegroundColor Red
    Write-Host "  >> Deposez chartjs.min.js dans : $scriptTemp" -ForegroundColor Yellow
    return '<script src="https://cdn.jsdelivr.net/npm/chart.js@4.4.0/dist/chart.umd.min.js"></script>'
}

function Open-Browser {
    param([string]$FilePath)
    $browsers = @(
        "C:\Program Files (x86)\Microsoft\Edge\Application\msedge.exe",
        "C:\Program Files\Microsoft\Edge\Application\msedge.exe",
        "C:\Program Files\Google\Chrome\Application\chrome.exe",
        "C:\Program Files (x86)\Google\Chrome\Application\chrome.exe",
        "C:\Program Files\Mozilla Firefox\firefox.exe",
        "C:\Program Files (x86)\Mozilla Firefox\firefox.exe"
    )
    $found = $null
    foreach ($b in $browsers) { if (Test-Path $b) { $found = $b; break } }
    if ($found) {
        Write-Host "  Navigateur : $(Split-Path $found -Leaf)" -ForegroundColor Green
        Start-Process -FilePath $found -ArgumentList "`"$FilePath`""
    } else {
        Write-Host "  Navigateur : defaut (si IE : cliquez 'Allow blocked content')" -ForegroundColor Yellow
        Start-Process $FilePath
    }
}

# ============================================================
# ✅ Generation HTML
# ============================================================
function Write-HtmlOnce {
    param([string]$target)
    $dataFileJs = $dataFile -replace '\\','\\\\'
    $chartJsTag = Get-ChartJsTag

    $html = @"
<!DOCTYPE html>
<html lang="fr" data-theme="dark">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width,initial-scale=1.0">
<title>NN Ping Monitor v4.4</title>
$chartJsTag
<style>
/* ============================================================
   THEMES
   ============================================================ */
:root{
  --bg:#1a1a2e;--surface:#16213e;--surface2:#0d1b2a;--surface3:#0a0f1a;
  --border:#0f3460;--border2:#1e3050;--border3:#0f2040;
  --text:#e0e0e0;--text2:#a0b0c0;--text3:#445;--text4:#889;
  --accent:#4cc9f0;--accent2:#0f3460;
  --ok:#4ade80;--warn:#fb923c;--danger:#f87171;
  --live-bg:#143a20;--live-c:#4ade80;
  --hist-bg:#3a2a08;--hist-c:#fb923c;
  --apply-bg:#0f3460;--apply-c:#4cc9f0;
  --reset-bg:#5a1515;--reset-c:#f87171;
  --tog-bg:transparent;--tog-c:#4466aa;--tog-border:#1e3050;
  --sb-track:#111927;--sb-bg:#0d1117;
  --sb-live:#1a5a2a;--sb-hist:#1e4a7a;
  --inp-bg:#0d1b2a;--inp-border:#0f3460;
  --chart-grid:rgba(80,80,120,.15);--chart-grid2:rgba(80,80,120,.2);
  --chart-tick:#445;--chart-tickY:#bbb;
  --chart-line:rgba(80,255,100,.85);--chart-fill:rgba(50,220,80,.07);
  --chart-to-bg:rgba(255,60,60,.2);--chart-to-bd:rgba(255,60,60,.6);
}
[data-theme="light"]{
  --bg:#f0f4f8;--surface:#ffffff;--surface2:#e8edf5;--surface3:#dde4ee;
  --border:#b0c0d8;--border2:#c8d4e8;--border3:#c0cfe0;
  --text:#0f1923;--text2:#3a5070;--text3:#8090a8;--text4:#607090;
  --accent:#0063be;--accent2:#dde9f8;
  --ok:#007a5e;--warn:#b86000;--danger:#c0202e;
  --live-bg:#d4f0e0;--live-c:#007a5e;
  --hist-bg:#fdefd4;--hist-c:#b86000;
  --apply-bg:#dde9f8;--apply-c:#0063be;
  --reset-bg:#fde8e8;--reset-c:#c0202e;
  --tog-bg:#eef2f8;--tog-c:#3a5070;--tog-border:#b0c0d8;
  --sb-track:#dde4ee;--sb-bg:#e8edf5;
  --sb-live:#007a5e;--sb-hist:#0063be;
  --inp-bg:#ffffff;--inp-border:#b0c0d8;
  --chart-grid:rgba(100,120,160,.12);--chart-grid2:rgba(100,120,160,.18);
  --chart-tick:#8090a8;--chart-tickY:#3a5070;
  --chart-line:rgba(0,120,80,.85);--chart-fill:rgba(0,180,100,.07);
  --chart-to-bg:rgba(192,32,46,.15);--chart-to-bd:rgba(192,32,46,.5);
}

/* ============================================================
   BASE
   ============================================================ */
*{margin:0;padding:0;box-sizing:border-box;transition:background-color .2s,color .2s,border-color .2s}
body{background:var(--bg);color:var(--text);font-family:'Segoe UI',Consolas,monospace;display:flex;flex-direction:column;height:100vh;overflow:hidden}

/* ============================================================
   HEADER
   ============================================================ */
.hdr{background:var(--surface);padding:8px 16px;border-bottom:2px solid var(--border);
     display:flex;align-items:center;justify-content:space-between;gap:8px;
     min-height:44px;flex-shrink:0}
.hl{display:flex;align-items:center;gap:10px}
.hdr h1{font-size:1.05em;font-weight:bold;color:var(--text);white-space:nowrap}
.ts{color:var(--accent)}
.vtag{background:var(--accent2);color:var(--accent);font-size:.72em;
      padding:2px 7px;border-radius:10px;font-weight:bold}
.hr2{display:flex;gap:10px;align-items:center;flex-shrink:0}
.dur{color:var(--warn);font-size:.85em;font-weight:bold;white-space:nowrap}
.ub{font-size:.95em;font-weight:bold;padding:3px 10px;border-radius:20px;
    border:2px solid currentColor;white-space:nowrap}
.ug{color:var(--ok)}.uo{color:var(--warn)}.ur{color:var(--danger)}

/* ============================================================
   INFOBAR
   ============================================================ */
.ibar{background:var(--surface2);padding:0 16px;border-bottom:1px solid var(--border);
      display:flex;align-items:center;font-size:.81em;height:26px;flex-shrink:0;overflow:hidden}
.sp{width:1px;height:13px;background:var(--border2);margin:0 9px;flex-shrink:0}
.si{display:flex;gap:3px;align-items:center;flex-shrink:0;white-space:nowrap}
.sl{color:var(--text3)}.sv{font-weight:bold}
.ok{color:var(--ok)}.t2{color:var(--danger)}.wn{color:var(--warn)}.nt{color:var(--text2)}
.il{display:flex;align-items:center;gap:5px;flex-shrink:0}
.iv{color:var(--text3);font-size:.88em}
.mv{color:var(--ok);font-size:.88em;font-weight:600}
.mv.h{color:var(--warn)}

/* ============================================================
   CANVAS
   ============================================================ */
.cw{flex:1;position:relative;padding:8px 14px 4px;overflow:hidden;min-height:60px}
.hb{display:none;position:absolute;top:10px;right:16px;
    background:var(--hist-bg);color:var(--hist-c);
    font-size:.76em;font-weight:bold;padding:2px 9px;border-radius:5px;
    border:1px solid var(--hist-c);pointer-events:none;z-index:10}
.hb.v{display:block}

/* ============================================================
   SCROLLBAR CUSTOM
   ============================================================ */
.sbw{background:var(--sb-bg);height:16px;flex-shrink:0;
     border-top:1px solid var(--border3);border-bottom:1px solid var(--border3);
     position:relative;cursor:pointer;user-select:none}
.sbt{position:absolute;top:3px;bottom:3px;left:0;right:0;
     background:var(--sb-track);border-radius:5px;margin:0 4px}
.sbh{position:absolute;top:0;bottom:0;border-radius:5px;
     min-width:20px;cursor:grab;transition:background .15s,left .05s,width .05s}
.sbh:hover,.sbh.d{filter:brightness(1.3)}
.sbh.lm{background:var(--sb-live)}
.sbh.hm{background:var(--sb-hist)}
.sbd{position:absolute;right:4px;top:50%;transform:translateY(-50%);
     width:5px;height:5px;border-radius:50%;background:var(--ok);
     animation:pl 1.2s infinite}
@keyframes pl{0%,100%{opacity:1}50%{opacity:.2}}

/* ============================================================
   CONTROLES
   ============================================================ */
.cb{background:var(--surface);border-top:1px solid var(--border);flex-shrink:0}
.ch{display:flex;align-items:center;justify-content:space-between;
    padding:5px 16px;gap:8px;min-height:36px}
.chl{display:flex;align-items:center;gap:8px;flex-wrap:wrap}
.chr{display:flex;align-items:center;gap:6px;flex-shrink:0}
.co{display:flex;gap:16px;align-items:center;flex-wrap:wrap;
    padding:6px 16px 8px;border-top:1px solid var(--border)}
.co.hid{display:none}

/* Options groupees */
.og{display:flex;align-items:center;gap:12px;flex-wrap:wrap}
.og-sep{width:1px;height:24px;background:var(--border2);flex-shrink:0}
.og-title{color:var(--text3);font-size:.72em;font-weight:600;
          text-transform:uppercase;letter-spacing:.5px;white-space:nowrap}

/* Champ texte */
.ci{display:flex;align-items:center;gap:5px}
.ci label{color:var(--text4);font-size:.78em;white-space:nowrap}
input[type=text]{background:var(--inp-bg);border:1px solid var(--inp-border);
                 color:var(--accent);padding:3px 8px;border-radius:4px;
                 font-size:.82em;width:165px;font-family:Consolas,monospace;font-weight:bold}
input[type=text]:focus{outline:2px solid var(--accent)}

/* Sliders */
.sg{display:flex;align-items:center;gap:6px}
.sg label{color:var(--text3);font-size:.75em;white-space:nowrap;min-width:56px;text-align:right}
.sg .sv2{color:var(--accent);font-weight:bold;font-size:.78em;min-width:44px}
input[type=range]{width:100px;accent-color:var(--accent);cursor:pointer}

/* Select intervalle */
.sg select{background:var(--inp-bg);border:1px solid var(--inp-border);
           color:var(--accent);padding:2px 4px;border-radius:4px;
           font-size:.78em;font-family:Consolas,monospace;font-weight:bold;
           cursor:pointer;min-width:70px}

/* Boutons */
.btn{padding:4px 11px;border:none;border-radius:4px;cursor:pointer;
     font-size:.78em;font-weight:bold;white-space:nowrap;transition:opacity .15s}
.btn:hover{opacity:.8}
.ba{background:var(--apply-bg);color:var(--apply-c)}
.br{background:var(--reset-bg);color:var(--reset-c)}
.bl{background:var(--live-bg);color:var(--live-c);min-width:78px}
.bh2{background:var(--hist-bg);color:var(--hist-c);min-width:78px}
.bt{background:var(--tog-bg);border:1px solid var(--tog-border);
    color:var(--tog-c);font-size:.72em;padding:2px 8px;border-radius:4px;cursor:pointer}
.bt:hover{filter:brightness(1.15)}

/* Theme toggle */
.theme-btn{background:var(--tog-bg);border:1px solid var(--tog-border);
           color:var(--tog-c);font-size:.72em;padding:2px 10px;
           border-radius:4px;cursor:pointer;white-space:nowrap}
.theme-btn:hover{filter:brightness(1.15)}

/* Dot */
.dot{width:8px;height:8px;border-radius:50%;display:inline-block;flex-shrink:0}
.do{background:var(--ok);animation:pl 1.2s infinite}
.dt{background:var(--danger)}
</style>
</head>
<body>

<!-- ============================================================
     HEADER
     ============================================================ -->
<div class="hdr">
  <div class="hl">
    <span class="dot do" id="sd"></span>
    <h1>Ping Monitor &mdash; <span class="ts" id="tl">$target</span></h1>
    <span class="vtag">v4.4</span>
  </div>
  <div class="hr2">
    <span class="dur" id="dl">--</span>
    <span class="ub ug" id="ul">UpTime : --%</span>
  </div>
</div>

<!-- ============================================================
     INFOBAR — update + mode + stats sur 1 ligne
     ============================================================ -->
<div class="ibar">
  <div class="il">
    <span id="nl" class="iv">--:--:--</span>
    <span style="color:var(--border2);font-size:.8em">|</span>
    <span id="ml" class="mv">Live</span>
  </div>
  <div class="sp"></div>
  <div class="si"><span class="sl">Dernier</span><span class="sv ok" id="s1">--</span></div>
  <div class="sp"></div>
  <div class="si"><span class="sl">Min</span><span class="sv nt" id="s2">--</span></div>
  <div class="sp"></div>
  <div class="si"><span class="sl">Max</span><span class="sv nt" id="s3">--</span></div>
  <div class="sp"></div>
  <div class="si"><span class="sl">Moy</span><span class="sv nt" id="s4">--</span></div>
  <div class="sp"></div>
  <div class="si"><span class="sl">Perte</span><span class="sv ok" id="s5">--%</span></div>
  <div class="sp"></div>
  <div class="si"><span class="sl">Total</span><span class="sv nt" id="s6">0</span></div>
</div>

<!-- ============================================================
     CANVAS
     ============================================================ -->
<div class="cw">
  <div id="hb" class="hb">Molette ou scrollbar pour naviguer</div>
  <canvas id="pc"></canvas>
</div>

<!-- ============================================================
     SCROLLBAR HORIZONTALE CUSTOM
     ============================================================ -->
<div class="sbw">
  <div class="sbt" id="sbt">
    <div class="sbh lm" id="sbh">
      <div class="sbd" id="sbdot"></div>
    </div>
  </div>
</div>

<!-- ============================================================
     CONTROLES
     ============================================================ -->
<div class="cb">

  <!-- Ligne principale toujours visible -->
  <div class="ch">
    <div class="chl">
      <div class="ci">
        <label>Cible :</label>
        <input type="text" id="iT" value="$target"
               onkeydown="if(event.key==='Enter')this.blur();"
               onfocus="pr=true" onblur="pr=false">
        <button class="btn ba" onclick="applyT()" onmousedown="pr=false">Appliquer</button>
      </div>
      <button class="btn bl" id="bL" onclick="togLive()">&#9654; Live</button>
      <button class="btn br" onclick="doReset()">&#8635; Vue</button>
    </div>
    <div class="chr">
      <button class="theme-btn" id="thBtn" onclick="togTheme()">&#9728; Light</button>
      <button class="bt" id="bto" onclick="togOpt()">&#9660; Options</button>
    </div>
  </div>

  <!-- Options foldables -->
  <div class="co hid" id="co">
    <div class="og">

      <!-- Groupe : Affichage -->
      <span class="og-title">Affichage</span>
      <div class="sg">
        <label>Points :</label>
        <input type="range" id="sP" min="10" max="3000" value="120"
          oninput="document.getElementById('vP').textContent=this.value+' pts';uc();usb()">
        <span class="sv2" id="vP">120 pts</span>
      </div>
      <div class="sg">
        <label>Taille pts :</label>
        <input type="range" id="sD" min="0" max="10" value="0"
          oninput="updDL(this.value);uc()">
        <span class="sv2" id="vD">Auto</span>
      </div>

      <div class="og-sep"></div>

      <!-- Groupe : Intervalle de ping -->
      <span class="og-title">Intervalle ping</span>
      <div class="sg">
        <label>Intervalle :</label>
        <select id="selInt" onchange="applyInterval(this.value)">
          <option value="200">200 ms</option>
          <option value="500">500 ms</option>
          <option value="1000" selected>1 s</option>
          <option value="2000">2 s</option>
          <option value="5000">5 s</option>
          <option value="10000">10 s</option>
          <option value="30000">30 s</option>
          <option value="60000">1 min</option>
        </select>
      </div>
      <div class="si" style="font-size:.78em">
        <span style="color:var(--text3)">Prochain ping dans</span>
        <span class="sv nt" id="sNext" style="font-size:.9em">--</span>
      </div>

    </div>
  </div>
</div>

<script>
var DJP='$dataFileJs';
var aD=[],live=true,vo=0,pr=false,ldc=0,oo=false;
var sbdrag=false,sbsx=0,sbsvo=0;
var darkMode=true;

// ============================================================
// Theme
// ============================================================
function togTheme(){
  darkMode=!darkMode;
  document.documentElement.setAttribute('data-theme',darkMode?'dark':'light');
  document.getElementById('thBtn').innerHTML=darkMode?'&#9728; Light':'&#9790; Dark';
  updChartTheme();
}
function updChartTheme(){
  var s=getComputedStyle(document.documentElement);
  var grid=s.getPropertyValue('--chart-grid').trim();
  var grid2=s.getPropertyValue('--chart-grid2').trim();
  var tick=s.getPropertyValue('--chart-tick').trim();
  var tickY=s.getPropertyValue('--chart-tickY').trim();
  ch.options.scales.x.ticks.color=tick;
  ch.options.scales.x.grid.color=grid;
  ch.options.scales.y.ticks.color=tickY;
  ch.options.scales.y.grid.color=grid2;
  ch.data.datasets[0].borderColor=s.getPropertyValue('--chart-line').trim();
  ch.data.datasets[0].backgroundColor=s.getPropertyValue('--chart-fill').trim();
  ch.data.datasets[1].backgroundColor=s.getPropertyValue('--chart-to-bg').trim();
  ch.data.datasets[1].borderColor=s.getPropertyValue('--chart-to-bd').trim();
  ch.update('none');
}

// ============================================================
// Intervalle ping — communique via champ cache dans le JS
// ============================================================
var pingIntervalMs = 1000;
var nextPingIn     = 1000;
var intervalTimer  = null;
var countdownTimer = null;

function applyInterval(val){
  pingIntervalMs = parseInt(val);
  // Ecriture dans un fichier flag pour PS (via data.js etendu)
  // Le script PS lit l intervalle depuis window.PD.interval
  document.getElementById('sNext').textContent = (pingIntervalMs/1000).toFixed(1)+'s';
  startCountdown();
}

function startCountdown(){
  if(countdownTimer) clearInterval(countdownTimer);
  nextPingIn = pingIntervalMs;
  countdownTimer = setInterval(function(){
    nextPingIn -= 500;
    if(nextPingIn < 0) nextPingIn = pingIntervalMs;
    document.getElementById('sNext').textContent = (nextPingIn/1000).toFixed(1)+'s';
  },500);
}

// ============================================================
// Chart.js
// ============================================================
var cx=document.getElementById('pc').getContext('2d');
var ch=new Chart(cx,{
  type:'line',
  data:{labels:[],datasets:[
    {label:'ms',data:[],
     borderColor:'rgba(80,255,100,.85)',backgroundColor:'rgba(50,220,80,.07)',
     borderWidth:2,pointRadius:[],pointBackgroundColor:[],pointBorderColor:[],
     fill:true,tension:.2,spanGaps:false,order:2},
    {label:'TO',data:[],type:'bar',
     backgroundColor:'rgba(255,60,60,.2)',borderColor:'rgba(255,60,60,.6)',
     borderWidth:1,barPercentage:.4,categoryPercentage:1,order:1}
  ]},
  options:{
    responsive:true,maintainAspectRatio:false,animation:false,
    interaction:{mode:'index',intersect:false},
    plugins:{legend:{display:false},
      tooltip:{callbacks:{label:function(c){
        return c.datasetIndex===0?(c.parsed.y===null?'Timeout':c.parsed.y+' ms'):'';
      }}}},
    scales:{
      x:{ticks:{color:'#445',maxTicksLimit:12,font:{size:9,family:'Consolas'},maxRotation:0},
         grid:{color:'rgba(80,80,120,.15)'}},
      y:{min:0,
         ticks:{color:'#bbb',font:{size:11,family:'Consolas',weight:'bold'},
                callback:function(v){return v+'ms';}},
         grid:{color:'rgba(80,80,120,.2)'}}
    }
  }
});

// ============================================================
// Helpers
// ============================================================
function gmp(){return parseInt(document.getElementById('sP').value);}
function gds(n,w){
  var s=parseInt(document.getElementById('sD').value);if(s>0)return s;
  var p=w/Math.max(n,1);
  if(p>=12)return 5;if(p>=7)return 3;if(p>=4)return 2;if(p>=2)return 1;return 0;
}
function ft(ms){
  var d=new Date(ms);
  return('0'+d.getHours()).slice(-2)+':'+('0'+d.getMinutes()).slice(-2)+':'+('0'+d.getSeconds()).slice(-2);
}
function updDL(v){document.getElementById('vD').textContent=(+v===0)?'Auto':v+'px';}

// ============================================================
// Scrollbar
// ============================================================
function usb(){
  var th=document.getElementById('sbh'),dt=document.getElementById('sbdot');
  var tot=aD.length,mp=gmp();
  if(tot<=mp){
    th.style.left='0%';th.style.width='100%';
    th.className='sbh lm';dt.style.display='block';return;
  }
  var r=mp/tot,p=vo/tot;
  th.style.width=(r*100).toFixed(2)+'%';
  th.style.left=(p*100).toFixed(2)+'%';
  if(live){th.className='sbh lm';dt.style.display='block';}
  else{th.className='sbh hm';dt.style.display='none';}
}

document.getElementById('sbt').addEventListener('mousedown',function(e){
  if(e.target===document.getElementById('sbh'))return;
  var rect=document.getElementById('sbt').getBoundingClientRect();
  var r=(e.clientX-rect.left)/rect.width;
  var tot=aD.length,mp=gmp();
  var nv=Math.round(r*tot-mp/2);
  nv=Math.max(0,Math.min(nv,Math.max(0,tot-mp)));
  vo=nv;sl(vo>=Math.max(0,tot-mp));uc();usb();
});
document.getElementById('sbh').addEventListener('mousedown',function(e){
  e.preventDefault();e.stopPropagation();
  sbdrag=true;sbsx=e.clientX;sbsvo=vo;
  document.getElementById('sbh').classList.add('d');
});
document.addEventListener('mousemove',function(e){
  if(!sbdrag)return;
  var rect=document.getElementById('sbt').getBoundingClientRect();
  var tot=aD.length,mp=gmp();
  var dv=Math.round(((e.clientX-sbsx)/rect.width)*tot);
  var nv=Math.max(0,Math.min(sbsvo+dv,Math.max(0,tot-mp)));
  vo=nv;sl(vo>=Math.max(0,tot-mp));uc();usb();
});
document.addEventListener('mouseup',function(){
  if(sbdrag){sbdrag=false;document.getElementById('sbh').classList.remove('d');}
});

// ============================================================
// Graphique
// ============================================================
function uc(){
  var mp=gmp(),tot=aD.length,cw=cx.canvas.offsetWidth;
  var mv=Math.max(0,tot-mp);
  if(live){vo=mv;}else{vo=Math.max(0,Math.min(vo,mv));}
  var sl2=aD.slice(vo,vo+mp),n=sl2.length,ds=gds(n,cw);
  var lb=[],vs=[],tv=[],pr2=[],pb=[],pd=[],pm='';
  sl2.forEach(function(d,i){
    var ts=ft(d.t),mn=ts.substring(0,5);
    lb.push(i>0&&mn!==pm?ts:'');pm=mn;
    if(d.v<0){
      vs.push(null);tv.push(1);pr2.push(ds>0?ds+2:0);
      pb.push('rgba(255,50,50,.9)');pd.push('rgba(255,50,50,1)');
    } else {
      vs.push(d.v);tv.push(null);pr2.push(ds);
      pb.push(darkMode?'rgba(120,255,140,.9)':'rgba(0,140,80,.9)');
      pd.push(darkMode?'rgba(80,255,100,1)':'rgba(0,120,60,1)');
    }
  });
  ch.data.labels=lb;
  ch.data.datasets[0].data=vs;ch.data.datasets[0].pointRadius=pr2;
  ch.data.datasets[0].pointBackgroundColor=pb;ch.data.datasets[0].pointBorderColor=pd;
  ch.data.datasets[1].data=tv;
  var vv=vs.filter(function(v){return v!==null;});
  if(vv.length>0)ch.options.scales.y.max=Math.ceil(Math.max.apply(null,vv)/10)*10+10;
  ch.update('none');
}

// ============================================================
// UI
// ============================================================
function uu(d){
  var lv=d.lastV,lo=d.loss,up=d.uptime;
  var dot=document.getElementById('sd'),s1=document.getElementById('s1');
  if(lv<0){dot.className='dot dt';s1.textContent='Timeout';s1.className='sv t2';}
  else{dot.className='dot do';s1.textContent=lv+' ms';s1.className='sv ok';}
  document.getElementById('s2').textContent=d.minV>=0?d.minV+' ms':'--';
  document.getElementById('s3').textContent=d.maxV>=0?d.maxV+' ms':'--';
  document.getElementById('s4').textContent=d.avgV>0?d.avgV+' ms':'--';
  var e5=document.getElementById('s5');
  e5.textContent=lo+'%';e5.className='sv '+(lo>10?'t2':lo>0?'wn':'ok');
  document.getElementById('s6').textContent=d.total;
  var ub=document.getElementById('ul');
  ub.textContent='UpTime : '+up+'%';
  ub.className='ub '+(up>=99?'ug':up>=90?'uo':'ur');
  document.getElementById('dl').textContent=d.dur;
  document.getElementById('nl').textContent=d.now;
  if(d.target)document.getElementById('tl').textContent=d.target;
}

// ============================================================
// Live / Historique
// ============================================================
function sl(v){
  live=v;
  var btn=document.getElementById('bL'),hb=document.getElementById('hb'),ml=document.getElementById('ml');
  if(live){
    btn.innerHTML='&#9654; Live';btn.className='btn bl';
    hb.classList.remove('v');ml.textContent='Live';ml.className='mv';
  } else {
    btn.innerHTML='&#9646;&#9646; Hist.';btn.className='btn bh2';
    hb.classList.add('v');ml.textContent='Historique';ml.className='mv h';
  }
  usb();
}
function togLive(){
  var tot=aD.length,mp=gmp();
  if(live){sl(false);}
  else{vo=Math.max(0,tot-mp);sl(true);uc();}
}
document.getElementById('pc').addEventListener('wheel',function(e){
  e.preventDefault();
  var mp=gmp(),tot=aD.length,st=Math.max(1,Math.floor(mp/8));
  var nv=vo+(e.deltaY>0?st:-st);
  nv=Math.max(0,Math.min(nv,Math.max(0,tot-mp)));
  vo=nv;sl(vo>=Math.max(0,tot-mp));uc();usb();
},{passive:false});

// ============================================================
// Options
// ============================================================
function togOpt(){
  oo=!oo;
  var co=document.getElementById('co'),bt=document.getElementById('bto');
  if(oo){co.classList.remove('hid');bt.innerHTML='&#9650; Options';}
  else{co.classList.add('hid');bt.innerHTML='&#9660; Options';}
}

function applyT(){
  var t=document.getElementById('iT').value.trim();if(!t)return;
  document.getElementById('tl').textContent=t;
  alert('Pour changer la cible, modifiez Target dans le script PowerShell et relancez.');
}
function doReset(){vo=Math.max(0,aD.length-gmp());sl(true);uc();usb();}

// ============================================================
// Chargement donnees
// ============================================================
function loadData(){
  if(pr)return;
  var old=document.getElementById('ds');if(old)old.parentNode.removeChild(old);
  var s=document.createElement('script');
  s.id='ds';s.src=DJP+'?_='+Date.now();
  s.onload=function(){
    if(window.PD){
      var d=window.PD;
      if(d.items.length>ldc){
        d.items.slice(ldc).forEach(function(p){aD.push(p);});
        ldc=d.items.length;
        if(aD.length>3000)aD=aD.slice(aD.length-3000);
      } else if(d.items.length<ldc){
        aD=d.items.slice();ldc=d.items.length;
      }
      uu(d);usb();if(live)uc();
    }
  };
  s.onerror=function(){};
  document.head.appendChild(s);
}

loadData();
setInterval(loadData,2000);
startCountdown();
</script>
</body>
</html>
"@

    try { $html | Set-Content -Path $htmlFile -Encoding UTF8 -ErrorAction Stop }
    catch { Write-Host "  ERREUR HTML : $_" -ForegroundColor Red }
}

# ============================================================
# --- MAIN ---
# ============================================================
$script:startMs = Get-NowMs

Write-Host ""
Write-Host "  Mode : $($ExecutionContext.SessionState.LanguageMode)" -ForegroundColor Cyan
Write-Host "  ============================================" -ForegroundColor Cyan
Write-Host "   Novo Nordisk Ping Monitor v4.4"             -ForegroundColor White
Write-Host "   Cible     : $Target"                        -ForegroundColor Yellow
Write-Host "   Intervalle: $Interval ms"                   -ForegroundColor Yellow
Write-Host "   Rapport   : $htmlFile"                      -ForegroundColor Gray
Write-Host "   Arret     : Ctrl+C"                        -ForegroundColor Red
Write-Host "  ============================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "  Chart.js — emplacements acceptes :" -ForegroundColor Cyan
Write-Host "   $scriptTemp\chartjs.min.js" -ForegroundColor Gray
Write-Host "   $env:USERPROFILE\Documents\chartjs.min.js" -ForegroundColor Gray
Write-Host ""

Write-Host "  Test ping $Target ..." -ForegroundColor Cyan
$testPing = Get-PingTime -TargetHost $Target
if ($testPing -ge 0) {
    Write-Host "  Ping OK : $testPing ms" -ForegroundColor Green
} else {
    Write-Host "  Ping : Timeout (monitoring quand meme)" -ForegroundColor Yellow
}
Write-Host ""

Write-HtmlOnce -target $script:Target
Write-DataJs
Open-Browser -FilePath $htmlFile

Write-Host "  Navigateur ouvert." -ForegroundColor Green
Write-Host "  Ctrl+C pour arreter" -ForegroundColor Gray
Write-Host ""

# ============================================================
# --- Boucle principale ---
# ============================================================
$lastWrite = Get-Date

try {
    while ($true) {

        $val = Get-PingTime -TargetHost $script:Target
        $ts  = Get-NowMs

        $script:pingTs   += $ts
        $script:pingVs   += $val
        $script:pingCount++

        if ($script:pingCount -gt $MaxKeep) {
            $cut              = $script:pingCount - $MaxKeep
            $script:pingTs    = $script:pingTs[$cut..($script:pingCount - 1)]
            $script:pingVs    = $script:pingVs[$cut..($script:pingCount - 1)]
            $script:pingCount = $MaxKeep
        }

        $now = Get-Date
        if (($now - $lastWrite).TotalSeconds -ge $WriteEvery) {
            Write-DataJs
            $lastWrite = $now

            $st      = Calc-Stats
            $elapsed = Get-ElapsedSec
            $hh      = [int]($elapsed / 3600)
            $mm      = [int](($elapsed % 3600) / 60)
            $ss      = $elapsed % 60
            $lv      = if ($val -ge 0) { "$val ms" } else { "Timeout" }
            $col     = if ($val -ge 0) { "Green" } else { "Red" }

            Write-Host ("  [{0:D2}h{1:D2}m{2:D2}s] {3,-12} | Total:{4,5} | Perte:{5,3}%" -f `
                $hh, $mm, $ss, $lv, $script:pingCount, $st.loss) -ForegroundColor $col
        }

        Start-Sleep -Milliseconds $Interval
    }
}
finally {
    Write-Host ""
    Write-Host "  Arret..." -ForegroundColor Yellow
    Write-DataJs
    Write-Host "  Rapport : $htmlFile" -ForegroundColor Gray
    Write-Host "  Arrete." -ForegroundColor Green
    Write-Host ""
}
