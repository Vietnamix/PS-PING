# PS-PING — Ping Monitor

> Moniteur de ping en temps réel pour Windows : un script PowerShell autonome qui génère un tableau de bord web interactif, **100 % hors ligne**.

![Version](https://img.shields.io/badge/version-4.7-blue)
![PowerShell](https://img.shields.io/badge/PowerShell-5.1%2B-5391FE?logo=powershell&logoColor=white)
![Platform](https://img.shields.io/badge/plateforme-Windows-0078D6?logo=windows&logoColor=white)
![Offline](https://img.shields.io/badge/mode-100%25%20offline-success)
![License](https://img.shields.io/badge/licence-MIT-green)

PS-PING surveille en continu la latence vers une cible (par défaut `8.8.8.8`), enregistre chaque mesure, et affiche un graphe Chart.js qui se rafraîchit tout seul dans votre navigateur. Aucune installation, aucune dépendance système : un seul fichier `.ps1`.

---

## 📸 Preview

<p align="center">
  <img src="PS_PING_2026-06-02.png" alt="PS_NCDU" width="90%">
</p>

---

## Sommaire

- [Aperçu](#aperçu)
- [Fonctionnalités](#fonctionnalités)
- [Prérequis](#prérequis)
- [Installation](#installation)
- [Installation de Chart.js (mode hors ligne)](#installation-de-chartjs-mode-hors-ligne)
- [Utilisation](#utilisation)
- [Configuration](#configuration)
- [L'interface](#linterface)
- [Architecture / fonctionnement](#architecture--fonctionnement)
- [ConstrainedLanguage](#constrainedlanguage)
- [Dépannage](#dépannage)
- [Structure des fichiers générés](#structure-des-fichiers-générés)
- [Changelog](#changelog)
- [Limitations connues](#limitations-connues)
- [Contribuer](#contribuer)
- [Licence](#licence)

---

## Aperçu

Au lancement, le script :

1. effectue un ping de test sur la cible ;
2. génère une page HTML autonome dans `%TEMP%\PingMonitor` ;
3. ouvre cette page dans votre navigateur ;
4. continue à pinger en boucle et à écrire les données, que la page recharge automatiquement.

Le tableau de bord affiche la latence, les pertes, l'uptime, les min/max/moyenne, et permet de naviguer dans l'historique (jusqu'à 3000 points) sans interrompre la mesure.

> 💡 Pensez à ajouter ici une capture d'écran : `docs/screenshot.png`
>
> `![Capture du tableau de bord](docs/screenshot.png)`

---

## Fonctionnalités

- **Graphe temps réel** — latence tracée avec Chart.js, mise à jour fluide (sans animation parasite).
- **Détection des timeouts** — barres rouges verticales sur le graphe + comptage des pertes.
- **Repères temporels** — barres verticales avec libellé `HH:mm` à chaque changement de minute.
- **Statistiques live** — dernier ping, min, max, moyenne, % de perte, uptime, durée, total.
- **Mode Live / Historique** — la vue suit le temps réel, ou se fige pour explorer le passé (molette ou scrollbar).
- **Thème clair / sombre** — bascule en un clic, toutes les couleurs s'adaptent.
- **Réglages d'affichage** — nombre de points visibles et taille des points.
- **100 % hors ligne** — Chart.js est embarqué directement dans la page depuis un cache local.
- **Compatible ConstrainedLanguage** — pour les environnements PowerShell verrouillés (voir [section dédiée](#constrainedlanguage)).
- **Relance automatique depuis l'ISE** — détecte l'ISE et relance dans une console `powershell.exe`.
- **Écriture atomique des données** — aucune lecture de fichier tronqué côté navigateur.

---

## Prérequis

| Composant | Détail |
|-----------|--------|
| OS | Windows |
| PowerShell | 5.1 ou supérieur |
| Navigateur | Edge ou Chrome recommandés (Firefox supporté ; éviter Internet Explorer) |
| Chart.js | `chart.js@4.4.0` — embarqué localement (voir ci-dessous) |
| Réseau | Aucun (offline) — un accès Internet est seulement utile pour télécharger Chart.js la première fois |

---

## Installation

```powershell
# 1. Cloner le dépôt
git clone https://github.com/<votre-compte>/ps-ping.git
cd ps-ping

# 2. (Optionnel) débloquer le fichier téléchargé
Unblock-File .\PS-PING_v4.7.ps1

# 3. Lancer
powershell -NoProfile -ExecutionPolicy Bypass -File .\PS-PING_v4.7.ps1
```

> Si la stratégie d'exécution bloque le script, le lancement ci-dessus avec `-ExecutionPolicy Bypass` contourne le problème pour cette session uniquement, sans modifier les réglages de la machine.

---

## Installation de Chart.js (mode hors ligne)

Pour fonctionner sans Internet, le script embarque Chart.js **directement dans la page**. Il cherche un fichier local dans cet ordre :

```
%TEMP%\PingMonitor\chartjs.min.js
%TEMP%\PingMonitor\chart.min.js
%USERPROFILE%\Documents\chartjs.min.js
%USERPROFILE%\Documents\chart.min.js
%USERPROFILE%\Desktop\chartjs.min.js
%USERPROFILE%\Desktop\chart.min.js
```

**Pour préparer le cache une seule fois :**

1. Téléchargez `chart.umd.min.js` depuis la version 4.4.0 de Chart.js.
2. Renommez-le `chartjs.min.js`.
3. Déposez-le dans `%USERPROFILE%\Documents` (ou un autre emplacement de la liste).

Le script le recopie ensuite automatiquement dans `%TEMP%\PingMonitor` pour les fois suivantes.

> Si aucun fichier local n'est trouvé, le script **tente** un téléchargement depuis le CDN jsDelivr, puis se rabat sur une balise CDN distante. ⚠️ Le téléchargement nécessite `FullLanguage` (voir [ConstrainedLanguage](#constrainedlanguage)) et un accès réseau.

---

## Utilisation

```powershell
.\PS-PING_v4.7.ps1
```

Une fois lancé :

- La console affiche un log synthétique toutes les 2 secondes : durée, dernier ping, total, % de perte, intervalle.
- Le navigateur s'ouvre sur le tableau de bord.
- **`Ctrl+C`** arrête proprement le monitoring (une dernière écriture est garantie).

Exemple de sortie console :

```
  [00h02m14s] 14 ms        | Total:  134 | Perte:  0% | Int:1000ms
  [00h02m16s] Timeout      | Total:  136 | Perte:  1% | Int:1000ms
  [00h02m18s] 13 ms        | Total:  138 | Perte:  1% | Int:1000ms
```

---

## Configuration

Les paramètres se modifient en tête du script, dans la section `--- Configuration ---` :

```powershell
$Target     = "8.8.8.8"   # cible du ping (IP ou nom d'hôte)
$Interval   = 1000        # intervalle entre pings, en millisecondes
$MaxKeep    = 3000        # nombre max de points conservés en mémoire
$WriteEvery = 2           # fréquence d'écriture du fichier de données, en secondes
$TrimBuffer = 200         # marge avant de tronquer l'historique (perf)
```

| Paramètre | Rôle | Conseil |
|-----------|------|---------|
| `$Target` | Hôte surveillé | IP ou FQDN. Se change **dans le script** puis relance |
| `$Interval` | Cadence des pings | 1000 ms est un bon compromis. Plage utile : 200 ms → 60 s |
| `$MaxKeep` | Profondeur d'historique | 3000 points ≈ 50 min à 1 ping/s |
| `$WriteEvery` | Rafraîchissement du rapport | Plus bas = plus réactif, mais plus d'I/O disque |
| `$TrimBuffer` | Optimisation mémoire | Évite de retailler le tableau à chaque ping |

> ℹ️ **La cible et l'intervalle ne sont pas modifiables depuis la page web.** Une page ouverte en `file://` ne peut pas piloter le processus PowerShell. Ces réglages sont donc affichés en lecture seule dans l'interface, et se changent dans le script avant relance.

---

## L'interface

**En-tête**
- Pastille de statut (verte = OK, rouge = timeout), cible, version.
- Durée de monitoring et badge **UpTime** (vert ≥ 99 %, orange ≥ 90 %, rouge sinon).

**Bandeau de statistiques**
- Heure courante · mode (Live / Historique).
- Dernier · Min · Max · Moyenne · Perte · Total.

**Graphe**
- Courbe de latence + barres rouges pour les timeouts.
- Barres pointillées + libellé `HH:mm` aux changements de minute.

**Barre de navigation (scrollbar)**
- Verte en mode Live, bleue en mode Historique.
- Cliquer/glisser pour parcourir l'historique.

**Barre d'outils (bas)**
- **Cible** (affichage), **▶ Live / ⏸ Hist.**, **↻ Vue** (recadrer).
- **☀ Light / ☾ Dark** (thème), **▼ Options**.

**Options**
- *Points* : nombre de points affichés (10 → 3000).
- *Taille pts* : 0 (ligne seule) → 10 px.
- *Intervalle* : affichage en lecture seule + compte à rebours du prochain ping.

**Navigation rapide**
- **Molette** sur le graphe : reculer / avancer dans le temps (sort du Live automatiquement).
- Bouton **▶ Live** : revenir au temps réel.

---

## Architecture / fonctionnement

PS-PING repose sur un découplage simple entre le **collecteur** (PowerShell) et l'**affichage** (page HTML), reliés par un fichier de données.

```
┌─────────────────────┐        écrit          ┌──────────────────┐
│   PS-PING_v4.7.ps1  │ ───────────────────▶ │  ping_data.js    │
│  (boucle de ping)   │   (écriture atomique) │  window.PD = {…} │
└─────────────────────┘                       └──────────────────┘
          │ génère une fois                            ▲
          ▼                                            │ recharge toutes les 2 s
┌─────────────────────┐        lit / affiche           │
│  ping_monitor.html  │ ───────────────────────────────┘
│  (Chart.js + UI)    │
└─────────────────────┘
```

**Côté PowerShell** — une boucle tourne ~10 fois/s avec deux cadences indépendantes :
- déclencher un ping tous les `$Interval` ms ;
- réécrire `ping_data.js` tous les `$WriteEvery` s.

L'écriture est **atomique** (fichier `.tmp` puis `Move-Item -Force`) pour que la page ne lise jamais un fichier à moitié écrit. Les timestamps sont forcés en entiers longs et les latences en entiers, ce qui évite tout `NaN` ou notation scientifique côté JavaScript.

**Côté navigateur** — la page (générée une seule fois) recharge `ping_data.js` en boucle via une balise `<script>` anti-cache. Elle ne charge que les **nouveaux** points (chargement par delta) et redessine le graphe en un seul `update` sans animation. La convention `-1 = timeout` est utilisée de bout en bout.

---

## ConstrainedLanguage

Le script est conçu pour rester compatible avec le mode **ConstrainedLanguage** de PowerShell (environnements verrouillés par AppLocker / WDAC) : pas de `[math]::Round` problématique, pas de types .NET interdits dans le chemin critique (ping, stats, génération HTML).

⚠️ **Seule exception** : le *fallback* de téléchargement de Chart.js utilise `System.Net.WebClient`, qui est **bloqué en ConstrainedLanguage strict**. Dans ce cas :
- le téléchargement échoue **proprement** (try/catch) ;
- il suffit alors de **déposer manuellement** `chartjs.min.js` dans un des emplacements listés plus haut.

Le mode de langage courant est affiché au démarrage (`Mode : …`).

---

## Dépannage

| Symptôme | Cause probable | Solution |
|----------|----------------|----------|
| Le graphe reste vide | Chart.js introuvable + pas d'accès CDN | Déposer `chartjs.min.js` dans `%USERPROFILE%\Documents` |
| « Allow blocked content » dans le navigateur | Internet Explorer bloque le JS local | Ouvrir le rapport avec Edge ou Chrome |
| Le script se relance dans une autre fenêtre | Lancé depuis l'ISE | Comportement normal (l'ISE est mal adapté) |
| « telechargement impossible (CL strict…) » | ConstrainedLanguage + hors ligne | Déposer Chart.js manuellement |
| L'intervalle ne change pas depuis la page | Limitation `file://` (par design) | Modifier `$Interval` dans le script et relancer |
| `running scripts is disabled` | ExecutionPolicy | Lancer avec `-ExecutionPolicy Bypass` |

---

## Structure des fichiers générés

Tout est créé dans `%TEMP%\PingMonitor` :

```
%TEMP%\PingMonitor\
├── ping_monitor.html   # le tableau de bord (généré une fois)
├── ping_data.js        # les données rafraîchies en continu
└── chartjs.min.js      # cache local de Chart.js (si trouvé/téléchargé)
```

Ces fichiers sont temporaires ; ils peuvent être supprimés sans risque entre deux sessions.

---

## Changelog

### v4.7
- Suppression du canal de commande mort (`ping_cmd.js` / lecture de commandes) : le sélecteur d'intervalle ne pouvait pas écrire sur disque depuis `file://`, il est désormais en lecture seule.
- **Écriture atomique** de `ping_data.js` (`.tmp` + `Move-Item`) : plus de lecture partielle côté navigateur.
- **Trim allégé** : l'historique n'est retaillé que tous les `+TrimBuffer` pings au lieu de chaque tick.
- Note ConstrainedLanguage clarifiée (limite du téléchargement Chart.js).
- Commentaires détaillés ajoutés sur l'ensemble des fonctions PowerShell et JavaScript.

### v4.6
- Chart.js embarqué depuis cache local, timestamps en entiers longs (anti-notation scientifique), déduplication des barres de minute, thème clair/sombre.

---

## Limitations connues

- **Timeout de ping non paramétrable** : `Test-Connection` (PS 5.1) n'expose pas de paramètre de timeout. Sur une cible injoignable, l'attente suit le comportement par défaut. Une alternative avec timeout précis (`System.Net.NetworkInformation.Ping`) est fournie **en commentaire** dans `Get-PingTime`, mais elle nécessite `FullLanguage`.
- **Cible/intervalle non modifiables depuis l'UI** (limitation `file://`, voir ci-dessus).
- **Windows uniquement** (chemins de navigateurs, ISE, `%TEMP%`).

---

## Contribuer

Les contributions sont les bienvenues :

1. Forkez le dépôt.
2. Créez une branche (`git checkout -b feature/ma-feature`).
3. Committez (`git commit -m "Ajoute ma-feature"`).
4. Poussez (`git push origin feature/ma-feature`).
5. Ouvrez une Pull Request.

Pour les bugs ou suggestions, ouvrez une *issue* en décrivant votre version de Windows / PowerShell et le mode de langage affiché au démarrage.

---

## Licence

Distribué sous licence MIT. Voir le fichier [`LICENSE.md`](License.md) pour les détails.

---

## Auteur

**Eric Guiffault** — PS-PING Ping Monitor

> Un outil de diagnostic réseau simple, autonome et lisible, pensé pour les environnements Windows verrouillés.
