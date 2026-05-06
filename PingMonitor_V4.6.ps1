# ============================================================
# SCRIPT  : Novo Nordisk Ping Monitor
# VERSION : 4.6
# AUTEUR  : Novo Nordisk IT - EGUI
# DATE    : 2026-05
# DESCRIPTION : Monitoring de ping — 100% offline.
#               Chart.js embarque depuis cache local.
#               Compatible ConstrainedLanguage strict.
# ------------------------------------------------------------
# INSTALLATION OFFLINE — Chart.js :
#   Telecharger : chart.js@4.4.0/dist/chart.umd.min.js
#   Copier dans : %USERPROFILE%\Documents\chartjs.min.js
#              ou %TEMP%\NovoPingMonitor\chartjs.min.js
# ------------------------------------------------------------
# NAVIGATEUR : Edge ou Chrome recommandes
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
$Interval   = 1000
$MaxKeep    = 3000
$WriteEvery = 2

# ============================================================
# --- Dossier temporaire ---
# ============================================================
$scriptTemp = "$env:TEMP\NovoPingMonitor"
if (-not (Test-Path $scriptTemp)) {
    New-Item -ItemType Directory -Path $scriptTemp -Force | Out-Null
}
$htmlFile = "$scriptTemp\ping_monitor.html"
$dataFile = "$scriptTemp\ping_data.js"
$cmdFile  = "$scriptTemp\ping_cmd.js"

# ============================================================
# --- Variables ---
# ============================================================
$script:Target    = $Target
$script:startTime = Get-Date
$script:pingTs    = @()
$script:pingVs    = @()
$script:pingCount = 0
$script:interval  = $Interval

# ============================================================
# ✅ Fonctions compatibles ConstrainedLanguage
# ============================================================
function Round-Int {
    param([double]$n)
    if (($n - [int]$n) -ge 0.5) { return [int]$n + 1 }
    return [int]$n
}

# ✅ Timestamp propre — evite notation scientifique
function Get-NowMs {
    $epoch = [datetime]"1970-01-01 00:00:00"
    $span  = (Get-Date).ToUniversalTime() - $epoch
    return [long]$span.TotalMilliseconds
}

function Get-ElapsedSec {
    return [int]((Get-Date) - $script:startTime).TotalSeconds
}

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
    $loss  = Round-Int $lossRaw
    $avgV  = 0
    if ($validCnt -gt 0) { $avgV = Round-Int ($sumV / $validCnt) }
    $lastV = -1
    if ($script:pingCount -gt 0) { $lastV = $script:pingVs[$script:pingCount - 1] }
    $minStr = "-1"; if ($validCnt -gt 0) { $minStr = "$minV" }
    $maxStr = "-1"; if ($validCnt -gt 0) { $maxStr = "$maxV" }
    return @{ loss=$loss; uptime=(100-$loss); avgV=$avgV; lastV=$lastV; minStr=$minStr; maxStr=$maxStr }
}

# ✅ Timestamps forces en entier long propre
function Write-DataJs {
    $parts = @()
    for ($i=0; $i -lt $script:pingCount; $i++) {
        $ts = [long]$script:pingTs[$i]
        $v  = [int]$script:pingVs[$i]
        $parts += "{t:$ts,v:$v}"
    }
    $st      = Calc-Stats
    $elapsed = Get-ElapsedSec
    $hh = [int]($elapsed/3600); $mm = [int](($elapsed%3600)/60); $ss = $elapsed%60
    $js = "window.PD={items:[" + ($parts -join ",") + "]," +
          "target:`"$($script:Target)`",startMs:$($script:startMs)," +
          "total:$($script:pingCount),loss:$($st.loss),uptime:$($st.uptime)," +
          "lastV:$($st.lastV),minV:$($st.minStr),maxV:$($st.maxStr),avgV:$($st.avgV)," +
          "interval:$($script:interval)," +
          "dur:`"$("{0:D2}h {1:D2}m {2:D2}s"-f $hh,$mm,$ss)`"," +
          "now:`"$(Get-Date -Format "HH:mm:ss")`"};"
    try { $js | Set-Content -Path $dataFile -Encoding UTF8 -ErrorAction Stop } catch {}
}

function Read-CmdFile {
    if (-not (Test-Path $cmdFile)) { return }
    try {
        $raw = Get-Content -Path $cmdFile -Raw -ErrorAction SilentlyContinue
        if (-not $raw) { return }
        if ($raw -match '"interval"\s*:\s*(\d+)') {
            $newInterval = [int]$Matches[1]
            if ($newInterval -ge 200 -and $newInterval -le 60000) {
                if ($newInterval -ne $script:interval) {
                    $script:interval = $newInterval
                    Write-Host "  Intervalle -> $newInterval ms" -ForegroundColor Cyan
                }
            }
        }
        Remove-Item $cmdFile -Force -ErrorAction SilentlyContinue
    } catch {}
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
            Write-Host "  Chart.js : telecharge OK" -ForegroundColor Green
            return "<script>`n$src`n</script>"
        }
    } catch { Write-Host "  Chart.js : telechargement impossible" -ForegroundColor Red }
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
<title>NN Ping Monitor v4.6</title>
$chartJsTag
<style>
:root{
  --bg:#1a1a2e;--surface:#16213e;--surface2:#0d1b2a;
  --border:#0f3460;--border2:#1e3050;--border3:#0f2040;
  --text:#e0e0e0;--text2:#a0b0c0;--text3:#556;--text4:#889;
  --accent:#4cc9f0;--accent2:#0f3460;
  --ok:#4ade80;--warn:#fb923c;--danger:#f87171;
  --live-bg:#143a20;--live-c:#4ade80;
  --hist-bg:#3a2a08;--hist-c:#fb923c;
  --apply-bg:#0f3460;--apply-c:#4cc9f0;
  --reset-bg:#5a1515;--reset-c:#f87171;
  --tog-bg:transparent;--tog-c:#4466aa;--tog-bd:#1e3050;
  --sb-track:#111927;--sb-bg:#0d1117;
  --sb-live:#1a5a2a;--sb-hist:#1e4a7a;
  --inp-bg:#0d1b2a;--inp-bd:#0f3460;
  --grid:rgba(80,80,120,.15);--grid2:rgba(80,80,120,.2);
  --tick:#556;--tickY:#ccc;
  --cline:rgba(80,255,100,.9);--cfill:rgba(50,220,80,.08);
  --ctobg:rgba(255,60,60,.2);--ctobd:rgba(255,60,60,.6);
  --ptok:rgba(120,255,140,.95);--ptokb:rgba(80,255,100,1);
  --ptto:rgba(255,50,50,.95);--pttob:rgba(255,50,50,1);
  --mbar-c:rgba(160,190,255,.6);
  --mbar-lbl:rgba(180,210,255,.9);
  --tobar-c:rgba(255,80,80,.75);
}
[data-theme="light"]{
  --bg:#f0f4f8;--surface:#ffffff;--surface2:#e8edf5;
  --border:#b0c0d8;--border2:#c8d4e8;--border3:#c0cfe0;
  --text:#0f1923;--text2:#3a5070;--text3:#8090a8;--text4:#607090;
  --accent:#0063be;--accent2:#dde9f8;
  --ok:#007a5e;--warn:#b86000;--danger:#c0202e;
  --live-bg:#d4f0e0;--live-c:#007a5e;
  --hist-bg:#fdefd4;--hist-c:#b86000;
  --apply-bg:#dde9f8;--apply-c:#0063be;
  --reset-bg:#fde8e8;--reset-c:#c0202e;
  --tog-bg:#eef2f8;--tog-c:#3a5070;--tog-bd:#b0c0d8;
  --sb-track:#dde4ee;--sb-bg:#e8edf5;
  --sb-live:#007a5e;--sb-hist:#0063be;
  --inp-bg:#ffffff;--inp-bd:#b0c0d8;
  --grid:rgba(100,120,160,.12);--grid2:rgba(100,120,160,.18);
  --tick:#8090a8;--tickY:#3a5070;
  --cline:rgba(0,130,70,.9);--cfill:rgba(0,180,100,.08);
  --ctobg:rgba(192,32,46,.15);--ctobd:rgba(192,32,46,.5);
  --ptok:rgba(0,140,80,.95);--ptokb:rgba(0,120,60,1);
  --ptto:rgba(200,30,40,.95);--pttob:rgba(200,30,40,1);
  --mbar-c:rgba(40,80,180,.5);
  --mbar-lbl:rgba(20,60,160,.85);
  --tobar-c:rgba(192,32,46,.65);
}
*{margin:0;padding:0;box-sizing:border-box}
body{background:var(--bg);color:var(--text);font-family:'Segoe UI',Consolas,monospace;
     display:flex;flex-direction:column;height:100vh;overflow:hidden;
     transition:background .25s,color .25s}
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
.ub{font-size:.95em;font-weight:bold;padding:3px 10px;
    border-radius:20px;border:2px solid currentColor;white-space:nowrap}
.ug{color:var(--ok)}.uo{color:var(--warn)}.ur{color:var(--danger)}
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
.cw{flex:1;position:relative;padding:8px 14px 4px;overflow:hidden;min-height:60px}
.hb{display:none;position:absolute;top:10px;right:16px;
    background:var(--hist-bg);color:var(--hist-c);font-size:.76em;font-weight:bold;
    padding:2px 9px;border-radius:5px;border:1px solid var(--hist-c);
    pointer-events:none;z-index:10}
.hb.v{display:block}
.sbw{background:var(--sb-bg);height:16px;flex-shrink:0;
     border-top:1px solid var(--border3);border-bottom:1px solid var(--border3);
     position:relative;cursor:pointer;user-select:none}
.sbt{position:absolute;top:3px;bottom:3px;left:0;right:0;
     background:var(--sb-track);border-radius:5px;margin:0 4px}
.sbh{position:absolute;top:0;bottom:0;border-radius:5px;min-width:20px;
     cursor:grab;transition:filter .15s}
.sbh:hover,.sbh.d{filter:brightness(1.3)}
.sbh.lm{background:var(--sb-live)}
.sbh.hm{background:var(--sb-hist)}
.sbd{position:absolute;right:4px;top:50%;transform:translateY(-50%);
     width:5px;height:5px;border-radius:50%;background:var(--ok);animation:pl 1.2s infinite}
@keyframes pl{0%,100%{opacity:1}50%{opacity:.2}}
.cb{background:var(--surface);border-top:1px solid var(--border);flex-shrink:0}
.ch{display:flex;align-items:center;justify-content:space-between;
    padding:5px 16px;gap:8px;min-height:36px}
.chl{display:flex;align-items:center;gap:8px;flex-wrap:wrap}
.chr{display:flex;align-items:center;gap:6px;flex-shrink:0}
.co{display:flex;gap:10px;align-items:center;flex-wrap:wrap;
    padding:6px 16px 8px;border-top:1px solid var(--border)}
.co.hid{display:none}
.og{display:flex;align-items:center;gap:10px;flex-wrap:wrap}
.og-sep{width:1px;height:24px;background:var(--border2);flex-shrink:0}
.og-title{color:var(--text3);font-size:.7em;font-weight:700;
          text-transform:uppercase;letter-spacing:.5px;white-space:nowrap}
.ci{display:flex;align-items:center;gap:5px}
.ci label{color:var(--text4);font-size:.78em;white-space:nowrap}
input[type=text]{background:var(--inp-bg);border:1px solid var(--inp-bd);
                 color:var(--accent);padding:3px 8px;border-radius:4px;
                 font-size:.82em;width:165px;font-family:Consolas,monospace;font-weight:bold}
input[type=text]:focus{outline:2px solid var(--accent)}
.sg{display:flex;align-items:center;gap:5px}
.sg label{color:var(--text3);font-size:.75em;white-space:nowrap;min-width:52px;text-align:right}
.sg .sv2{color:var(--accent);font-weight:bold;font-size:.78em;min-width:42px}
input[type=range]{width:100px;accent-color:var(--accent);cursor:pointer}
select{background:var(--inp-bg);border:1px solid var(--inp-bd);
       color:var(--accent);padding:2px 5px;border-radius:4px;
       font-size:.78em;font-family:Consolas,monospace;font-weight:bold;cursor:pointer}
.btn{padding:4px 11px;border:none;border-radius:4px;cursor:pointer;
     font-size:.78em;font-weight:bold;white-space:nowrap;transition:opacity .15s}
.btn:hover{opacity:.8}
.ba{background:var(--apply-bg);color:var(--apply-c)}
.br{background:var(--reset-bg);color:var(--reset-c)}
.bl{background:var(--live-bg);color:var(--live-c);min-width:78px}
.bh2{background:var(--hist-bg);color:var(--hist-c);min-width:78px}
.bt{background:var(--tog-bg);border:1px solid var(--tog-bd);
    color:var(--tog-c);font-size:.72em;padding:2px 8px;border-radius:4px;cursor:pointer}
.bt:hover,.thbtn:hover{filter:brightness(1.15)}
.thbtn{background:var(--tog-bg);border:1px solid var(--tog-bd);
       color:var(--tog-c);font-size:.72em;padding:2px 10px;
       border-radius:4px;cursor:pointer;white-space:nowrap}
.dot{width:8px;height:8px;border-radius:50%;display:inline-block;flex-shrink:0}
.do{background:var(--ok);animation:pl 1.2s infinite}
.dt{background:var(--danger)}
</style>
</head>
<body>

<div class="hdr">
  <div class="hl">
    <span class="dot do" id="sd"></span>
    <h1>Novo Nordisk Ping Monitor &mdash; <span class="ts" id="tl">$target</span></h1>
    <span class="vtag">v4.6</span>
  </div>
  <div class="hr2">
    <span class="dur" id="dl">--</span>
    <span class="ub ug" id="ul">UpTime : --%</span>
  </div>
</div>

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

<div class="cw">
  <div id="hb" class="hb">Molette ou scrollbar pour naviguer</div>
  <canvas id="pc"></canvas>
</div>

<div class="sbw">
  <div class="sbt" id="sbt">
    <div class="sbh lm" id="sbh">
      <div class="sbd" id="sbdot"></div>
    </div>
  </div>
</div>

<div class="cb">
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
      <button class="thbtn" id="thBtn" onclick="togTheme()">&#9728; Light</button>
      <button class="bt" id="bto" onclick="togOpt()">&#9660; Options</button>
    </div>
  </div>
  <div class="co hid" id="co">
    <div class="og">
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
        <span class="sv2" id="vD">0 (ligne)</span>
      </div>
      <div class="og-sep"></div>
      <span class="og-title">Intervalle ping</span>
      <div class="sg">
        <label>Intervalle :</label>
        <select id="selInt" onchange="saveInterval(this.value)">
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
      <div class="sg" style="gap:4px">
        <span style="color:var(--text3);font-size:.75em">Prochain :</span>
        <span class="sv2" id="sNext">--</span>
      </div>
    </div>
  </div>
</div>

<script>
var DJP='$dataFileJs';
var aD=[],live=true,vo=0,pr=false,ldc=0,oo=false;
var sbdrag=false,sbsx=0,sbsvo=0;
var darkMode=true;
var curInterval=1000,nextIn=1000,cdTimer=null;

// ============================================================
// Theme
// ============================================================
function togTheme(){
  darkMode=!darkMode;
  document.documentElement.setAttribute('data-theme',darkMode?'dark':'light');
  document.getElementById('thBtn').innerHTML=darkMode?'&#9728; Light':'&#9790; Dark';
  uc();
}

// ============================================================
// Intervalle
// ============================================================
function saveInterval(val){
  curInterval=parseInt(val,10);
  startCD();
}
function startCD(){
  if(cdTimer)clearInterval(cdTimer);
  nextIn=curInterval;
  updNxt();
  cdTimer=setInterval(function(){
    nextIn-=200;
    if(nextIn<=0)nextIn=curInterval;
    updNxt();
  },200);
}
function updNxt(){
  document.getElementById('sNext').textContent=(nextIn/1000).toFixed(1)+'s';
}

// ============================================================
// ✅ Helpers timestamps — protection NaN et notation scientifique
// ============================================================
function ft(ms){
  var n=parseInt(ms,10);
  if(isNaN(n)||n<=0)return '--:--:--';
  var d=new Date(n);
  return('0'+d.getHours()).slice(-2)+':'+
         ('0'+d.getMinutes()).slice(-2)+':'+
         ('0'+d.getSeconds()).slice(-2);
}
function fm(ms){
  var n=parseInt(ms,10);
  if(isNaN(n)||n<=0)return '--:--';
  var d=new Date(n);
  return('0'+d.getHours()).slice(-2)+':'+('0'+d.getMinutes()).slice(-2);
}

// ============================================================
// ✅ Plugin barres verticales — enregistre AVANT new Chart()
// ============================================================
Chart.register({
  id:'vlines',
  afterDraw:function(chart){
    if(!chart.config._vlines)return;
    var data=chart.config._vlines;
    var hasTo =(data.toLines  && data.toLines.length >0);
    var hasMin=(data.minLines && data.minLines.length>0);
    if(!hasTo&&!hasMin)return;

    var ctx2=chart.ctx;
    var xs=chart.scales.x,ys=chart.scales.y;
    if(!xs||!ys)return;
    var top=ys.top,bot=ys.bottom;
    var s=getComputedStyle(document.documentElement);

    ctx2.save();

    // ---- Barres timeout : rouge epais visible ----
    if(hasTo){
      ctx2.strokeStyle=s.getPropertyValue('--tobar-c').trim()||'rgba(255,80,80,.75)';
      ctx2.lineWidth=2;
      ctx2.setLineDash([]);
      ctx2.globalAlpha=0.85;
      data.toLines.forEach(function(idx){
        try{
          var x=xs.getPixelForValue(idx);
          if(x>=xs.left&&x<=xs.right){
            ctx2.beginPath();ctx2.moveTo(x,top);ctx2.lineTo(x,bot);ctx2.stroke();
          }
        }catch(e){}
      });
    }

    // ---- Barres minutes : bleu/gris avec label ----
    if(hasMin){
      var mColor=s.getPropertyValue('--mbar-c').trim()||'rgba(160,190,255,.6)';
      var mText =s.getPropertyValue('--mbar-lbl').trim()||'rgba(180,210,255,.9)';
      ctx2.strokeStyle=mColor;
      ctx2.lineWidth=1.5;
      ctx2.setLineDash([4,3]);
      ctx2.globalAlpha=0.8;

      // ✅ Deduplication : une seule barre par label "HH:mm"
      var drawn={};
      data.minLines.forEach(function(ml){
        if(drawn[ml.label])return;
        drawn[ml.label]=true;
        try{
          var x=xs.getPixelForValue(ml.x);
          if(x>=xs.left&&x<=xs.right){
            // Ligne
            ctx2.beginPath();ctx2.moveTo(x,top);ctx2.lineTo(x,bot);ctx2.stroke();
            // Label vertical
            if(bot-top>50){
              ctx2.save();
              ctx2.setLineDash([]);
              ctx2.globalAlpha=1;
              ctx2.fillStyle=mText;
              ctx2.font='bold 10px Consolas,monospace';
              ctx2.translate(x+5,Math.min(top+90,bot-8));
              ctx2.rotate(-Math.PI/2);
              ctx2.fillText(ml.label,0,0);
              ctx2.restore();
            }
          }
        }catch(e){}
      });
    }

    ctx2.restore();
  }
});

// ============================================================
// Chart.js — cree APRES Chart.register
// ============================================================
var cx=document.getElementById('pc').getContext('2d');
var ch=new Chart(cx,{
  type:'line',
  data:{labels:[],datasets:[
    {label:'ms',data:[],
     borderColor:'rgba(80,255,100,.9)',backgroundColor:'rgba(50,220,80,.08)',
     borderWidth:2,pointRadius:[],pointBackgroundColor:[],pointBorderColor:[],
     fill:true,tension:.2,spanGaps:false,order:2},
    {label:'TO',data:[],type:'bar',
     backgroundColor:'rgba(255,60,60,.2)',borderColor:'rgba(255,60,60,.6)',
     borderWidth:1,barPercentage:.4,categoryPercentage:1,order:1}
  ]},
  options:{
    responsive:true,maintainAspectRatio:false,animation:false,
    interaction:{mode:'index',intersect:false},
    plugins:{
      legend:{display:false},
      tooltip:{callbacks:{label:function(c){
        return c.datasetIndex===0?(c.parsed.y===null?'Timeout':c.parsed.y+' ms'):'';
      }}}
    },
    scales:{
      x:{ticks:{color:'#556',maxTicksLimit:12,font:{size:9,family:'Consolas'},maxRotation:0},
         grid:{color:'rgba(80,80,120,.15)'}},
      y:{min:0,
         ticks:{color:'#ccc',font:{size:11,family:'Consolas',weight:'bold'},
                callback:function(v){return v+'ms';}},
         grid:{color:'rgba(80,80,120,.2)'}}
    }
  }
});

// ✅ Donnees barres attachees a chart.config (accessible par le plugin)
ch.config._vlines={toLines:[],minLines:[]};

// ============================================================
// Helpers
// ============================================================
function gmp(){return parseInt(document.getElementById('sP').value,10);}
function gds(n,w){
  var s=parseInt(document.getElementById('sD').value,10);
  if(s===0)return 0;
  if(s>0)return s;
  var p=w/Math.max(n,1);
  if(p>=12)return 5;if(p>=7)return 3;if(p>=4)return 2;if(p>=2)return 1;return 0;
}
function updDL(v){
  document.getElementById('vD').textContent=(+v===0)?'0 (ligne)':v+'px';
}

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
// ✅ Graphique — une seule mise a jour par cycle
// ============================================================
function uc(){
  var mp=gmp(),tot=aD.length,cw=cx.canvas.offsetWidth;
  var mv=Math.max(0,tot-mp);
  if(live){vo=mv;}else{vo=Math.max(0,Math.min(vo,mv));}

  var sl2=aD.slice(vo,vo+mp);
  var n=sl2.length,ds=gds(n,cw);
  var lb=[],vs=[],tv=[],pr2=[],pb=[],pd=[];
  var toLines=[],minLines=[];

  // ✅ prevMinKey base sur timestamp reel converti correctement
  var prevMinKey='__INIT__';

  var s=getComputedStyle(document.documentElement);
  var ptok=s.getPropertyValue('--ptok').trim()||'rgba(120,255,140,.95)';
  var ptokb=s.getPropertyValue('--ptokb').trim()||'rgba(80,255,100,1)';
  var ptto=s.getPropertyValue('--ptto').trim()||'rgba(255,50,50,.95)';
  var pttob=s.getPropertyValue('--pttob').trim()||'rgba(255,50,50,1)';

  sl2.forEach(function(d,i){
    // ✅ Forcer entier pour eviter NaN
    var ts=parseInt(d.t,10);
    var timeStr=ft(ts);
    // ✅ Cle minute basee sur timestamp reel
    var minKey=fm(ts);

    // ✅ Barre de minute : seulement si la minute change ET i>0
    if(i>0 && minKey!=='--:--' && minKey!==prevMinKey){
      minLines.push({x:i, label:minKey});
    }
    prevMinKey=minKey;

    // ✅ Label axe X : visible seulement au changement de minute
    if(i>0 && minKey!==fm(parseInt(sl2[i-1].t,10))){
      lb.push(timeStr);
    } else {
      lb.push('');
    }

    var v=parseInt(d.v,10);
    if(v<0){
      vs.push(null);tv.push(1);
      pr2.push(ds>0?Math.max(ds,3):0);
      pb.push(ptto);pd.push(pttob);
      toLines.push(i);
    } else {
      vs.push(v);tv.push(null);
      pr2.push(ds);
      pb.push(ptok);pd.push(ptokb);
    }
  });

  // Mise a jour donnees
  ch.data.labels=lb;
  ch.data.datasets[0].data=vs;
  ch.data.datasets[0].pointRadius=pr2;
  ch.data.datasets[0].pointBackgroundColor=pb;
  ch.data.datasets[0].pointBorderColor=pd;
  ch.data.datasets[1].data=tv;

  // Couleurs theme
  ch.data.datasets[0].borderColor=s.getPropertyValue('--cline').trim();
  ch.data.datasets[0].backgroundColor=s.getPropertyValue('--cfill').trim();
  ch.data.datasets[1].backgroundColor=s.getPropertyValue('--ctobg').trim();
  ch.data.datasets[1].borderColor=s.getPropertyValue('--ctobd').trim();
  ch.options.scales.x.ticks.color=s.getPropertyValue('--tick').trim();
  ch.options.scales.x.grid.color=s.getPropertyValue('--grid').trim();
  ch.options.scales.y.ticks.color=s.getPropertyValue('--tickY').trim();
  ch.options.scales.y.grid.color=s.getPropertyValue('--grid2').trim();

  // ✅ Barres via chart.config._vlines — accessible par le plugin
  ch.config._vlines={toLines:toLines,minLines:minLines};

  var vv=vs.filter(function(v2){return v2!==null;});
  if(vv.length>0)ch.options.scales.y.max=Math.ceil(Math.max.apply(null,vv)/10)*10+10;

  // ✅ Un seul update
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
  if(d.interval&&d.interval!==curInterval){
    curInterval=d.interval;
    var sel=document.getElementById('selInt');
    for(var i=0;i<sel.options.length;i++){
      if(parseInt(sel.options[i].value,10)===curInterval){sel.selectedIndex=i;break;}
    }
    startCD();
  }
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
  if(live){sl(false);}else{vo=Math.max(0,tot-mp);sl(true);uc();}
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
// ✅ Chargement donnees — UN SEUL appel uc() par cycle
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
        // ✅ Forcer parseInt sur chaque item pour eviter NaN
        d.items.slice(ldc).forEach(function(p){
          aD.push({t:parseInt(p.t,10),v:parseInt(p.v,10)});
        });
        ldc=d.items.length;
        if(aD.length>3000)aD=aD.slice(aD.length-3000);
      } else if(d.items.length<ldc){
        aD=d.items.map(function(p){
          return {t:parseInt(p.t,10),v:parseInt(p.v,10)};
        });
        ldc=d.items.length;
      }
      uu(d);
      usb();
      // ✅ Un seul appel uc() ici
      if(live)uc();
    }
  };
  s.onerror=function(){};
  document.head.appendChild(s);
}

// ✅ Un seul timer de chargement
loadData();
setInterval(loadData,2000);
startCD();
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
Write-Host "   Novo Nordisk Ping Monitor v4.6"             -ForegroundColor White
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

$lastWrite = Get-Date
$lastPing  = Get-Date

try {
    while ($true) {
        $now = Get-Date
        Read-CmdFile

        $sinceLastPing = ($now - $lastPing).TotalMilliseconds
        if ($sinceLastPing -ge $script:interval) {
            $val = Get-PingTime -TargetHost $script:Target
            $ts  = Get-NowMs
            $script:pingTs   += $ts
            $script:pingVs   += $val
            $script:pingCount++
            $lastPing = $now

            if ($script:pingCount -gt $MaxKeep) {
                $cut              = $script:pingCount - $MaxKeep
                $script:pingTs    = $script:pingTs[$cut..($script:pingCount - 1)]
                $script:pingVs    = $script:pingVs[$cut..($script:pingCount - 1)]
                $script:pingCount = $MaxKeep
            }
        }

        $sinceLW = ($now - $lastWrite).TotalSeconds
        if ($sinceLW -ge $WriteEvery) {
            Write-DataJs
            $lastWrite = $now

            $st      = Calc-Stats
            $elapsed = Get-ElapsedSec
            $hh      = [int]($elapsed / 3600)
            $mm      = [int](($elapsed % 3600) / 60)
            $ss      = $elapsed % 60
            $lv      = if ($script:pingCount -gt 0 -and $script:pingVs[$script:pingCount-1] -ge 0) {
                          "$($script:pingVs[$script:pingCount-1]) ms"
                       } else { "Timeout" }
            $col = if ($lv -ne "Timeout") { "Green" } else { "Red" }

            Write-Host ("  [{0:D2}h{1:D2}m{2:D2}s] {3,-12} | Total:{4,5} | Perte:{5,3}% | Int:{6}ms" -f `
                $hh, $mm, $ss, $lv, $script:pingCount, $st.loss, $script:interval) -ForegroundColor $col
        }

        Start-Sleep -Milliseconds 100
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
