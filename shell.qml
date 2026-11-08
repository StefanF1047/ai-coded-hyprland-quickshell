import Quickshell
import Quickshell.Wayland
import Quickshell.Io
import Quickshell.Services.Notifications
import QtQuick
import QtQuick.Layouts
import QtQuick.Controls

PanelWindow {
    id: dockPanel

    anchors { bottom: true; left: true; right: true }

    implicitHeight: 90
    exclusiveZone: dockPanel.dockApps.length > 0
        ? dockRect.height + dockRect.anchors.bottomMargin
        : 0
    color: "transparent"

    BackgroundEffect.blurRegion: Region {
        Region { item: dockRect.visible       ? dockRect       : null }
        Region { item: clockRect.visible      ? clockRect      : null }
        Region { item: launcherButton.visible ? launcherButton : null }
        Region { item: ccButton.visible       ? ccButton       : null }
    }

    // ========== Clipboard watcher ==========
    Process {
        id: cliphistWatcher
        command: ["wl-paste", "--watch", "cliphist", "store"]
        running: true
        onExited: retryTimer.start()
    }
    Timer {
        id: retryTimer
        interval: 1000
        onTriggered: cliphistWatcher.running = true
    }

    // ========== awww daemon autoload ==========
    Process {
        id: awwwStartup
        command: ["sh", "-c",
            "pgrep -x awww-daemon >/dev/null 2>&1 || setsid -f awww-daemon >/dev/null 2>&1 || true"
        ]
    }
    Timer {
        id: awwwTimer
        interval: 30000
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: awwwStartup.running = true
    }

    // ========== Persistent settings ==========
    property color accent: "#1e66f5"
    property real glassOpacity: 0.45
    property real cornerRadius: 20
    property bool darkMode: false
    property string wallpaperPath: ""
    property string iconTheme: ""

    // ========== Theme (dark = pure black, no blue tint) ==========
    readonly property color glass: darkMode
        ? Qt.rgba(0, 0, 0, glassOpacity)
        : Qt.rgba(0.937, 0.945, 0.961, glassOpacity)
    // semi-transparent so the layer-shell blur behind it actually reads as glass
    readonly property color panelBg: darkMode
        ? Qt.rgba(0.05, 0.05, 0.06, 0.55)
        : Qt.rgba(0.95, 0.96, 0.97, 0.55)
    readonly property color textMain: darkMode ? "#ffffff" : "#000000"
    readonly property color textDim:  darkMode ? "#aaaaaa" : "#333333"
    readonly property color tileBg: darkMode ? "#1affffff" : "#30ffffff"
    readonly property color tileBgHover: darkMode ? "#2affffff" : "#45ffffff"
    readonly property color tileBorder: darkMode ? "#2affffff" : "#55ffffff"
    readonly property color inputTop: darkMode ? "#20ffffff" : "#30ffffff"
    readonly property color inputBot: darkMode ? "#10ffffff" : "#18ffffff"
    readonly property color dotIdle:  "#9ca0b0"
    readonly property color danger:   "#d20f39"

    readonly property real buttonRadius: cornerRadius
    readonly property real panelRadius:  cornerRadius + 6
    readonly property real searchRadius: Math.max(4, cornerRadius - 8)

    readonly property var accentColors: [
        "#1e66f5", "#7287fd", "#209fb5", "#04a5e5",
        "#179299", "#40a02b", "#df8e1d", "#fe640b",
        "#e64553", "#d20f39", "#8839ef", "#ea76cb"
    ]

    // ========== Runtime state ==========
    property var desktopEntriesById: ({})
    property var desktopEntriesByClass: ({})
    property var windows: []
    property string focusedAddress: ""
    property var now: new Date()

    property bool launcherOpen: false
    property var allApps: []
    property var filteredApps: []
    property string searchText: ""
    property var pinnedIds: []

    // Control Center
    property bool ccOpen: false
    property string ccView: "main"
    property bool wifiEnabled: false
    property string wifiSSID: ""
    property var wifiNetworks: []
    property string wifiPasswordTarget: ""
    property string wifiPasswordPrompt: ""
    property bool btEnabled: false
    property var btDevices: []
    property int volume: 50
    property bool muted: false
    property int notifCount: 0
    property bool dndEnabled: false
    property var clipboardHistory: []
    property string pendingPowerAction: ""
    property var availableIconThemes: []

    // Notifications
    property var notifToasts: []
    property int notifSeq: 0

    // Live icon resolution (theme-aware, no restart needed)
    property var iconPaths: ({})
    property int iconRevision: 0
    property int iconCount: 0

    // Wallpaper browser
    property var wallpapers: []
    property bool wallpaperFpsApplied: false

    // Monitors / display
    property var monitors: []
    property var monitorRules: ({})
    property string monitorStatus: ""

    // Keyboard / mouse / gestures
    property var inputCfg: ({
        kb_layout: "us",
        kb_variant: "",
        kb_model: "",
        kb_options: "",
        kb_rules: "",
        follow_mouse: 1,
        sensitivity: 0,
        natural_scroll: false,
        gesture_fingers: 3,
        gesture_direction: "horizontal",
        gesture_action: "workspace",
        device_name: "",
        device_sensitivity: ""
    })

    // Cards to show: live monitors plus any monitor we have disabled via config
    readonly property var displayMonitors: {
        const list = [];
        const live = ({});
        for (const m of monitors) { live[m.name] = true; list.push(m); }
        for (const name of Object.keys(monitorRules)) {
            const r = monitorRules[name];
            if (r && r.disabled && !live[name]) {
                list.push({
                    name: name, disabled: true, focused: false,
                    width: 0, height: 0, refresh: 0, scale: 1,
                    resolutions: [], desc: ""
                });
            }
        }
        return list;
    }

    // Optimistic-update timestamps
    property real lastVolumeUpdate: 0
    property real lastMuteUpdate: 0
    property real lastWifiToggle: 0
    property real lastBtToggle: 0
    property real lastDndToggle: 0

    // ---------- Load settings ----------
    Process {
        id: loadSettings
        running: true
        command: ["sh", "-c",
            "mkdir -p \"$HOME/.config/quickshell\"; " +
            "cat \"$HOME/.config/quickshell/settings.json\" 2>/dev/null || echo '{}'"
        ]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const s = JSON.parse(this.text.trim() || "{}");
                    if (s.accent) dockPanel.accent = s.accent;
                    if (typeof s.glassOpacity === "number") dockPanel.glassOpacity = s.glassOpacity;
                    if (typeof s.cornerRadius === "number") dockPanel.cornerRadius = s.cornerRadius;
                    if (typeof s.darkMode === "boolean") dockPanel.darkMode = s.darkMode;
                    if (s.wallpaperPath) dockPanel.wallpaperPath = s.wallpaperPath;
                    if (s.iconTheme) dockPanel.iconTheme = s.iconTheme;
                } catch (e) {}
            }
        }
    }

    function saveSettings() {
        const s = JSON.stringify({
            accent: String(accent),
            glassOpacity: glassOpacity,
            cornerRadius: cornerRadius,
            darkMode: darkMode,
            wallpaperPath: wallpaperPath,
            iconTheme: iconTheme
        });
        const escaped = s.replace(/'/g, "'\\''");
        Quickshell.execDetached(["sh", "-c",
            "mkdir -p \"$HOME/.config/quickshell\" && printf '%s' '" + escaped +
            "' > \"$HOME/.config/quickshell/settings.json\""
        ]);
    }

    function shellQuote(s) {
        return "'" + String(s).replace(/'/g, "'\\''") + "'";
    }

    // ---------- System-wide dark mode ----------
    // Follows the freedesktop appearance portal (gsettings color-scheme), the GTK
    // theme and the GTK prefer-dark flags, which is what GTK3/GTK4/libadwaita,
    // Qt6 (>6.5), Firefox and most Wayland apps read.
    function applyDarkMode() {
        const flag = darkMode ? "1" : "0";
        const scheme = darkMode ? "prefer-dark" : "default";
        const gtkTheme = darkMode ? "Adwaita-dark" : "Adwaita";
        const script =
            'gsettings set org.gnome.desktop.interface color-scheme ' + shellQuote(scheme) + ' 2>/dev/null\n' +
            'gsettings set org.gnome.desktop.appearance color-scheme ' + shellQuote(scheme) + ' 2>/dev/null\n' +
            'gsettings set org.gnome.desktop.interface gtk-theme ' + shellQuote(gtkTheme) + ' 2>/dev/null\n' +
            'for v in 3.0 4.0; do\n' +
            '  d="$HOME/.config/gtk-$v"; mkdir -p "$d"; f="$d/settings.ini"\n' +
            '  if [ -f "$f" ]; then\n' +
            '    if grep -q "^gtk-application-prefer-dark-theme" "$f"; then\n' +
            '      sed -i "s/^gtk-application-prefer-dark-theme=.*/gtk-application-prefer-dark-theme=' + flag + '/" "$f"\n' +
            '    else\n' +
            '      printf "gtk-application-prefer-dark-theme=' + flag + '\\n" >> "$f"\n' +
            '    fi\n' +
            '  else\n' +
            '    printf "[Settings]\\ngtk-application-prefer-dark-theme=' + flag + '\\n" > "$f"\n' +
            '  fi\n' +
            'done';
        Quickshell.execDetached(["sh", "-c", script]);
    }

    onDarkModeChanged: applyDarkMode()

    // ---------- Icon theme scanner ----------
    Process {
        id: loadIconThemes
        running: true
        command: ["sh", "-c",
            "for dir in \"$HOME/.local/share/icons\" /usr/share/icons; do " +
            "[ -d \"$dir\" ] || continue; " +
            "for d in \"$dir\"/*/; do " +
            "[ -f \"$d/index.theme\" ] || continue; " +
            "id=$(basename \"$d\"); " +
            "name=$(grep -m1 '^Name=' \"$d/index.theme\" 2>/dev/null | sed 's/^Name=//' | head -1); " +
            "[ -z \"$name\" ] && name=\"$id\"; " +
            "printf '%s\\t%s\\n' \"$id\" \"$name\"; " +
            "done; done | sort -u"
        ]
        stdout: StdioCollector {
            onStreamFinished: {
                const themes = [];
                for (const line of this.text.trim().split("\n")) {
                    if (!line) continue;
                    const parts = line.split("\t");
                    if (parts.length >= 2 && parts[0])
                        themes.push({ id: parts[0], name: parts[1] });
                }
                dockPanel.availableIconThemes = themes;
            }
        }
    }

    // ---------- Current system icon theme ----------
    Process {
        id: loadCurrentIconTheme
        running: true
        command: ["sh", "-c",
            "gsettings get org.gnome.desktop.interface icon-theme 2>/dev/null | tr -d \"'\" || echo ''"
        ]
        stdout: StdioCollector {
            onStreamFinished: {
                const t = this.text.trim();
                if (t && !dockPanel.iconTheme) dockPanel.iconTheme = t;
            }
        }
    }

    // ---------- Live icon pack index ----------
    function iconHelperScript() {
        return [
            "#!/bin/sh",
            'theme="$1"; shift',
            '[ -n "$theme" ] || exit 0',
            '',
            'dirs=""',
            'for base in "$HOME/.local/share/icons" "$HOME/.icons" "/usr/share/icons" "/usr/local/share/icons"; do',
            '  [ -d "$base/$theme" ] || continue',
            '  dirs="$dirs $base/$theme"',
            '  inh=$(grep -m1 "^Inherits=" "$base/$theme/index.theme" 2>/dev/null | sed "s/^Inherits=//" | tr "," " ")',
            '  for p in $inh; do [ -d "$base/$p" ] && dirs="$dirs $base/$p"; done',
            'done',
            'dirs="$dirs /usr/share/icons/hicolor"',
            '',
            'i=0',
            'for d in $dirs; do',
            '  [ -d "$d" ] || continue',
            '  i=$((i+1))',
            '  find "$d" -maxdepth 4 -type f \\( -name "*.png" -o -name "*.svg" -o -name "*.xpm" \\) -path "*/apps/*" 2>/dev/null |',
            '  while IFS= read -r f; do',
            '    b=${f##*/}',
            '    printf "%s|%s|%s\\n" "${b%.*}" "$i" "$f"',
            '  done',
            'done',
            '',
            'if [ -d /usr/share/pixmaps ]; then',
            '  i=$((i+1))',
            '  find /usr/share/pixmaps -maxdepth 1 -type f \\( -name "*.png" -o -name "*.svg" \\) 2>/dev/null |',
            '  while IFS= read -r f; do',
            '    b=${f##*/}',
            '    printf "%s|%s|%s\\n" "${b%.*}" "$i" "$f"',
            '  done',
            'fi'
        ].join("\n");
    }

    Process {
        id: iconResolver
        property var wanted: ({})
        property bool queued: false
        command: []
        stdout: StdioCollector {
            onStreamFinished: {
                const wanted = iconResolver.wanted;
                const sizeScore = (p) => {
                    if (p.endsWith(".svg")) return 4096;
                    const m = p.match(/\/(\d+)x(\d+)\//);
                    return m ? Math.max(parseInt(m[1]), parseInt(m[2])) : 1;
                };
                const pick = {};
                for (const line of this.text.split("\n")) {
                    const parts = line.split("|");
                    if (parts.length < 3) continue;
                    const name = parts[0];
                    if (!wanted[name]) continue;
                    const prio = parseInt(parts[1]) || 999;
                    const path = parts[2];
                    if (!path) continue;
                    const sc = sizeScore(path);
                    const cur = pick[name];
                    if (!cur || prio < cur.prio || (prio === cur.prio && sc > cur.score))
                        pick[name] = { prio: prio, score: sc, path: path };
                }
                const map = {};
                let count = 0;
                for (const name of Object.keys(pick)) {
                    map[name] = pick[name].path;
                    count++;
                    const lower = name.toLowerCase();
                    if (!map[lower]) map[lower] = pick[name].path;
                }
                dockPanel.iconCount = count;
                dockPanel.iconPaths = map;
                dockPanel.iconRevision++;
            }
        }
        onRunningChanged: {
            if (!running && iconResolver.queued) {
                iconResolver.queued = false;
                dockPanel.refreshIconPaths();
            }
        }
    }

    function refreshIconPaths() {
        const theme = iconTheme;
        const names = [], seen = {};
        const add = (n) => {
            if (!n) return;
            let s = String(n);
            if (s.charAt(0) === "/") return;
            s = s.replace(/\.(svg|png|xpm)$/i, "");
            for (const key of [s, s.toLowerCase()]) {
                if (!key || seen[key]) continue;
                seen[key] = true;
                names.push(key);
            }
        };
        for (const a of allApps) { add(a.icon); add(a.wmclass); add(a.id); }
        add("application-x-executable");
        if (!theme || names.length === 0) return;
        if (iconResolver.running) { iconResolver.queued = true; return; }
        if (names.length > 400) names.length = 400;

        const wrapper =
            'mkdir -p "$HOME/.cache/quickshell" && ' +
            'printf "%s" ' + shellQuote(iconHelperScript()) +
            ' > "$HOME/.cache/quickshell/icon-index.sh" && ' +
            'exec sh "$HOME/.cache/quickshell/icon-index.sh" "$@"';

        const wanted = {};
        for (const n of names) wanted[n] = true;
        iconResolver.wanted = wanted;
        iconResolver.command = ["sh", "-c", wrapper, "iconscan", theme].concat(names);
        iconResolver.running = true;
    }

    function setIconTheme(id) {
        iconTheme = id;
        saveSettings();
        const safe = id.replace(/'/g, "'\\''");
        Quickshell.execDetached(["sh", "-c",
            "gsettings set org.gnome.desktop.interface icon-theme '" + safe + "' 2>/dev/null || true"
        ]);
        refreshIconPaths();
    }

    onIconThemeChanged: refreshIconPaths()

    // ---------- Wallpaper (awww) ----------
    onWallpaperPathChanged: applyWallpaperNow()

    function wallpaperFps() {
        for (const m of monitors) if (m.focused && m.refresh > 0) return m.refresh;
        for (const m of monitors) if (m.refresh > 0) return m.refresh;
        return 60;
    }

    function applyWallpaperNow() {
        if (!wallpaperPath) return;
        const fps = wallpaperFps();
        if (monitors.length > 0) wallpaperFpsApplied = true;
        Quickshell.execDetached(["sh", "-c",
            'p="$1"; f="$2"; i=0; ' +
            'while [ $i -lt 10 ]; do ' +
            '  awww img "$p" --transition-type center --transition-fps "$f" >/dev/null 2>&1 && exit 0; ' +
            '  pgrep -x awww-daemon >/dev/null 2>&1 || setsid -f awww-daemon >/dev/null 2>&1; ' +
            '  i=$((i+1)); sleep 0.4; ' +
            'done; exit 0',
            "awww", wallpaperPath, String(fps)]);
    }

    onMonitorsChanged: {
        if (!wallpaperFpsApplied && wallpaperPath && monitors.length > 0)
            applyWallpaperNow();
    }

    Process {
        id: wallpaperScan
        command: ["sh", "-c",
            'for d in "$HOME/Pictures" "$HOME/Pictures/Wallpapers" "$HOME/Wallpapers" ' +
            '"$HOME/.local/share/wallpapers" "$HOME/Downloads" "/usr/share/wallpapers"; do ' +
            '[ -d "$d" ] || continue; ' +
            'find "$d" -maxdepth 3 -type f \\( -iname "*.png" -o -iname "*.jpg" ' +
            '-o -iname "*.jpeg" -o -iname "*.webp" \\) -printf "%T@\\t%p\\n" 2>/dev/null; ' +
            'done | sort -rn | head -n 48 | cut -f2-'
        ]
        stdout: StdioCollector {
            onStreamFinished: {
                const list = [];
                for (const line of this.text.split("\n")) {
                    const p = line.trim();
                    if (p && list.indexOf(p) < 0) list.push(p);
                }
                dockPanel.wallpapers = list;
            }
        }
    }

    function applyWallpaper(path) {
        if (!path) return;
        wallpaperPath = path;
        saveSettings();
    }

    function openWallpaperView() {
        ccView = "wallpapers";
        wallpaperScan.running = true;
    }

    // ---------- Load pins ----------
    Process {
        id: loadPins
        running: true
        command: ["sh", "-c",
            "mkdir -p \"$HOME/.config/quickshell\"; " +
            "cat \"$HOME/.config/quickshell/pins.json\" 2>/dev/null || echo '[]'"
        ]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const parsed = JSON.parse(this.text.trim() || "[]");
                    if (Array.isArray(parsed)) dockPanel.pinnedIds = parsed;
                } catch (e) { dockPanel.pinnedIds = []; }
            }
        }
    }

    function savePins() {
        const json = JSON.stringify(pinnedIds);
        const escaped = json.replace(/'/g, "'\\''");
        Quickshell.execDetached(["sh", "-c",
            "mkdir -p \"$HOME/.config/quickshell\" && printf '%s' '" + escaped +
            "' > \"$HOME/.config/quickshell/pins.json\""
        ]);
    }

    function togglePin(item) {
        const id = item.entry ? item.entry.id : item.id;
        if (!id) return;
        if (pinnedIds.indexOf(id) >= 0) pinnedIds = pinnedIds.filter(x => x !== id);
        else pinnedIds = pinnedIds.concat([id]);
        savePins();
    }

    function reorderPinned(fromIdx, toIdx) {
        const fromApp = dockApps[fromIdx];
        const toApp = dockApps[toIdx];
        if (!fromApp || !toApp || !fromApp.pinned || !toApp.pinned) return;
        const fromPin = pinnedIds.indexOf(fromApp.id);
        const toPin = pinnedIds.indexOf(toApp.id);
        if (fromPin < 0 || toPin < 0) return;
        const newPins = pinnedIds.slice();
        const [removed] = newPins.splice(fromPin, 1);
        newPins.splice(toPin, 0, removed);
        pinnedIds = newPins;
        savePins();
    }

    // ---------- .desktop scan ----------
    Process {
        id: loadDesktop
        running: true
        command: ["sh", "-c",
            "for dir in /usr/share/applications \"$HOME/.local/share/applications\" " +
            "/var/lib/flatpak/exports/share/applications " +
            "\"$HOME/.local/share/flatpak/exports/share/applications\"; do " +
            "[ -d \"$dir\" ] || continue; " +
            "for f in \"$dir\"/*.desktop; do " +
            "[ -f \"$f\" ] || continue; " +
            "grep -q '^Type=Application' \"$f\" || continue; " +
            "grep -q '^NoDisplay=true' \"$f\" && continue; " +
            "grep -q '^Hidden=true' \"$f\" && continue; " +
            "name=$(grep -m1 '^Name=' \"$f\" | sed 's/^Name=//'); " +
            "icon=$(grep -m1 '^Icon=' \"$f\" | sed 's/^Icon=//'); " +
            "exec=$(grep -m1 '^Exec=' \"$f\" | sed 's/^Exec=//' | sed 's/ *%[a-zA-Z]//g'); " +
            "wmclass=$(grep -m1 '^StartupWMClass=' \"$f\" | sed 's/^StartupWMClass=//'); " +
            "base=$(basename \"$f\" .desktop); " +
            "printf '%s\\t%s\\t%s\\t%s\\t%s\\n' \"$wmclass\" \"$base\" \"$name\" \"$icon\" \"$exec\"; " +
            "done; done"
        ]
        stdout: StdioCollector {
            onStreamFinished: {
                const byId = {}, byClass = {}, list = [];
                for (const line of this.text.split("\n")) {
                    if (!line) continue;
                    const p = line.split("\t");
                    if (p.length < 5) continue;
                    const entry = { id: p[1], name: p[2], icon: p[3], exec: p[4], wmclass: p[0] || p[1] };
                    if (entry.id) byId[entry.id] = entry;
                    if (p[0]) byClass[p[0].toLowerCase()] = entry;
                    if (p[1]) byClass[p[1].toLowerCase()] = entry;
                    list.push(entry);
                }
                dockPanel.desktopEntriesById = byId;
                dockPanel.desktopEntriesByClass = byClass;
                dockPanel.allApps = list;
                dockPanel.filteredApps = list;
                dockPanel.refreshIconPaths();
            }
        }
    }

    // ---------- Polls ----------
    Timer { interval: 500; running: true; repeat: true; onTriggered: pollClients.running = true }
    Process {
        id: pollClients
        running: true
        command: ["hyprctl", "clients", "-j"]
        stdout: StdioCollector {
            onStreamFinished: {
                try { dockPanel.windows = JSON.parse(this.text).filter(c => !c.hidden && c.mapped !== false); }
                catch (e) {}
            }
        }
    }

    Timer { interval: 200; running: true; repeat: true; onTriggered: pollFocused.running = true }
    Process {
        id: pollFocused
        command: ["hyprctl", "activewindow", "-j"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const info = JSON.parse(this.text);
                    dockPanel.focusedAddress = info.address || "";
                } catch (e) {}
            }
        }
    }

    Timer { interval: 1000; running: true; repeat: true; onTriggered: dockPanel.now = new Date() }

    // ---------- CC polls ----------
    Timer {
        interval: dockPanel.ccOpen ? 1500 : 4000
        running: true; repeat: true
        onTriggered: wifiStateProc.running = true
    }
    Process {
        id: wifiStateProc
        command: ["sh", "-c", "nmcli -t radio wifi 2>/dev/null || echo disabled"]
        stdout: StdioCollector {
            onStreamFinished: {
                if (Date.now() - dockPanel.lastWifiToggle > 1500)
                    dockPanel.wifiEnabled = this.text.trim() === "enabled";
            }
        }
    }
    Timer { interval: dockPanel.ccOpen ? 2000 : 4000; running: true; repeat: true; onTriggered: wifiSSIDProc.running = true }
    Process {
        id: wifiSSIDProc
        command: ["sh", "-c", "nmcli -t -f active,ssid dev wifi 2>/dev/null | grep '^yes' | head -1 | cut -d: -f2"]
        stdout: StdioCollector { onStreamFinished: { dockPanel.wifiSSID = this.text.trim(); } }
    }
    Timer { interval: dockPanel.ccOpen ? 2000 : 6000; running: true; repeat: true; onTriggered: btStateProc.running = true }
    Process {
        id: btStateProc
        command: ["sh", "-c", "bluetoothctl show 2>/dev/null | grep 'Powered:' | awk '{print $2}'"]
        stdout: StdioCollector {
            onStreamFinished: {
                if (Date.now() - dockPanel.lastBtToggle > 1500)
                    dockPanel.btEnabled = this.text.trim() === "yes";
            }
        }
    }
    Timer { interval: dockPanel.ccOpen ? 500 : 1500; running: true; repeat: true; onTriggered: audioProc.running = true }
    Process {
        id: audioProc
        command: ["sh", "-c",
            "pactl get-sink-volume @DEFAULT_SINK@ 2>/dev/null | head -1 | grep -oP '\\d+(?=%)' | head -1; " +
            "pactl get-sink-mute @DEFAULT_SINK@ 2>/dev/null | awk '{print $2}'"]
        stdout: StdioCollector {
            onStreamFinished: {
                const lines = this.text.split("\n");
                const n = Date.now();
                if (lines[0] && lines[0].trim() && n - dockPanel.lastVolumeUpdate > 800)
                    dockPanel.volume = parseInt(lines[0].trim()) || 0;
                if (lines[1] && n - dockPanel.lastMuteUpdate > 800)
                    dockPanel.muted = (lines[1] || "").trim() === "yes";
            }
        }
    }
    Timer { interval: dockPanel.ccOpen ? 1500 : 4000; running: true; repeat: true; onTriggered: dndProc.running = true }
    Process {
        id: dndProc
        command: ["sh", "-c", "dunstctl is-paused 2>/dev/null || echo false"]
        stdout: StdioCollector {
            onStreamFinished: {
                if (Date.now() - dockPanel.lastDndToggle > 1500)
                    dockPanel.dndEnabled = this.text.trim() === "true";
            }
        }
    }
    Timer { interval: 2500; running: dockPanel.ccOpen; repeat: true; onTriggered: clipProc.running = true }
    Process {
        id: clipProc
        command: ["sh", "-c", "cliphist list 2>/dev/null | head -50"]
        stdout: StdioCollector {
            onStreamFinished: {
                const items = [];
                for (const line of this.text.split("\n")) {
                    if (!line) continue;
                    const idx = line.indexOf("\t");
                    if (idx < 0) continue;
                    const id = line.substring(0, idx);
                    const txt = line.substring(idx + 1);
                    if (id && txt) items.push({ id, text: txt });
                }
                dockPanel.clipboardHistory = items;
            }
        }
    }

    // ================= Notifications =================
    NotificationServer {
        id: notifServer
        onNotification: (n) => {
            try {
                if (dockPanel.dndEnabled) return;
                const item = {
                    id: dockPanel.notifSeq++,
                    appName: String(n.appName || ""),
                    summary: String(n.summary || ""),
                    body: String(n.body || ""),
                    urgency: Number(n.urgency === undefined ? 1 : n.urgency)
                };
                dockPanel.notifToasts = [item].concat(dockPanel.notifToasts).slice(0, 4);
                dockPanel.notifCount = dockPanel.notifCount + 1;
            } catch (e) {}
        }
    }

    function removeToast(id) {
        const list = [];
        for (const t of notifToasts) if (t.id !== id) list.push(t);
        notifToasts = list;
    }

    Timer {
        interval: 500
        running: dockPanel.notifToasts.length > 0
        repeat: true
        onTriggered: {
            const cut = Date.now() - 8000;
            const keep = [];
            for (const t of dockPanel.notifToasts) if (t.time > cut) keep.push(t);
            if (keep.length !== dockPanel.notifToasts.length) dockPanel.notifToasts = keep;
        }
    }

    PanelWindow {
        id: notifPopup
        anchors { top: true; right: true }
        margins { top: 12; right: 12 }
        implicitWidth: 380
        implicitHeight: Math.max(1, notifCol.implicitHeight)
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.namespace: "quickshell-notifications"
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
        exclusionMode: ExclusionMode.Ignore
        color: "transparent"
        visible: dockPanel.notifToasts.length > 0

        BackgroundEffect.blurRegion: Region {
            Region { item: dockPanel.notifToasts.length > 0 ? notifCol : null }
        }

        Column {
            id: notifCol
            width: parent.width
            spacing: 8

            Repeater {
                model: dockPanel.notifToasts
                delegate: Rectangle {
                    id: toast
                    required property var modelData
                    width: notifCol.width
                    height: toastCol.implicitHeight + 22
                    radius: dockPanel.panelRadius
                    color: dockPanel.panelBg
                    border.width: 1
                    border.color: toast.modelData.urgency >= 2 ? dockPanel.danger : dockPanel.tileBorder

                    property bool shown: false
                    property bool leaving: false

                    opacity: (toast.shown && !toast.leaving) ? 1 : 0
                    Behavior on opacity { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }
                    x: (toast.shown && !toast.leaving) ? 0 : 32
                    Behavior on x { NumberAnimation { duration: 320; easing.type: Easing.OutCubic } }

                    Timer {
                        interval: 16
                        running: true
                        onTriggered: toast.shown = true
                    }
                    Timer {
                        interval: 5500
                        running: true
                        onTriggered: {
                            toast.leaving = true;
                            toastExitTimer.start();
                        }
                    }
                    Timer {
                        id: toastExitTimer
                        interval: 220
                        onTriggered: dockPanel.removeToast(toast.modelData.id)
                    }

                    Column {
                        id: toastCol
                        anchors.fill: parent
                        anchors.margins: 11
                        spacing: 3
                        Text {
                            width: parent.width
                            text: (toast.modelData.appName ? toast.modelData.appName + " · " : "")
                                  + (toast.modelData.summary || "Notification")
                            font.pixelSize: 12
                            font.bold: true
                            color: dockPanel.textMain
                            elide: Text.ElideRight
                        }
                        Text {
                            width: parent.width
                            visible: text.length > 0
                            text: toast.modelData.body
                            font.pixelSize: 11
                            color: dockPanel.textDim
                            wrapMode: Text.WordWrap
                            maximumLineCount: 4
                            elide: Text.ElideRight
                            textFormat: Text.PlainText
                        }
                    }

                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            toast.leaving = true;
                            toastExitTimer.start();
                        }
                    }
                }
            }
        }
    }

    // ---------- Monitors / display ----------
    function parseMonitorsJson(text) {
        let raw;
        try { raw = JSON.parse(text); } catch (e) { return null; }
        if (!Array.isArray(raw) || raw.length === 0) return null;
        const out = [];
        for (const m of raw) {
            const modes = [], seenMode = {};
            for (const s of (m.availableModes || [])) {
                const mt = String(s).match(/^(\d+)x(\d+)@([\d.]+)Hz$/);
                if (!mt) continue;
                const w = parseInt(mt[1]), h = parseInt(mt[2]);
                const r = Math.round(parseFloat(mt[3]));
                const k = w + "x" + h + "@" + r;
                if (seenMode[k]) continue;
                seenMode[k] = true;
                modes.push({ w: w, h: h, r: r, key: k });
            }
            modes.sort(function (a, b) {
                return b.w * b.h - a.w * a.h || b.r - a.r;
            });

            const resMap = {}, resolutions = [];
            for (const md of modes) {
                const rk = md.w + "x" + md.h;
                if (!resMap[rk]) {
                    resMap[rk] = {
                        key: rk, w: md.w, h: md.h,
                        label: md.w + "×" + md.h,
                        active: (m.width === md.w && m.height === md.h),
                        rates: []
                    };
                    resolutions.push(resMap[rk]);
                }
                resMap[rk].rates.push({
                    r: md.r,
                    label: md.r + " Hz",
                    active: (m.width === md.w && m.height === md.h
                             && Math.abs((m.refreshRate || 0) - md.r) < 1.5)
                });
            }

            out.push({
                name: m.name,
                desc: (m.description || "").replace(/\s+/g, " "),
                width: m.width, height: m.height,
                refresh: Math.round(m.refreshRate || 0),
                scale: m.scale || 1,
                x: m.x, y: m.y,
                disabled: m.disabled === true,
                focused: m.focused === true,
                resolutions: resolutions
            });
        }
        return out;
    }

    Process {
        id: monitorProc
        running: true
        command: ["hyprctl", "monitors", "-j"]
        stdout: StdioCollector {
            onStreamFinished: {
                const list = dockPanel.parseMonitorsJson(this.text);
                if (list) dockPanel.monitors = list;
            }
        }
    }
    Timer {
        id: monitorRefreshTimer
        interval: 600
        onTriggered: monitorProc.running = true
    }

    function monitorHelperScript() {
        return [
            "#!/bin/sh",
            'QSDIR="$HOME/.config/quickshell"',
            'QSSTATE="$QSDIR/monitors.state"',
            'QSJSON="$QSDIR/monitors.json"',
            'QSLUA="$HOME/.config/hypr/quickshell-monitors.lua"',
            'QSCONF="$HOME/.config/hypr/hyprland.lua"',
            'mkdir -p "$QSDIR" "$HOME/.config/hypr" || exit 0',
            '[ -f "$QSSTATE" ] || : > "$QSSTATE"',
            'TAB=$(printf "\\t")',
            '',
            'qs_regen() {',
            '  {',
            '    printf "{"',
            '    first=1',
            '    while IFS="$TAB" read -r n mode pos scale dis; do',
            '      [ -n "$n" ] || continue',
            '      [ "$first" = "1" ] || printf ","',
            '      first=0',
            '      if [ "$scale" = "auto" ]; then sc="\\"auto\\""; else sc="$scale"; fi',
            '      if [ "$dis" = "true" ]; then dj="true"; else dj="false"; fi',
            '      printf "\\"%s\\":{\\"mode\\":\\"%s\\",\\"position\\":\\"%s\\",\\"scale\\":%s,\\"disabled\\":%s}" "$n" "$mode" "$pos" "$sc" "$dj"',
            '    done < "$QSSTATE"',
            '    printf "}"',
            '  } > "$QSJSON"',
            '',
            '  {',
            '    printf "%s\\n\\n" "-- Monitor rules generated by the Quickshell dock."',
            '    while IFS="$TAB" read -r n mode pos scale dis; do',
            '      [ -n "$n" ] || continue',
            '      if [ "$dis" = "true" ]; then',
            '        printf "hl.monitor({\\n    output   = \\"%s\\",\\n    disabled = true,\\n})\\n\\n" "$n"',
            '      else',
            '        if [ "$scale" = "auto" ]; then sc="\\"auto\\""; else sc="$scale"; fi',
            '        printf "hl.monitor({\\n    output   = \\"%s\\",\\n    mode     = \\"%s\\",\\n    position = \\"%s\\",\\n    scale    = %s,\\n})\\n\\n" "$n" "$mode" "$pos" "$sc"',
            '      fi',
            '    done < "$QSSTATE"',
            '  } > "$QSLUA"',
            '',
            '  if [ -f "$QSCONF" ] && ! grep -q "quickshell-monitors" "$QSCONF"; then',
            '    printf "\\n-- Monitor settings from the Quickshell dock\\n" >> "$QSCONF"',
            '    printf "dofile((os.getenv(\\"HOME\\") or \\"\\") .. \\"/.config/hypr/quickshell-monitors.lua\\")\\n" >> "$QSCONF"',
            '  fi',
            '}',
            '',
            'qs_apply_one() {',
            '  if [ "$5" = "true" ]; then',
            '    hyprctl keyword monitor "$1,disable" 2>&1',
            '  else',
            '    hyprctl keyword monitor "$1,$2,$3,$4" 2>&1',
            '  fi',
            '}',
            '',
            'cmd="$1"',
            'shift',
            'case "$cmd" in',
            '  list)',
            '    cat "$QSSTATE"',
            '    ;;',
            '  apply-all)',
            '    qs_regen',
            '    while IFS="$TAB" read -r n mode pos scale dis; do',
            '      [ -n "$n" ] || continue',
            '      qs_apply_one "$n" "$mode" "$pos" "$scale" "$dis" >/dev/null 2>&1',
            '    done < "$QSSTATE"',
            '    ;;',
            '  set)',
            '    n="$1"; mode="$2"; pos="$3"; scale="$4"; dis="$5"',
            '    if [ -z "$n" ]; then exit 0; fi',
            '    tmp="$QSSTATE.tmp"',
            '    : > "$tmp"',
            '    while IFS="$TAB" read -r en emode epos escale edis; do',
            '      [ -n "$en" ] || continue',
            '      if [ "$en" = "$n" ]; then continue; fi',
            '      printf "%s\\t%s\\t%s\\t%s\\t%s\\n" "$en" "$emode" "$epos" "$escale" "$edis" >> "$tmp"',
            '    done < "$QSSTATE"',
            '    printf "%s\\t%s\\t%s\\t%s\\t%s\\n" "$n" "$mode" "$pos" "$scale" "$dis" >> "$tmp"',
            '    mv "$tmp" "$QSSTATE"',
            '    qs_regen',
            '    qs_apply_one "$n" "$mode" "$pos" "$scale" "$dis"',
            '    ;;',
            'esac'
        ].join("\n");
    }

    function monitorHelperCommand(args) {
        const script =
            'mkdir -p "$HOME/.cache/quickshell"\n' +
            'cat > "$HOME/.cache/quickshell/hypr-monitors.sh" <<\'QSEOF\'\n' +
            monitorHelperScript() + '\nQSEOF\n' +
            'exec sh "$HOME/.cache/quickshell/hypr-monitors.sh" "$@"';
        return ["sh", "-c", script, "hyprmon"].concat(args);
    }

    Process {
        id: monitorApply
        property var pendingArgs: []
        property bool queued: false
        command: []
        stdout: StdioCollector {
            onStreamFinished: {
                const t = this.text.trim();
                const benign = (t === "" || t === "ok"
                                || t.toLowerCase().indexOf("unknown request") >= 0);
                dockPanel.monitorStatus = benign ? "" : t;
                monitorRefreshTimer.restart();
            }
        }
        onRunningChanged: {
            if (!running && monitorApply.queued) {
                monitorApply.queued = false;
                dockPanel.execMonitorHelper();
            }
        }
    }

    function runMonitorHelper(args) {
        monitorApply.pendingArgs = args;
        if (monitorApply.running) { monitorApply.queued = true; return; }
        execMonitorHelper();
    }
    function execMonitorHelper() {
        const args = monitorApply.pendingArgs || [];
        if (args.length === 0) return;
        monitorApply.command = monitorHelperCommand(args);
        monitorApply.running = true;
    }

    Process {
        id: monitorLoad
        running: true
        command: monitorHelperCommand(["list"])
        stdout: StdioCollector {
            onStreamFinished: {
                const rules = {};
                for (const line of this.text.split("\n")) {
                    if (!line) continue;
                    const p = line.split("\t");
                    if (p.length < 5 || !p[0]) continue;
                    rules[p[0]] = {
                        mode: p[1] || "preferred",
                        position: p[2] || "auto",
                        scale: (p[3] === "auto" || p[3] === "") ? "auto" : Number(p[3]),
                        disabled: p[4] === "true"
                    };
                }
                dockPanel.monitorRules = rules;
                if (Object.keys(rules).length > 0)
                    Quickshell.execDetached(dockPanel.monitorHelperCommand(["apply-all"]));
                monitorRefreshTimer.restart();
            }
        }
    }

    function findMonitor(name) {
        for (const m of monitors) if (m.name === name) return m;
        return null;
    }
    function activeRates(mon) {
        if (!mon || !mon.resolutions) return [];
        for (const res of mon.resolutions) if (res.active) return res.rates;
        return [];
    }

    function commitMonitorRule(name, obj) {
        const copy = {};
        for (const k of Object.keys(monitorRules)) copy[k] = monitorRules[k];
        copy[name] = obj;
        monitorRules = copy;

        const dis = obj.disabled ? "true" : "false";
        const mode = obj.mode || "preferred";
        const pos = obj.position || "auto";
        const sc = (obj.scale === "auto" || obj.scale === undefined || obj.scale === null)
            ? "auto" : Number(obj.scale).toFixed(2);
        runMonitorHelper(["set", name, mode, pos, sc, dis]);
    }

    function applyMonitor(name, w, h, rate, scale) {
        const mon = findMonitor(name);
        if (!mon || mon.disabled) return;
        const rr = Number(rate || mon.refresh || 0);
        const mode = w + "x" + h + (rr > 0 ? "@" + rr.toFixed(2) : "");
        const sc = Number((scale === undefined || scale === null) ? mon.scale : scale);
        commitMonitorRule(name, {
            mode: mode,
            position: mon.x + "x" + mon.y,
            scale: Math.round(sc * 100) / 100,
            disabled: false
        });
    }
    function setMonitorScale(name, s) {
        const mon = findMonitor(name);
        if (!mon || mon.disabled) return;
        applyMonitor(name, mon.width, mon.height, mon.refresh, s);
    }
    function disableMonitor(name) {
        commitMonitorRule(name, { mode: "preferred", position: "auto", scale: "auto", disabled: true });
    }
    function enableMonitor(name) {
        commitMonitorRule(name, { mode: "preferred", position: "auto", scale: "auto", disabled: false });
    }

    // ---------- Keyboard / mouse / gestures ----------
    function inputHelperScript() {
        return [
            "#!/bin/sh",
            'QSDIR="$HOME/.config/quickshell"',
            'QSSTATE="$QSDIR/input.state"',
            'QSLUA="$HOME/.config/hypr/quickshell-input.lua"',
            'QSCONF="$HOME/.config/hypr/hyprland.lua"',
            'mkdir -p "$QSDIR" "$HOME/.config/hypr" || exit 0',
            '[ -f "$QSSTATE" ] || : > "$QSSTATE"',
            'TAB=$(printf "\\t")',
            '',
            'qs_input_regen() {',
            '  {',
            "    printf '%s\\n' '-- Input configuration generated by the Quickshell dock.'",
            "    printf '\\n'",
            '    IFS="$TAB" read -r layout variant model options rules follow sens nscroll gfingers gdir gaction devname devsens < "$QSSTATE"',
            "    printf 'hl.config({\\n    input = {\\n'",
            "    printf '        kb_layout  = \"%s\",\\n' \"$layout\"",
            "    printf '        kb_variant = \"%s\",\\n' \"$variant\"",
            "    printf '        kb_model   = \"%s\",\\n' \"$model\"",
            "    printf '        kb_options = \"%s\",\\n' \"$options\"",
            "    printf '        kb_rules   = \"%s\",\\n' \"$rules\"",
            "    printf '\\n        follow_mouse = %s,\\n' \"$follow\"",
            "    printf '\\n        sensitivity = %s, -- -1.0 - 1.0, 0 means no modification.\\n' \"$sens\"",
            "    printf '\\n        touchpad = {\\n            natural_scroll = %s,\\n        },\\n' \"$nscroll\"",
            "    printf '    },\\n})\\n\\n'",
            "    printf 'hl.gesture({\\n    fingers = %s,\\n    direction = \"%s\",\\n    action = \"%s\"\\n})\\n' \"$gfingers\" \"$gdir\" \"$gaction\"",
            '    if [ -n "$devname" ]; then',
            "      printf '\\nhl.device({\\n    name        = \"%s\",\\n    sensitivity = %s,\\n})\\n' \"$devname\" \"$devsens\"",
            '    fi',
            '  } > "$QSLUA"',
            '  if [ -f "$QSCONF" ] && ! grep -q "quickshell-input" "$QSCONF"; then',
            '    printf "\\n-- Input settings from the Quickshell dock\\n" >> "$QSCONF"',
            '    printf "dofile((os.getenv(\\"HOME\\") or \\"\\") .. \\"/.config/hypr/quickshell-input.lua\\")\\n" >> "$QSCONF"',
            '  fi',
            '}',
            '',
            'cmd="$1"',
            'shift',
            'case "$cmd" in',
            '  load)',
            '    cat "$QSSTATE"',
            '    ;;',
            '  set)',
            '    {',
            '      first=1',
            '      for a in "$@"; do',
            '        if [ "$first" = "1" ]; then printf "%s" "$a"; first=0',
            '        else printf "\\t%s" "$a"; fi',
            '      done',
            '      printf "\\n"',
            '    } > "$QSSTATE"',
            '    qs_input_regen',
            '    hyprctl keyword input:kb_layout "$1" >/dev/null 2>&1',
            '    hyprctl keyword input:kb_variant "$2" >/dev/null 2>&1',
            '    hyprctl keyword input:kb_model "$3" >/dev/null 2>&1',
            '    hyprctl keyword input:kb_options "$4" >/dev/null 2>&1',
            '    hyprctl keyword input:kb_rules "$5" >/dev/null 2>&1',
            '    hyprctl keyword input:follow_mouse "$6" >/dev/null 2>&1',
            '    hyprctl keyword input:sensitivity "$7" >/dev/null 2>&1',
            '    hyprctl keyword input:touchpad:natural_scroll "$8" >/dev/null 2>&1',
            '    ;;',
            'esac'
        ].join("\n");
    }

    function inputHelperCommand(args) {
        const script =
            'mkdir -p "$HOME/.cache/quickshell"\n' +
            'cat > "$HOME/.cache/quickshell/hypr-input.sh" <<\'QSIEOF\'\n' +
            inputHelperScript() + '\nQSIEOF\n' +
            'exec sh "$HOME/.cache/quickshell/hypr-input.sh" "$@"';
        return ["sh", "-c", script, "hyprinput"].concat(args);
    }

    Process {
        id: inputApply
        property var pendingArgs: []
        property bool queued: false
        command: []
        stdout: StdioCollector { onStreamFinished: {} }
        onRunningChanged: {
            if (!running && inputApply.queued) {
                inputApply.queued = false;
                dockPanel.execInputHelper();
            }
        }
    }

    function runInputHelper(args) {
        inputApply.pendingArgs = args;
        if (inputApply.running) { inputApply.queued = true; return; }
        execInputHelper();
    }
    function execInputHelper() {
        const args = inputApply.pendingArgs || [];
        if (args.length === 0) return;
        inputApply.command = inputHelperCommand(args);
        inputApply.running = true;
    }

    function setInputValue(key, value) {
        const copy = {};
        for (const k of Object.keys(inputCfg)) copy[k] = inputCfg[k];
        copy[key] = value;
        inputCfg = copy;
        saveInput();
    }

    function saveInput() {
        const c = inputCfg;
        const num = (v) => (isNaN(Number(v)) ? 0 : Number(v));
        runInputHelper(["set",
            String(c.kb_layout === undefined ? "us" : c.kb_layout),
            String(c.kb_variant === undefined ? "" : c.kb_variant),
            String(c.kb_model === undefined ? "" : c.kb_model),
            String(c.kb_options === undefined ? "" : c.kb_options),
            String(c.kb_rules === undefined ? "" : c.kb_rules),
            String(c.follow_mouse === undefined ? 1 : c.follow_mouse),
            num(c.sensitivity).toFixed(2),
            c.natural_scroll ? "true" : "false",
            String(c.gesture_fingers === undefined ? 3 : c.gesture_fingers),
            String(c.gesture_direction === undefined ? "horizontal" : c.gesture_direction),
            String(c.gesture_action === undefined ? "workspace" : c.gesture_action),
            String(c.device_name === undefined ? "" : c.device_name),
            (c.device_sensitivity === "" || c.device_sensitivity === undefined)
                ? "0" : num(c.device_sensitivity).toFixed(2)
        ]);
    }

    Process {
        id: inputLoad
        running: true
        command: inputHelperCommand(["load"])
        stdout: StdioCollector {
            onStreamFinished: {
                const line = this.text.split("\n")[0];
                if (!line || line.length === 0) {
                    dockPanel.saveInput();   // create the lua with defaults
                    return;
                }
                const p = line.split("\t");
                if (p.length < 13) { dockPanel.saveInput(); return; }
                dockPanel.inputCfg = {
                    kb_layout: p[0],
                    kb_variant: p[1],
                    kb_model: p[2],
                    kb_options: p[3],
                    kb_rules: p[4],
                    follow_mouse: Number(p[5]),
                    sensitivity: Number(p[6]),
                    natural_scroll: p[7] === "true",
                    gesture_fingers: Number(p[8]),
                    gesture_direction: p[9],
                    gesture_action: p[10],
                    device_name: p[11],
                    device_sensitivity: p[12]
                };
            }
        }
    }

    // ---------- WiFi ----------
    Timer {
        interval: 8000
        running: dockPanel.ccOpen && dockPanel.ccView === "wifi" && dockPanel.wifiEnabled
        repeat: true
        onTriggered: wifiScanProc.running = true
    }
    Process {
        id: wifiScanProc
        command: ["sh", "-c", "nmcli -m multiline -f SSID,SECURITY,SIGNAL,ACTIVE device wifi list 2>/dev/null"]
        stdout: StdioCollector {
            onStreamFinished: {
                const seen = {};
                const blocks = this.text.trim().split(/\n\s*\n/);
                for (const block of blocks) {
                    const net = {};
                    for (const line of block.split("\n")) {
                        const idx = line.indexOf(":");
                        if (idx < 0) continue;
                        net[line.substring(0, idx)] = line.substring(idx + 1);
                    }
                    if (!net.SSID) continue;
                    if (!seen[net.SSID] || net.ACTIVE === "yes") {
                        seen[net.SSID] = {
                            ssid: net.SSID,
                            sec: net.SECURITY || "",
                            signal: parseInt(net.SIGNAL) || 0,
                            active: net.ACTIVE === "yes"
                        };
                    }
                }
                dockPanel.wifiNetworks = Object.values(seen)
                    .sort((a, b) => (b.active ? 1 : 0) - (a.active ? 1 : 0) || b.signal - a.signal);
            }
        }
    }

    Timer {
        interval: 6000
        running: dockPanel.ccOpen && dockPanel.ccView === "bluetooth" && dockPanel.btEnabled
        repeat: true
        onTriggered: btDevicesProc.running = true
    }
    Process {
        id: btDevicesProc
        command: ["sh", "-c",
            "echo '---PAIRED---'; bluetoothctl devices Paired 2>/dev/null; " +
            "echo '---CONNECTED---'; bluetoothctl devices Connected 2>/dev/null"]
        stdout: StdioCollector {
            onStreamFinished: {
                const paired = [], connected = new Set();
                let mode = "";
                for (const line of this.text.split("\n")) {
                    if (line === "---PAIRED---") { mode = "paired"; continue; }
                    if (line === "---CONNECTED---") { mode = "connected"; continue; }
                    const m = line.match(/^Device\s+([0-9A-Fa-f:]+)\s+(.+)$/);
                    if (!m) continue;
                    if (mode === "connected") connected.add(m[1]);
                    else if (mode === "paired") paired.push({ mac: m[1], name: m[2] });
                }
                dockPanel.btDevices = paired.map(d => ({
                    mac: d.mac, name: d.name, connected: connected.has(d.mac)
                }));
            }
        }
    }

    // ---------- Actions ----------
    function toggleWifi() {
        wifiEnabled = !wifiEnabled;
        lastWifiToggle = Date.now();
        Quickshell.execDetached(["sh", "-c",
            wifiEnabled ? "nmcli radio wifi on" : "nmcli radio wifi off"]);
        if (wifiEnabled) wifiScanProc.running = true;
    }
    function toggleBt() {
        btEnabled = !btEnabled;
        lastBtToggle = Date.now();
        Quickshell.execDetached(["sh", "-c",
            btEnabled ? "bluetoothctl power on" : "bluetoothctl power off"]);
    }
    function toggleDnd() {
        dndEnabled = !dndEnabled;
        lastDndToggle = Date.now();
        Quickshell.execDetached(["sh", "-c",
            dndEnabled ? "dunstctl set-paused true" : "dunstctl set-paused false"]);
    }
    function setVolume(v) {
        volume = Math.round(v);
        lastVolumeUpdate = Date.now();
        Quickshell.execDetached(["sh", "-c",
            "pactl set-sink-volume @DEFAULT_SINK@ " + Math.round(v) + "%"]);
    }
    function toggleMute() {
        muted = !muted;
        lastMuteUpdate = Date.now();
        Quickshell.execDetached(["sh", "-c", "pactl set-sink-mute @DEFAULT_SINK@ toggle"]);
    }
    function clearNotifications() {
        notifToasts = [];
        notifCount = 0;
        Quickshell.execDetached(["sh", "-c", "dunstctl close-all 2>/dev/null || true"]);
    }

    function copyClipboard(id) {
        const safeId = String(id).replace(/[^0-9]/g, '');
        if (!safeId) return;
        Quickshell.execDetached(["sh", "-c",
            "cliphist decode " + safeId + " | wl-copy"
        ]);
        closeCCTimer.restart();
    }
    Timer {
        id: closeCCTimer
        interval: 120
        onTriggered: dockPanel.closeCC()
    }

    function closeCC() {
        ccOpen = false;
        wifiPasswordTarget = "";
        wifiPasswordPrompt = "";
        resetCcViewTimer.restart();
    }
    Timer {
        id: resetCcViewTimer
        interval: 400
        onTriggered: dockPanel.ccView = "main"
    }

    function connectOrDisconnectWifi(net) {
        if (net.active) {
            Quickshell.execDetached(["sh", "-c",
                "nmcli device disconnect $(nmcli -t -f DEVICE,STATE device | grep ':connected' | head -1 | cut -d: -f1)"]);
            return;
        }
        const openNet = !net.sec || net.sec === "" || net.sec === "--";
        if (openNet) {
            const ssid = net.ssid.replace(/'/g, "'\\''");
            Quickshell.execDetached(["sh", "-c", "nmcli device wifi connect '" + ssid + "'"]);
        } else {
            wifiPasswordTarget = net.ssid;
            wifiPasswordPrompt = "";
        }
    }
    function submitWifiPassword() {
        if (!wifiPasswordTarget) return;
        const ssid = wifiPasswordTarget.replace(/'/g, "'\\''");
        const pass = wifiPasswordPrompt.replace(/'/g, "'\\''");
        Quickshell.execDetached(["sh", "-c",
            "nmcli device wifi connect '" + ssid + "' password '" + pass + "'"]);
        wifiPasswordTarget = "";
        wifiPasswordPrompt = "";
        wifiScanProc.running = true;
    }
    function toggleBtDevice(dev) {
        Quickshell.execDetached(["sh", "-c",
            "bluetoothctl " + (dev.connected ? "disconnect " : "connect ") + dev.mac]);
    }

    function powerAction(action) {
        if (action === "lock" || action === "logout" || action === "sleep") {
            executePowerAction(action);
            return;
        }
        if (pendingPowerAction === action) {
            executePowerAction(action);
            pendingPowerAction = "";
            return;
        }
        pendingPowerAction = action;
        powerConfirmTimer.restart();
    }
    function executePowerAction(action) {
        switch (action) {
            case "lock":     Quickshell.execDetached(["loginctl", "lock-session"]); break;
            case "logout":   Quickshell.execDetached(["hyprctl", "dispatch", "exit"]); break;
            case "sleep":    Quickshell.execDetached(["systemctl", "suspend"]); break;
            case "reboot":   Quickshell.execDetached(["systemctl", "reboot"]); break;
            case "shutdown": Quickshell.execDetached(["systemctl", "poweroff"]); break;
        }
    }
    Timer {
        id: powerConfirmTimer
        interval: 3000
        onTriggered: dockPanel.pendingPowerAction = ""
    }

    // ---------- Helpers ----------
    property var dockApps: {
        const result = [];
        const usedClasses = new Set();
        for (const pid of pinnedIds) {
            const entry = desktopEntriesById[pid];
            if (!entry) continue;
            const wmcls = (entry.wmclass || entry.id).toLowerCase();
            const idcls = entry.id.toLowerCase();
            const matching = windows.filter(w => {
                const c = (w.class || "").toLowerCase();
                return c === wmcls || c === idcls;
            });
            const focused = matching.some(w => w.address === focusedAddress);
            result.push({ id: entry.id, class: entry.wmclass || entry.id, entry, pinned: true,
                running: matching.length > 0, focused, count: matching.length });
            usedClasses.add(wmcls); usedClasses.add(idcls);
        }
        const groups = {};
        for (const w of windows) {
            const cls = (w.class || "").toLowerCase();
            if (!cls || usedClasses.has(cls)) continue;
            if (!groups[cls]) groups[cls] = { id: cls, class: w.class,
                entry: desktopEntriesByClass[cls] || null,
                pinned: false, running: true, focused: false, count: 0 };
            groups[cls].count++;
            if (w.address === focusedAddress) groups[cls].focused = true;
        }
        for (const k of Object.keys(groups)) result.push(groups[k]);
        return result;
    }

    function activate(app) {
        const target = windows.find(w =>
            (w.class || "").toLowerCase() === (app.class || "").toLowerCase());
        if (target) Quickshell.execDetached(["hyprctl", "dispatch", "focuswindow", "address:" + target.address]);
        else if (app.entry && app.entry.exec) Quickshell.execDetached(["sh", "-c", app.entry.exec]);
    }

    function resolveIcon(entry, fallbackName) {
        if (iconRevision < 0) return "";
        const keys = [];
        const push = (k) => {
            if (!k) return;
            let s = String(k);
            if (s.charAt(0) === "/") { keys.push(s); return; }
            s = s.replace(/\.(svg|png|xpm)$/i, "");
            keys.push(s);
            keys.push(s.toLowerCase());
        };
        if (entry && entry.icon) push(entry.icon);
        if (entry && entry.wmclass) push(entry.wmclass);
        if (entry && entry.id) push(entry.id);
        push(fallbackName);

        for (const k of keys) {
            if (k.charAt(0) === "/") return k;
            const hit = iconPaths[k];
            if (hit) return "file://" + hit;
        }
        if (entry && entry.icon) return Quickshell.iconPath(entry.icon, fallbackName);
        return Quickshell.iconPath(fallbackName || "application-x-executable",
                                  "application-x-executable");
    }

    function filterApps(query) {
        searchText = query;
        if (!query || query.trim().length === 0) { filteredApps = allApps; return; }
        const q = query.toLowerCase();
        filteredApps = allApps.filter(a => a.name && a.name.toLowerCase().includes(q));
    }
    function launchFromLauncher(app) {
        if (app.exec) Quickshell.execDetached(["sh", "-c", app.exec]);
        launcherOpen = false; searchText = ""; filteredApps = allApps;
    }
    function ccWidgetProgress(idx) {
        const p = ccPanel.revealProgress;
        if (p <= 0) return 0;
        const delay = Math.min(idx * 0.045, 0.26);
        const denom = Math.max(0.4, 1.0 - delay);
        return Math.max(0, Math.min(1.05, (p - delay) / denom));
    }

    // ================= Dock =================
    Rectangle {
        id: dockRect
        visible: dockPanel.dockApps.length > 0
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
        anchors.bottomMargin: 8
        width: dockContent.width + 32
        height: 64
        radius: dockPanel.buttonRadius
        color: dockPanel.glass
        border.width: 1
        border.color: dockPanel.tileBorder
        Behavior on width { NumberAnimation { duration: 260; easing.type: Easing.OutCubic } }

        Item {
            anchors.fill: parent
            id: dockHoverArea
            property real pointerX: -1
            MouseArea {
                anchors.fill: parent
                hoverEnabled: true
                onPositionChanged: dockHoverArea.pointerX = mouse.x
                onExited: dockHoverArea.pointerX = -1
            }
            Item {
                id: dockContent
                anchors.centerIn: parent
                width: Math.max(0, dockItemsRepeater.count * 64 - 8)
                height: 56
                Repeater {
                    id: dockItemsRepeater
                    model: dockPanel.dockApps
                    delegate: Item {
                        id: delegateItem
                        required property var modelData
                        required property int index
                        width: 56; height: 56
                        x: index * 64
                        Behavior on x { enabled: !dragArea.drag.active
                            NumberAnimation { duration: 280; easing.type: Easing.OutCubic } }
                        property real magnifyScale: {
                            if (dockHoverArea.pointerX < 0) return 1.0;
                            const c = delegateItem.x + dockContent.x + delegateItem.width / 2;
                            const d = Math.abs(dockHoverArea.pointerX - c);
                            if (d > 80) return 1.0;
                            return 1.0 + 0.5 * (1.0 - d / 80);
                        }
                        property real pressScale: 1.0
                        SequentialAnimation {
                            id: dockBounce
                            NumberAnimation { target: delegateItem; property: "pressScale"; to: 0.85; duration: 80; easing.type: Easing.OutQuad }
                            NumberAnimation { target: delegateItem; property: "pressScale"; to: 1.0; duration: 540; easing.type: Easing.OutElastic; easing.amplitude: 0.55; easing.period: 0.33 }
                        }
                        scale: magnifyScale * pressScale
                        y: (magnifyScale - 1.0) * -18
                        Behavior on magnifyScale { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }
                        Behavior on y { NumberAnimation { duration: 90; easing.type: Easing.OutCubic } }
                        Image {
                            anchors.centerIn: parent
                            source: dockPanel.resolveIcon(modelData.entry, modelData.class)
                            width: 48; height: 48
                            fillMode: Image.PreserveAspectFit
                            sourceSize.width: 96; sourceSize.height: 96
                            smooth: true
                            asynchronous: true
                            opacity: status === Image.Ready ? 1 : 0
                            Behavior on opacity { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }
                        }
                        Rectangle {
                            anchors.horizontalCenter: parent.horizontalCenter
                            anchors.top: parent.bottom
                            anchors.topMargin: -2
                            width: modelData.focused ? 8 : (modelData.running ? 5 : 3)
                            height: modelData.focused ? 8 : (modelData.running ? 5 : 3)
                            radius: width / 2
                            color: modelData.focused ? dockPanel.accent
                                : (modelData.running ? dockPanel.dotIdle : "#509ca0b0")
                            Behavior on width { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }
                            Behavior on height { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }
                            Behavior on color { ColorAnimation { duration: 160; easing.type: Easing.OutCubic } }
                        }
                        MouseArea {
                            id: dragArea
                            anchors.fill: parent
                            acceptedButtons: Qt.LeftButton
                            cursorShape: Qt.PointingHandCursor
                            drag.target: modelData.pinned ? delegateItem : null
                            drag.axis: Drag.XAxis
                            drag.threshold: 8
                            drag.minimumX: 0
                            drag.maximumX: Math.max(0, (dockPanel.pinnedIds.length - 1) * 64)
                            property bool wasDrag: false
                            onPressed: { wasDrag = false; dockBounce.restart(); }
                            onPositionChanged: if (drag.active) wasDrag = true
                            onReleased: {
                                if (wasDrag) {
                                    const t = Math.round(delegateItem.x / 64);
                                    const clamped = Math.max(0, Math.min(dockPanel.pinnedIds.length - 1, t));
                                    if (clamped !== index && modelData.pinned) dockPanel.reorderPinned(index, clamped);
                                }
                            }
                            onClicked: if (!wasDrag) dockPanel.activate(modelData)
                        }
                        TapHandler {
                            acceptedButtons: Qt.RightButton
                            onTapped: dockPanel.togglePin(modelData)
                        }
                    }
                }
            }
        }
    }

    // ================= Launcher Button =================
    Rectangle {
        id: launcherButton
        anchors.right: dockRect.left
        anchors.bottom: parent.bottom
        anchors.bottomMargin: 8
        anchors.rightMargin: 12
        width: 64; height: 64; radius: dockPanel.buttonRadius
        color: dockPanel.glass
        border.width: 1
        border.color: launcherOpen ? dockPanel.accent : dockPanel.tileBorder
        Behavior on border.color { ColorAnimation { duration: 200 } }
        property real hoverScale: launcherHover.containsMouse ? 1.06 : (launcherOpen ? 1.04 : 1.0)
        Behavior on hoverScale { NumberAnimation { duration: 260; easing.type: Easing.OutCubic } }
        property real pressScale: 1.0
        SequentialAnimation {
            id: launcherBounce
            NumberAnimation { target: launcherButton; property: "pressScale"; to: 0.82; duration: 80; easing.type: Easing.OutQuad }
            NumberAnimation { target: launcherButton; property: "pressScale"; to: 1.0; duration: 600; easing.type: Easing.OutElastic; easing.amplitude: 0.65; easing.period: 0.32 }
        }
        scale: hoverScale * pressScale
        Grid {
            anchors.centerIn: parent
            columns: 3; spacing: 6
            Repeater {
                model: 9
                delegate: Rectangle {
                    width: 6; height: 6; radius: 3
                    color: launcherOpen ? dockPanel.accent : dockPanel.textMain
                    Behavior on color { ColorAnimation { duration: 200; easing.type: Easing.OutCubic } }
                }
            }
        }
        MouseArea {
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            onPressed: launcherBounce.restart()
            onClicked: {
                dockPanel.closeCC();
                dockPanel.launcherOpen = !dockPanel.launcherOpen;
            }
        }
        HoverHandler { id: launcherHover }
    }

    // ================= CC Button =================
    Rectangle {
        id: ccButton
        anchors.right: clockRect.left
        anchors.bottom: parent.bottom
        anchors.bottomMargin: 8
        anchors.rightMargin: 12
        width: 64; height: 64; radius: dockPanel.buttonRadius
        color: dockPanel.glass
        border.width: 1
        border.color: ccOpen ? dockPanel.accent : dockPanel.tileBorder
        Behavior on border.color { ColorAnimation { duration: 200 } }
        property real hoverScale: ccHover.containsMouse ? 1.06 : (ccOpen ? 1.04 : 1.0)
        Behavior on hoverScale { NumberAnimation { duration: 260; easing.type: Easing.OutCubic } }
        property real pressScale: 1.0
        SequentialAnimation {
            id: ccBounce
            NumberAnimation { target: ccButton; property: "pressScale"; to: 0.82; duration: 80; easing.type: Easing.OutQuad }
            NumberAnimation { target: ccButton; property: "pressScale"; to: 1.0; duration: 600; easing.type: Easing.OutElastic; easing.amplitude: 0.65; easing.period: 0.32 }
        }
        scale: hoverScale * pressScale
        Item {
            anchors.centerIn: parent
            width: 28; height: 24
            property color c: ccOpen ? dockPanel.accent : dockPanel.textMain
            Behavior on c { ColorAnimation { duration: 180 } }
            Rectangle { x: 0; y: 1; width: 28; height: 2; radius: 1; color: parent.c }
            Rectangle { x: 18; y: -2; width: 8; height: 8; radius: 4; color: parent.c }
            Rectangle { x: 0; y: 11; width: 28; height: 2; radius: 1; color: parent.c }
            Rectangle { x: 4; y: 8; width: 8; height: 8; radius: 4; color: parent.c }
            Rectangle { x: 0; y: 21; width: 28; height: 2; radius: 1; color: parent.c }
            Rectangle { x: 13; y: 18; width: 8; height: 8; radius: 4; color: parent.c }
        }
        Rectangle {
            visible: dockPanel.notifCount > 0 && !dockPanel.dndEnabled
            anchors.top: parent.top; anchors.right: parent.right
            anchors.topMargin: -4; anchors.rightMargin: -4
            width: 20; height: 20; radius: 10
            color: dockPanel.danger
            scale: visible ? 1 : 0
            Behavior on scale { NumberAnimation { duration: 200; easing.type: Easing.OutBack } }
            Text {
                anchors.centerIn: parent
                text: dockPanel.notifCount > 9 ? "9+" : String(dockPanel.notifCount)
                color: "#ffffff"; font.pixelSize: 10; font.bold: true
            }
        }
        MouseArea {
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            onPressed: ccBounce.restart()
            onClicked: {
                dockPanel.launcherOpen = false;
                dockPanel.ccOpen = !dockPanel.ccOpen;
            }
        }
        HoverHandler { id: ccHover }
    }

    // ================= Launcher Panel =================
    PanelWindow {
        id: launcherPanel
        anchors { top: true; bottom: true; left: true; right: true }
        WlrLayershell.layer: WlrLayer.Top
        WlrLayershell.namespace: "quickshell-launcher"
        WlrLayershell.keyboardFocus: (dockPanel.launcherOpen || revealProgress > 0.001)
            ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
        exclusionMode: ExclusionMode.Ignore
        color: "transparent"
        visible: dockPanel.launcherOpen || revealProgress > 0.001
        property real revealProgress: 0.0

        // real blur behind the launcher -> glass, not just transparency
        BackgroundEffect.blurRegion: Region {
            Region { item: popupContent }
        }

        SequentialAnimation {
            id: launcherOpenSeq
            PauseAnimation { duration: 30 }
            NumberAnimation {
                target: launcherPanel; property: "revealProgress"
                to: 1.0; duration: 380; easing.type: Easing.OutCubic
            }
        }
        NumberAnimation {
            id: launcherCloseAnim
            target: launcherPanel; property: "revealProgress"
            to: 0.0; duration: 220; easing.type: Easing.InCubic
        }
        Connections {
            target: dockPanel
            function onLauncherOpenChanged() {
                if (dockPanel.launcherOpen) {
                    launcherCloseAnim.stop();
                    launcherPanel.revealProgress = 0;
                    launcherOpenSeq.start();
                    focusTimer.start();
                } else {
                    launcherOpenSeq.stop();
                    launcherCloseAnim.start();
                }
            }
        }
        Timer { id: focusTimer; interval: 90; onTriggered: searchField.forceActiveFocus() }

        MouseArea {
            anchors.fill: parent
            enabled: launcherPanel.revealProgress > 0.95
            onClicked: dockPanel.launcherOpen = false
        }

        Item {
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.bottom: parent.bottom
            anchors.bottomMargin: dockRect.height + dockRect.anchors.bottomMargin + 12
            width: 540; height: 460
            Rectangle {
                id: popupContent
                anchors.fill: parent
                radius: dockPanel.panelRadius
                color: dockPanel.panelBg
                border.width: 1; border.color: dockPanel.tileBorder
                transform: [
                    Translate { y: (1.0 - launcherPanel.revealProgress) * 26 },
                    Scale {
                        origin.x: popupContent.width / 2; origin.y: popupContent.height / 2
                        xScale: 0.9 + 0.1 * launcherPanel.revealProgress
                        yScale: 0.9 + 0.1 * launcherPanel.revealProgress
                    }
                ]
                opacity: Math.min(1.0, launcherPanel.revealProgress * 1.25)
                MouseArea { anchors.fill: parent }
                ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: 16
                    spacing: 12
                    TextField {
                        id: searchField
                        Layout.fillWidth: true
                        placeholderText: "Search applications…"
                        placeholderTextColor: dockPanel.textDim
                        font.pixelSize: 14
                        color: dockPanel.textMain
                        selectByMouse: true
                        focus: true
                        background: Rectangle {
                            radius: dockPanel.searchRadius
                            gradient: Gradient {
                                GradientStop { position: 0.0; color: dockPanel.inputTop }
                                GradientStop { position: 1.0; color: dockPanel.inputBot }
                            }
                            border.width: 1; border.color: dockPanel.tileBorder
                        }
                        onTextChanged: dockPanel.filterApps(text)
                        Keys.onPressed: (event) => {
                            if (event.key === Qt.Key_Escape) {
                                dockPanel.launcherOpen = false; event.accepted = true;
                            }
                        }
                    }
                    GridView {
                        id: appGrid
                        Layout.fillWidth: true; Layout.fillHeight: true
                        cellWidth: 100; cellHeight: 100
                        clip: true
                        model: dockPanel.filteredApps
                        delegate: Item {
                            id: tileItem
                            width: appGrid.cellWidth; height: appGrid.cellHeight
                            property real itemProgress: {
                                const p = launcherPanel.revealProgress;
                                if (p <= 0) return 0;
                                const delay = Math.min(index * 0.012, 0.24);
                                const denom = Math.max(0.5, 1.0 - delay);
                                return Math.max(0, Math.min(1.05, (p - delay) / denom));
                            }
                            property real pressScale: 1.0
                            SequentialAnimation {
                                id: tileBounce
                                NumberAnimation { target: tileItem; property: "pressScale"; to: 0.84; duration: 80; easing.type: Easing.OutQuad }
                                NumberAnimation { target: tileItem; property: "pressScale"; to: 1.0; duration: 520; easing.type: Easing.OutElastic; easing.amplitude: 0.55; easing.period: 0.33 }
                            }
                            property real hoverScale: tileHover.hovered ? 1.06 : 1.0
                            Behavior on hoverScale { NumberAnimation { duration: 240; easing.type: Easing.OutCubic } }
                            opacity: Math.min(1.0, itemProgress)
                            scale: (0.6 + 0.4 * Math.min(1.0, itemProgress)) * pressScale * hoverScale
                            transform: Translate { y: (1.0 - Math.min(1.0, itemProgress)) * 14 }
                            Column {
                                anchors.centerIn: parent
                                spacing: 6
                                Image {
                                    source: dockPanel.resolveIcon(modelData, "application-x-executable")
                                    width: 48; height: 48
                                    fillMode: Image.PreserveAspectFit
                                    sourceSize.width: 96; sourceSize.height: 96
                                    smooth: true
                                    asynchronous: true
                                    anchors.horizontalCenter: parent.horizontalCenter
                                }
                                Text {
                                    text: modelData.name || ""
                                    font.pixelSize: 11
                                    color: dockPanel.textMain
                                    width: appGrid.cellWidth - 12
                                    horizontalAlignment: Text.AlignHCenter
                                    wrapMode: Text.WordWrap
                                    maximumLineCount: 2
                                    elide: Text.ElideRight
                                }
                            }
                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onPressed: tileBounce.restart()
                                onClicked: dockPanel.launchFromLauncher(modelData)
                            }
                            TapHandler {
                                acceptedButtons: Qt.RightButton
                                onTapped: dockPanel.togglePin(modelData)
                            }
                            HoverHandler { id: tileHover }
                        }
                    }
                }
            }
        }
    }

    // ================= Control Center Panel =================
    PanelWindow {
        id: ccPanel
        anchors { top: true; bottom: true; left: true; right: true }
        WlrLayershell.layer: WlrLayer.Top
        WlrLayershell.namespace: "quickshell-cc"
        WlrLayershell.keyboardFocus: (dockPanel.ccOpen || revealProgress > 0.001)
            ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
        exclusionMode: ExclusionMode.Ignore
        color: "transparent"
        visible: dockPanel.ccOpen || revealProgress > 0.001
        property real revealProgress: 0.0
        property int viewDirection: 1
        property real viewAnim: 1.0
        property string previousCcView: "main"

        // real blur behind the panel -> glass, not just transparency
        BackgroundEffect.blurRegion: Region {
            Region { item: ccContent }
        }

        SequentialAnimation {
            id: ccOpenSeq
            PauseAnimation { duration: 30 }
            NumberAnimation {
                target: ccPanel; property: "revealProgress"
                to: 1.0; duration: 380; easing.type: Easing.OutCubic
            }
        }
        NumberAnimation {
            id: ccCloseAnim
            target: ccPanel; property: "revealProgress"
            to: 0.0; duration: 220; easing.type: Easing.InCubic
        }
        Connections {
            target: dockPanel
            function onCcOpenChanged() {
                if (dockPanel.ccOpen) {
                    ccCloseAnim.stop();
                    ccPanel.revealProgress = 0;
                    ccPanel.viewAnim = 1.0;
                    ccPanel.previousCcView = dockPanel.ccView;
                    ccOpenSeq.start();
                    clipProc.running = true;
                    if (dockPanel.ccView === "wifi") wifiScanProc.running = true;
                    if (dockPanel.ccView === "bluetooth") btDevicesProc.running = true;
                    if (dockPanel.ccView === "display") monitorProc.running = true;
                    if (dockPanel.ccView === "wallpapers") wallpaperScan.running = true;
                } else {
                    ccOpenSeq.stop();
                    ccCloseAnim.start();
                }
            }
            function onCcViewChanged() {
                const prev = ccPanel.previousCcView;
                const next = dockPanel.ccView;
                if (prev === "main" && next !== "main") ccPanel.viewDirection = 1;
                else if (prev !== "main" && next === "main") ccPanel.viewDirection = -1;
                else ccPanel.viewDirection = 1;
                ccPanel.previousCcView = next;
                ccPanel.viewAnim = 0;
                ccViewAnim.restart();
                if (next === "display") monitorProc.running = true;
                if (next === "wallpapers") wallpaperScan.running = true;
                if (next === "icons") dockPanel.refreshIconPaths();
            }
        }
        NumberAnimation {
            id: ccViewAnim
            target: ccPanel; property: "viewAnim"
            from: 0; to: 1; duration: 280; easing.type: Easing.OutCubic
        }

        MouseArea {
            anchors.fill: parent
            enabled: ccPanel.revealProgress > 0.95
            onClicked: dockPanel.closeCC()
        }

        Item {
            id: ccContainer
            anchors.right: parent.right
            anchors.rightMargin: 16
            anchors.bottom: parent.bottom
            anchors.bottomMargin: dockRect.height + dockRect.anchors.bottomMargin + 12
            width: 480
            height: 740

            Rectangle {
                id: ccContent
                anchors.fill: parent
                radius: dockPanel.panelRadius
                color: dockPanel.panelBg
                border.width: 1; border.color: dockPanel.tileBorder
                transform: [
                    Translate { y: (1.0 - ccPanel.revealProgress) * 26 },
                    Scale {
                        origin.x: ccContent.width / 2
                        origin.y: ccContent.height / 2
                        xScale: 0.88 + 0.12 * ccPanel.revealProgress
                        yScale: 0.88 + 0.12 * ccPanel.revealProgress
                    }
                ]
                opacity: Math.min(1.0, ccPanel.revealProgress * 1.25)
                MouseArea { anchors.fill: parent }

                Flickable {
                    anchors.fill: parent
                    anchors.margins: 16
                    contentHeight: ccColumn.implicitHeight
                    clip: true

                    ColumnLayout {
                        id: ccColumn
                        width: parent.width
                        spacing: 10

                        // Header
                        RowLayout {
                            Layout.fillWidth: true
                            Layout.preferredHeight: 32
                            Rectangle {
                                visible: dockPanel.ccView !== "main"
                                Layout.preferredWidth: 28
                                Layout.preferredHeight: 28
                                radius: 14
                                color: backHover.containsMouse ? dockPanel.tileBgHover : "transparent"
                                Behavior on color { ColorAnimation { duration: 150; easing.type: Easing.OutCubic } }
                                Text {
                                    anchors.centerIn: parent
                                    text: "‹"
                                    font.pixelSize: 22
                                    font.bold: true
                                    color: dockPanel.textMain
                                }
                                MouseArea {
                                    id: backHover
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: dockPanel.ccView = "main"
                                }
                            }
                            Text {
                                text: dockPanel.ccView === "wifi" ? "WiFi"
                                    : dockPanel.ccView === "bluetooth" ? "Bluetooth"
                                    : dockPanel.ccView === "icons" ? "Icon Theme"
                                    : dockPanel.ccView === "wallpapers" ? "Wallpaper"
                                    : dockPanel.ccView === "display" ? "Displays"
                                    : dockPanel.ccView === "input" ? "Keyboard & Mouse"
                                    : "Control Center"
                                font.pixelSize: 18
                                font.bold: true
                                color: dockPanel.textMain
                                Behavior on color { ColorAnimation { duration: 220; easing.type: Easing.OutCubic } }
                            }
                            Item { Layout.fillWidth: true }
                            Rectangle {
                                Layout.preferredWidth: 28
                                Layout.preferredHeight: 28
                                radius: 14
                                color: closeHover.containsMouse ? "#20ff0000" : "transparent"
                                Behavior on color { ColorAnimation { duration: 150; easing.type: Easing.OutCubic } }
                                Text {
                                    anchors.centerIn: parent
                                    text: "×"
                                    font.pixelSize: 18
                                    color: dockPanel.textDim
                                }
                                MouseArea {
                                    id: closeHover
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: dockPanel.closeCC()
                                }
                            }
                        }

                        // ============ MAIN VIEW ============
                        ColumnLayout {
                            visible: dockPanel.ccView === "main"
                            Layout.fillWidth: true
                            spacing: 10
                            opacity: ccPanel.viewAnim
                            transform: Translate { x: (1 - ccPanel.viewAnim) * ccPanel.viewDirection * 30 }

                            // Quick Toggles (idx 0)
                            RowLayout {
                                property real wProg: dockPanel.ccWidgetProgress(0)
                                Layout.fillWidth: true
                                Layout.preferredHeight: 92
                                spacing: 8
                                opacity: Math.min(1.0, wProg)
                                scale: 0.92 + 0.08 * Math.min(1.0, wProg)
                                transform: Translate { y: (1.0 - Math.min(1.0, wProg)) * 14 }
                                Repeater {
                                    model: [
                                        { id: "wifi", label: "WiFi", icon: "\uf1eb",
                                          active: dockPanel.wifiEnabled,
                                          sub: dockPanel.wifiEnabled ? (dockPanel.wifiSSID || "On") : "Off" },
                                        { id: "bt", label: "Bluetooth", icon: "\uf293",
                                          active: dockPanel.btEnabled,
                                          sub: dockPanel.btEnabled ? "On" : "Off" },
                                        { id: "dnd", label: "Focus", icon: dockPanel.dndEnabled ? "\uf1f6" : "\uf0f3",
                                          active: dockPanel.dndEnabled,
                                          sub: dockPanel.dndEnabled ? "DND" : "Off" }
                                    ]
                                    delegate: Rectangle {
                                        required property var modelData
                                        Layout.fillWidth: true
                                        Layout.preferredHeight: 92
                                        radius: dockPanel.buttonRadius - 4
                                        color: modelData.active ? dockPanel.accent : dockPanel.tileBg
                                        border.width: 1
                                        border.color: modelData.active ? dockPanel.accent : dockPanel.tileBorder
                                        Behavior on color { ColorAnimation { duration: 200; easing.type: Easing.OutCubic } }
                                        ColumnLayout {
                                            anchors.centerIn: parent
                                            spacing: 4
                                            Text {
                                                Layout.alignment: Qt.AlignHCenter
                                                text: modelData.icon
                                                font.pixelSize: 24
                                                color: modelData.active ? "#ffffff" : dockPanel.textMain
                                                Behavior on color { ColorAnimation { duration: 200 } }
                                            }
                                            Text {
                                                Layout.alignment: Qt.AlignHCenter
                                                text: modelData.label
                                                font.pixelSize: 12
                                                font.bold: true
                                                color: modelData.active ? "#ffffff" : dockPanel.textMain
                                            }
                                            Text {
                                                Layout.alignment: Qt.AlignHCenter
                                                text: modelData.sub
                                                font.pixelSize: 10
                                                color: modelData.active ? "#ddffffff" : dockPanel.textDim
                                                elide: Text.ElideRight
                                                Layout.maximumWidth: 120
                                            }
                                        }
                                        MouseArea {
                                            anchors.fill: parent
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: {
                                                if (modelData.id === "wifi") dockPanel.toggleWifi();
                                                else if (modelData.id === "bt") dockPanel.toggleBt();
                                                else if (modelData.id === "dnd") dockPanel.toggleDnd();
                                            }
                                        }
                                        Item {
                                            visible: modelData.id === "wifi" || modelData.id === "bt"
                                            anchors.right: parent.right
                                            anchors.bottom: parent.bottom
                                            anchors.rightMargin: 6
                                            anchors.bottomMargin: 6
                                            width: 20; height: 20
                                            Text {
                                                anchors.centerIn: parent
                                                text: "›"
                                                font.pixelSize: 16
                                                font.bold: true
                                                color: modelData.active ? "#ffffff" : dockPanel.textDim
                                            }
                                            MouseArea {
                                                anchors.fill: parent
                                                cursorShape: Qt.PointingHandCursor
                                                onClicked: {
                                                    if (modelData.id === "wifi") {
                                                        dockPanel.ccView = "wifi";
                                                        if (dockPanel.wifiEnabled) wifiScanProc.running = true;
                                                    } else {
                                                        dockPanel.ccView = "bluetooth";
                                                        if (dockPanel.btEnabled) btDevicesProc.running = true;
                                                    }
                                                }
                                            }
                                        }
                                    }
                                }
                            }

                            // Audio (idx 1)
                            Rectangle {
                                property real wProg: dockPanel.ccWidgetProgress(1)
                                Layout.fillWidth: true
                                Layout.preferredHeight: 80
                                radius: dockPanel.buttonRadius - 4
                                color: dockPanel.tileBg
                                border.width: 1; border.color: dockPanel.tileBorder
                                opacity: Math.min(1.0, wProg)
                                scale: 0.92 + 0.08 * Math.min(1.0, wProg)
                                transform: Translate { y: (1.0 - Math.min(1.0, wProg)) * 14 }
                                ColumnLayout {
                                    anchors.fill: parent
                                    anchors.margins: 12
                                    spacing: 6
                                    RowLayout {
                                        Layout.fillWidth: true
                                        Text {
                                            text: dockPanel.muted ? "\uf026" : "\uf028"
                                            font.pixelSize: 16
                                            color: dockPanel.textMain
                                        }
                                        Text {
                                            text: "Audio"
                                            font.pixelSize: 12; font.bold: true
                                            color: dockPanel.textMain
                                        }
                                        Item { Layout.fillWidth: true }
                                        Text {
                                            text: dockPanel.muted ? "Muted" : (dockPanel.volume + "%")
                                            font.pixelSize: 12
                                            color: dockPanel.textDim
                                        }
                                        Rectangle {
                                            Layout.preferredWidth: 32
                                            Layout.preferredHeight: 32
                                            radius: 16
                                            color: muteHover.containsMouse ? dockPanel.tileBgHover : "transparent"
                                            Behavior on color { ColorAnimation { duration: 150 } }
                                            Text {
                                                anchors.centerIn: parent
                                                text: dockPanel.muted ? "\uf026" : "\uf028"
                                                font.pixelSize: 14
                                                color: dockPanel.textMain
                                            }
                                            MouseArea {
                                                id: muteHover
                                                anchors.fill: parent
                                                hoverEnabled: true
                                                cursorShape: Qt.PointingHandCursor
                                                onClicked: dockPanel.toggleMute()
                                            }
                                        }
                                    }
                                    Slider {
                                        id: volumeSlider
                                        Layout.fillWidth: true
                                        from: 0; to: 100
                                        value: dockPanel.volume
                                        onMoved: {
                                            dockPanel.volume = Math.round(value);
                                            dockPanel.lastVolumeUpdate = Date.now();
                                        }
                                        onPressedChanged: if (!pressed) dockPanel.setVolume(dockPanel.volume)
                                        background: Rectangle {
                                            x: volumeSlider.leftPadding
                                            y: volumeSlider.topPadding + volumeSlider.availableHeight / 2 - height / 2
                                            implicitWidth: 200; implicitHeight: 6
                                            width: volumeSlider.availableWidth
                                            height: implicitHeight
                                            radius: 3
                                            color: "#30ffffff"
                                            Rectangle {
                                                width: volumeSlider.visualPosition * parent.width
                                                height: parent.height
                                                radius: 3
                                                color: dockPanel.accent
                                                Behavior on width { NumberAnimation { duration: 90; easing.type: Easing.OutCubic } }
                                            }
                                        }
                                        handle: Rectangle {
                                            x: volumeSlider.leftPadding + volumeSlider.visualPosition * (volumeSlider.availableWidth - width)
                                            y: volumeSlider.topPadding + volumeSlider.availableHeight / 2 - height / 2
                                            width: 16; height: 16; radius: 8
                                            color: "#ffffff"
                                            border.width: 2
                                            border.color: dockPanel.accent
                                            scale: volumeSlider.pressed ? 1.15 : 1.0
                                            Behavior on scale { NumberAnimation { duration: 150; easing.type: Easing.OutCubic } }
                                        }
                                    }
                                }
                            }

                            // Customization (idx 2)
                            Rectangle {
                                property real wProg: dockPanel.ccWidgetProgress(2)
                                Layout.fillWidth: true
                                Layout.preferredHeight: 420
                                radius: dockPanel.buttonRadius - 4
                                color: dockPanel.tileBg
                                border.width: 1; border.color: dockPanel.tileBorder
                                opacity: Math.min(1.0, wProg)
                                scale: 0.92 + 0.08 * Math.min(1.0, wProg)
                                transform: Translate { y: (1.0 - Math.min(1.0, wProg)) * 14 }
                                ColumnLayout {
                                    anchors.fill: parent
                                    anchors.margins: 12
                                    spacing: 10
                                    RowLayout {
                                        Layout.fillWidth: true
                                        Text { text: "\uf1fc"; font.pixelSize: 16; color: dockPanel.textMain }
                                        Text {
                                            text: "Customization"
                                            font.pixelSize: 12; font.bold: true
                                            color: dockPanel.textMain
                                        }
                                        Item { Layout.fillWidth: true }
                                    }

                                    // Dark mode
                                    RowLayout {
                                        Layout.fillWidth: true
                                        Text {
                                            text: "Dark mode"
                                            font.pixelSize: 11
                                            color: dockPanel.textDim
                                            Layout.preferredWidth: 60
                                        }
                                        Item { Layout.fillWidth: true }
                                        Rectangle {
                                            Layout.preferredWidth: 44
                                            Layout.preferredHeight: 24
                                            radius: 12
                                            color: dockPanel.darkMode ? dockPanel.accent : "#30ffffff"
                                            Behavior on color { ColorAnimation { duration: 220; easing.type: Easing.OutCubic } }
                                            Rectangle {
                                                x: dockPanel.darkMode ? parent.width - width - 2 : 2
                                                y: 2
                                                width: 20; height: 20; radius: 10
                                                color: "#ffffff"
                                                Behavior on x { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }
                                            }
                                            MouseArea {
                                                anchors.fill: parent
                                                cursorShape: Qt.PointingHandCursor
                                                onClicked: {
                                                    dockPanel.darkMode = !dockPanel.darkMode;
                                                    dockPanel.saveSettings();
                                                }
                                            }
                                        }
                                    }

                                    // Accent colors
                                    Text {
                                        text: "Accent color"
                                        font.pixelSize: 11
                                        color: dockPanel.textDim
                                    }
                                    Grid {
                                        Layout.fillWidth: true
                                        columns: 6
                                        rowSpacing: 6
                                        columnSpacing: 6
                                        Repeater {
                                            model: dockPanel.accentColors
                                            delegate: Rectangle {
                                                required property var modelData
                                                width: 30; height: 30; radius: 15
                                                color: modelData
                                                border.width: (String(dockPanel.accent).toLowerCase() === String(modelData).toLowerCase()) ? 3 : 1
                                                border.color: (String(dockPanel.accent).toLowerCase() === String(modelData).toLowerCase()) ? "#ffffff" : dockPanel.tileBorder
                                                Behavior on border.width { NumberAnimation { duration: 140; easing.type: Easing.OutCubic } }
                                                scale: swatchHover.containsMouse ? 1.1 : 1.0
                                                Behavior on scale { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }
                                                MouseArea {
                                                    id: swatchHover
                                                    anchors.fill: parent
                                                    hoverEnabled: true
                                                    cursorShape: Qt.PointingHandCursor
                                                    onClicked: {
                                                        dockPanel.accent = modelData;
                                                        dockPanel.saveSettings();
                                                    }
                                                }
                                            }
                                        }
                                    }

                                    // Glass
                                    RowLayout {
                                        Layout.fillWidth: true
                                        Text {
                                            text: "Glass"
                                            font.pixelSize: 11
                                            color: dockPanel.textDim
                                            Layout.preferredWidth: 60
                                        }
                                        Slider {
                                            id: glassSlider
                                            Layout.fillWidth: true
                                            from: 0.15; to: 0.95
                                            value: dockPanel.glassOpacity
                                            onMoved: dockPanel.glassOpacity = value
                                            onPressedChanged: if (!pressed) dockPanel.saveSettings()
                                            background: Rectangle {
                                                x: glassSlider.leftPadding
                                                y: glassSlider.topPadding + glassSlider.availableHeight / 2 - height / 2
                                                implicitWidth: 200; implicitHeight: 6
                                                width: glassSlider.availableWidth
                                                height: implicitHeight
                                                radius: 3
                                                color: "#30ffffff"
                                                Rectangle {
                                                    width: glassSlider.visualPosition * parent.width
                                                    height: parent.height; radius: 3
                                                    color: dockPanel.accent
                                                }
                                            }
                                            handle: Rectangle {
                                                x: glassSlider.leftPadding + glassSlider.visualPosition * (glassSlider.availableWidth - width)
                                                y: glassSlider.topPadding + glassSlider.availableHeight / 2 - height / 2
                                                width: 16; height: 16; radius: 8
                                                color: "#ffffff"
                                                border.width: 2; border.color: dockPanel.accent
                                            }
                                        }
                                        Text {
                                            text: Math.round(dockPanel.glassOpacity * 100) + "%"
                                            font.pixelSize: 11
                                            color: dockPanel.textDim
                                            Layout.preferredWidth: 40
                                        }
                                    }

                                    // Radius
                                    RowLayout {
                                        Layout.fillWidth: true
                                        Text {
                                            text: "Radius"
                                            font.pixelSize: 11
                                            color: dockPanel.textDim
                                            Layout.preferredWidth: 60
                                        }
                                        Slider {
                                            id: radiusSlider
                                            Layout.fillWidth: true
                                            from: 8; to: 32
                                            value: dockPanel.cornerRadius
                                            onMoved: dockPanel.cornerRadius = value
                                            onPressedChanged: if (!pressed) dockPanel.saveSettings()
                                            background: Rectangle {
                                                x: radiusSlider.leftPadding
                                                y: radiusSlider.topPadding + radiusSlider.availableHeight / 2 - height / 2
                                                implicitWidth: 200; implicitHeight: 6
                                                width: radiusSlider.availableWidth
                                                height: implicitHeight
                                                radius: 3
                                                color: "#30ffffff"
                                                Rectangle {
                                                    width: radiusSlider.visualPosition * parent.width
                                                    height: parent.height; radius: 3
                                                    color: dockPanel.accent
                                                }
                                            }
                                            handle: Rectangle {
                                                x: radiusSlider.leftPadding + radiusSlider.visualPosition * (radiusSlider.availableWidth - width)
                                                y: radiusSlider.topPadding + radiusSlider.availableHeight / 2 - height / 2
                                                width: 16; height: 16; radius: 8
                                                color: "#ffffff"
                                                border.width: 2; border.color: dockPanel.accent
                                            }
                                        }
                                        Text {
                                            text: Math.round(dockPanel.cornerRadius) + "px"
                                            font.pixelSize: 11
                                            color: dockPanel.textDim
                                            Layout.preferredWidth: 40
                                        }
                                    }

                                    // Wallpaper
                                    RowLayout {
                                        Layout.fillWidth: true
                                        spacing: 8
                                        Text {
                                            text: "Wallpaper"
                                            font.pixelSize: 11
                                            color: dockPanel.textDim
                                            Layout.preferredWidth: 60
                                        }
                                        Rectangle {
                                            Layout.preferredWidth: 32
                                            Layout.preferredHeight: 24
                                            radius: 4
                                            color: dockPanel.tileBgHover
                                            clip: true
                                            Image {
                                                anchors.fill: parent
                                                source: dockPanel.wallpaperPath ? "file://" + dockPanel.wallpaperPath : ""
                                                fillMode: Image.PreserveAspectCrop
                                                sourceSize.width: 64
                                                sourceSize.height: 48
                                                visible: dockPanel.wallpaperPath !== ""
                                            }
                                        }
                                        Text {
                                            Layout.fillWidth: true
                                            text: dockPanel.wallpaperPath
                                                ? dockPanel.wallpaperPath.split("/").pop()
                                                : "None"
                                            font.pixelSize: 11
                                            color: dockPanel.textMain
                                            elide: Text.ElideMiddle
                                        }
                                        Rectangle {
                                            Layout.preferredWidth: 70
                                            Layout.preferredHeight: 26
                                            radius: 13
                                            color: wpChooseHover.containsMouse ? dockPanel.tileBgHover : "transparent"
                                            border.width: 1; border.color: dockPanel.tileBorder
                                            Behavior on color { ColorAnimation { duration: 150 } }
                                            Text {
                                                anchors.centerIn: parent
                                                text: "Choose"
                                                font.pixelSize: 11
                                                color: dockPanel.textMain
                                            }
                                            MouseArea {
                                                id: wpChooseHover
                                                anchors.fill: parent
                                                hoverEnabled: true
                                                cursorShape: Qt.PointingHandCursor
                                                onClicked: dockPanel.openWallpaperView()
                                            }
                                        }
                                    }

                                    // Icon theme
                                    RowLayout {
                                        Layout.fillWidth: true
                                        spacing: 8
                                        Text {
                                            text: "Icon theme"
                                            font.pixelSize: 11
                                            color: dockPanel.textDim
                                            Layout.preferredWidth: 60
                                        }
                                        Text {
                                            Layout.fillWidth: true
                                            text: dockPanel.iconTheme || "Default"
                                            font.pixelSize: 11
                                            color: dockPanel.textMain
                                            elide: Text.ElideRight
                                        }
                                        Rectangle {
                                            Layout.preferredWidth: 70
                                            Layout.preferredHeight: 26
                                            radius: 13
                                            color: iconThemeHover.containsMouse ? dockPanel.tileBgHover : "transparent"
                                            border.width: 1; border.color: dockPanel.tileBorder
                                            Behavior on color { ColorAnimation { duration: 150 } }
                                            Text {
                                                anchors.centerIn: parent
                                                text: "Choose ›"
                                                font.pixelSize: 11
                                                color: dockPanel.textMain
                                            }
                                            MouseArea {
                                                id: iconThemeHover
                                                anchors.fill: parent
                                                hoverEnabled: true
                                                cursorShape: Qt.PointingHandCursor
                                                onClicked: {
                                                    dockPanel.ccView = "icons";
                                                    dockPanel.refreshIconPaths();
                                                }
                                            }
                                        }
                                    }
                                }
                            }

                            // Displays (idx 6)
                            Rectangle {
                                property real wProg: dockPanel.ccWidgetProgress(6)
                                Layout.fillWidth: true
                                Layout.preferredHeight: 64
                                radius: dockPanel.buttonRadius - 4
                                color: dockPanel.tileBg
                                border.width: 1; border.color: dockPanel.tileBorder
                                opacity: Math.min(1.0, wProg)
                                scale: 0.92 + 0.08 * Math.min(1.0, wProg)
                                transform: Translate { y: (1.0 - Math.min(1.0, wProg)) * 14 }
                                RowLayout {
                                    anchors.fill: parent
                                    anchors.margins: 12
                                    spacing: 10
                                    Text { text: "\uf108"; font.pixelSize: 18; color: dockPanel.textMain }
                                    ColumnLayout {
                                        Layout.fillWidth: true
                                        spacing: 2
                                        Text {
                                            text: "Displays"
                                            font.pixelSize: 12; font.bold: true
                                            color: dockPanel.textMain
                                        }
                                        Text {
                                            Layout.fillWidth: true
                                            text: dockPanel.monitors.length > 0
                                                ? dockPanel.monitors.length
                                                    + (dockPanel.monitors.length > 1 ? " monitors" : " monitor")
                                                    + " · " + dockPanel.monitors[0].width
                                                    + "×" + dockPanel.monitors[0].height
                                                    + " @ " + dockPanel.monitors[0].refresh + " Hz"
                                                : "Detecting…"
                                            font.pixelSize: 10
                                            color: dockPanel.textDim
                                            elide: Text.ElideRight
                                        }
                                    }
                                    Rectangle {
                                        Layout.preferredWidth: 88
                                        Layout.preferredHeight: 28
                                        radius: 14
                                        color: dispHover.containsMouse ? dockPanel.tileBgHover : "transparent"
                                        border.width: 1; border.color: dockPanel.tileBorder
                                        Text {
                                            anchors.centerIn: parent
                                            text: "Configure ›"
                                            font.pixelSize: 11
                                            color: dockPanel.textMain
                                        }
                                        MouseArea {
                                            id: dispHover
                                            anchors.fill: parent
                                            hoverEnabled: true
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: {
                                                monitorProc.running = true;
                                                dockPanel.ccView = "display";
                                            }
                                        }
                                    }
                                }
                            }

                            // Keyboard & mouse (idx 7)
                            Rectangle {
                                property real wProg: dockPanel.ccWidgetProgress(7)
                                Layout.fillWidth: true
                                Layout.preferredHeight: 64
                                radius: dockPanel.buttonRadius - 4
                                color: dockPanel.tileBg
                                border.width: 1; border.color: dockPanel.tileBorder
                                opacity: Math.min(1.0, wProg)
                                scale: 0.92 + 0.08 * Math.min(1.0, wProg)
                                transform: Translate { y: (1.0 - Math.min(1.0, wProg)) * 14 }
                                RowLayout {
                                    anchors.fill: parent
                                    anchors.margins: 12
                                    spacing: 10
                                    Text { text: "\uf11c"; font.pixelSize: 18; color: dockPanel.textMain }
                                    ColumnLayout {
                                        Layout.fillWidth: true
                                        spacing: 2
                                        Text {
                                            text: "Keyboard & Mouse"
                                            font.pixelSize: 12; font.bold: true
                                            color: dockPanel.textMain
                                        }
                                        Text {
                                            Layout.fillWidth: true
                                            text: dockPanel.inputCfg.kb_layout
                                                + " · follow " + dockPanel.inputCfg.follow_mouse
                                                + " · sens " + Number(dockPanel.inputCfg.sensitivity).toFixed(2)
                                            font.pixelSize: 10
                                            color: dockPanel.textDim
                                            elide: Text.ElideRight
                                        }
                                    }
                                    Rectangle {
                                        Layout.preferredWidth: 88
                                        Layout.preferredHeight: 28
                                        radius: 14
                                        color: inputHover.containsMouse ? dockPanel.tileBgHover : "transparent"
                                        border.width: 1; border.color: dockPanel.tileBorder
                                        Text {
                                            anchors.centerIn: parent
                                            text: "Configure ›"
                                            font.pixelSize: 11
                                            color: dockPanel.textMain
                                        }
                                        MouseArea {
                                            id: inputHover
                                            anchors.fill: parent
                                            hoverEnabled: true
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: dockPanel.ccView = "input"
                                        }
                                    }
                                }
                            }

                            // Notifications (idx 3)
                            Rectangle {
                                property real wProg: dockPanel.ccWidgetProgress(3)
                                Layout.fillWidth: true
                                Layout.preferredHeight: 60
                                radius: dockPanel.buttonRadius - 4
                                color: dockPanel.tileBg
                                border.width: 1; border.color: dockPanel.tileBorder
                                opacity: Math.min(1.0, wProg)
                                scale: 0.92 + 0.08 * Math.min(1.0, wProg)
                                transform: Translate { y: (1.0 - Math.min(1.0, wProg)) * 14 }
                                RowLayout {
                                    anchors.fill: parent
                                    anchors.margins: 12
                                    spacing: 8
                                    Text { text: "\uf0f3"; font.pixelSize: 16; color: dockPanel.textMain }
                                    Text {
                                        text: dockPanel.notifCount > 0
                                            ? dockPanel.notifCount + " unread"
                                            : "No notifications"
                                        font.pixelSize: 12
                                        color: dockPanel.textMain
                                    }
                                    Item { Layout.fillWidth: true }
                                    Rectangle {
                                        visible: dockPanel.notifCount > 0
                                        Layout.preferredWidth: 80
                                        Layout.preferredHeight: 28
                                        radius: 14
                                        color: clearHover.containsMouse ? dockPanel.danger : dockPanel.tileBgHover
                                        Behavior on color { ColorAnimation { duration: 150 } }
                                        Text {
                                            anchors.centerIn: parent
                                            text: "Clear all"
                                            font.pixelSize: 11
                                            color: clearHover.containsMouse ? "#ffffff" : dockPanel.textMain
                                        }
                                        MouseArea {
                                            id: clearHover
                                            anchors.fill: parent
                                            hoverEnabled: true
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: dockPanel.clearNotifications()
                                        }
                                    }
                                }
                            }

                            // Power (idx 4)
                            Rectangle {
                                property real wProg: dockPanel.ccWidgetProgress(4)
                                Layout.fillWidth: true
                                Layout.preferredHeight: 88
                                radius: dockPanel.buttonRadius - 4
                                color: dockPanel.tileBg
                                border.width: 1; border.color: dockPanel.tileBorder
                                opacity: Math.min(1.0, wProg)
                                scale: 0.92 + 0.08 * Math.min(1.0, wProg)
                                transform: Translate { y: (1.0 - Math.min(1.0, wProg)) * 14 }
                                RowLayout {
                                    anchors.fill: parent
                                    anchors.margins: 8
                                    spacing: 6
                                    Repeater {
                                        model: [
                                            { id: "lock", label: "Lock", icon: "\uf023" },
                                            { id: "logout", label: "Logout", icon: "\uf2f5" },
                                            { id: "sleep", label: "Sleep", icon: "\uf186" },
                                            { id: "reboot", label: "Reboot", icon: "\uf021" },
                                            { id: "shutdown", label: "Off", icon: "\uf011" }
                                        ]
                                        delegate: Rectangle {
                                            required property var modelData
                                            Layout.fillWidth: true
                                            Layout.fillHeight: true
                                            radius: dockPanel.buttonRadius - 8
                                            color: (dockPanel.pendingPowerAction === modelData.id)
                                                ? dockPanel.danger
                                                : (powerHover.containsMouse ? dockPanel.tileBgHover : "transparent")
                                            Behavior on color { ColorAnimation { duration: 160; easing.type: Easing.OutCubic } }
                                            scale: powerHover.containsMouse ? 1.04 : 1.0
                                            Behavior on scale { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }
                                            ColumnLayout {
                                                anchors.centerIn: parent
                                                spacing: 4
                                                Text {
                                                    Layout.alignment: Qt.AlignHCenter
                                                    text: modelData.icon
                                                    font.pixelSize: 18
                                                    color: (dockPanel.pendingPowerAction === modelData.id)
                                                        ? "#ffffff" : dockPanel.textMain
                                                }
                                                Text {
                                                    Layout.alignment: Qt.AlignHCenter
                                                    text: (dockPanel.pendingPowerAction === modelData.id)
                                                        ? "Sure?" : modelData.label
                                                    font.pixelSize: 10
                                                    color: (dockPanel.pendingPowerAction === modelData.id)
                                                        ? "#ffffff" : dockPanel.textDim
                                                }
                                            }
                                            MouseArea {
                                                id: powerHover
                                                anchors.fill: parent
                                                hoverEnabled: true
                                                cursorShape: Qt.PointingHandCursor
                                                onClicked: dockPanel.powerAction(modelData.id)
                                            }
                                        }
                                    }
                                }
                            }

                            // Clipboard (idx 5)
                            Rectangle {
                                property real wProg: dockPanel.ccWidgetProgress(5)
                                property int visibleCount: Math.min(dockPanel.clipboardHistory.length, 10)
                                Layout.fillWidth: true
                                Layout.preferredHeight: 60 + visibleCount * 32
                                radius: dockPanel.buttonRadius - 4
                                color: dockPanel.tileBg
                                border.width: 1; border.color: dockPanel.tileBorder
                                opacity: Math.min(1.0, wProg)
                                scale: 0.92 + 0.08 * Math.min(1.0, wProg)
                                transform: Translate { y: (1.0 - Math.min(1.0, wProg)) * 14 }

                                ColumnLayout {
                                    anchors.fill: parent
                                    anchors.margins: 12
                                    spacing: 6

                                    RowLayout {
                                        Layout.fillWidth: true
                                        Layout.preferredHeight: 24
                                        Text { text: "\uf0ea"; font.pixelSize: 16; color: dockPanel.textMain }
                                        Text {
                                            text: "Clipboard"
                                            font.pixelSize: 12; font.bold: true
                                            color: dockPanel.textMain
                                        }
                                        Item { Layout.fillWidth: true }
                                        Text {
                                            visible: dockPanel.clipboardHistory.length > 0
                                            text: dockPanel.clipboardHistory.length + " items"
                                                + (dockPanel.clipboardHistory.length > 10 ? " · scroll" : "")
                                            font.pixelSize: 10
                                            color: dockPanel.textDim
                                        }
                                    }

                                    Flickable {
                                        Layout.fillWidth: true
                                        Layout.fillHeight: true
                                        contentHeight: clipItemsCol.height
                                        clip: true
                                        boundsBehavior: Flickable.StopAtBounds

                                        Column {
                                            id: clipItemsCol
                                            width: parent.width
                                            spacing: 2

                                            Repeater {
                                                model: dockPanel.clipboardHistory
                                                delegate: Rectangle {
                                                    required property var modelData
                                                    width: clipItemsCol.width
                                                    height: 30
                                                    radius: Math.max(4, dockPanel.buttonRadius - 12)
                                                    color: clipItemHover.containsMouse ? dockPanel.tileBgHover : "transparent"
                                                    Behavior on color { ColorAnimation { duration: 150 } }
                                                    RowLayout {
                                                        anchors.fill: parent
                                                        anchors.leftMargin: 8
                                                        anchors.rightMargin: 8
                                                        spacing: 8
                                                        Text { text: "\uf0c5"; font.pixelSize: 11; color: dockPanel.textDim }
                                                        Text {
                                                            Layout.fillWidth: true
                                                            text: {
                                                                const t = modelData.text.split("\n")[0];
                                                                return t.length > 60 ? t.substring(0, 60) + "…" : t;
                                                            }
                                                            font.pixelSize: 11
                                                            color: dockPanel.textMain
                                                            elide: Text.ElideRight
                                                            textFormat: Text.PlainText
                                                        }
                                                    }
                                                    MouseArea {
                                                        id: clipItemHover
                                                        anchors.fill: parent
                                                        hoverEnabled: true
                                                        cursorShape: Qt.PointingHandCursor
                                                        onClicked: dockPanel.copyClipboard(modelData.id)
                                                    }
                                                }
                                            }

                                            Text {
                                                visible: dockPanel.clipboardHistory.length === 0
                                                width: parent.width
                                                text: "Clipboard is empty"
                                                font.pixelSize: 11
                                                color: dockPanel.textDim
                                                horizontalAlignment: Text.AlignHCenter
                                            }
                                        }
                                    }
                                }
                            }
                        }

                        // ============ WIFI VIEW ============
                        ColumnLayout {
                            visible: dockPanel.ccView === "wifi"
                            Layout.fillWidth: true
                            spacing: 10
                            opacity: ccPanel.viewAnim
                            transform: Translate { x: (1 - ccPanel.viewAnim) * ccPanel.viewDirection * 30 }

                            Rectangle {
                                Layout.fillWidth: true
                                Layout.preferredHeight: 60
                                radius: dockPanel.buttonRadius - 4
                                color: dockPanel.tileBg
                                border.width: 1; border.color: dockPanel.tileBorder
                                RowLayout {
                                    anchors.fill: parent
                                    anchors.margins: 12
                                    spacing: 10
                                    Text {
                                        text: "\uf1eb"
                                        font.pixelSize: 20
                                        color: dockPanel.wifiEnabled ? dockPanel.accent : dockPanel.textDim
                                        Behavior on color { ColorAnimation { duration: 200 } }
                                    }
                                    ColumnLayout {
                                        spacing: 2
                                        Text {
                                            text: "WiFi"
                                            font.pixelSize: 13; font.bold: true
                                            color: dockPanel.textMain
                                        }
                                        Text {
                                            text: dockPanel.wifiEnabled ? (dockPanel.wifiSSID || "On") : "Off"
                                            font.pixelSize: 11
                                            color: dockPanel.textDim
                                        }
                                    }
                                    Item { Layout.fillWidth: true }
                                    Rectangle {
                                        Layout.preferredWidth: 44
                                        Layout.preferredHeight: 24
                                        radius: 12
                                        color: dockPanel.wifiEnabled ? dockPanel.accent : "#30ffffff"
                                        Behavior on color { ColorAnimation { duration: 220; easing.type: Easing.OutCubic } }
                                        Rectangle {
                                            x: dockPanel.wifiEnabled ? parent.width - width - 2 : 2
                                            y: 2
                                            width: 20; height: 20; radius: 10
                                            color: "#ffffff"
                                            Behavior on x { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }
                                        }
                                        MouseArea {
                                            anchors.fill: parent
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: dockPanel.toggleWifi()
                                        }
                                    }
                                }
                            }

                            RowLayout {
                                Layout.fillWidth: true
                                Layout.preferredHeight: 32
                                Text {
                                    text: dockPanel.wifiEnabled ? "Available networks" : "WiFi is off"
                                    font.pixelSize: 12; font.bold: true
                                    color: dockPanel.textMain
                                }
                                Item { Layout.fillWidth: true }
                                Rectangle {
                                    visible: dockPanel.wifiEnabled
                                    Layout.preferredWidth: 80
                                    Layout.preferredHeight: 28
                                    radius: 14
                                    color: refreshHover.containsMouse ? dockPanel.tileBgHover : "transparent"
                                    Behavior on color { ColorAnimation { duration: 150 } }
                                    Text {
                                        anchors.centerIn: parent
                                        text: "Refresh"
                                        font.pixelSize: 11
                                        color: dockPanel.textMain
                                    }
                                    MouseArea {
                                        id: refreshHover
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: wifiScanProc.running = true
                                    }
                                }
                            }

                            Repeater {
                                model: dockPanel.wifiEnabled ? dockPanel.wifiNetworks : []
                                delegate: Rectangle {
                                    required property var modelData
                                    Layout.fillWidth: true
                                    Layout.preferredHeight: 44
                                    radius: dockPanel.buttonRadius - 8
                                    color: modelData.active ? dockPanel.accent
                                        : (netHover.containsMouse ? dockPanel.tileBgHover : dockPanel.tileBg)
                                    border.width: 1
                                    border.color: modelData.active ? dockPanel.accent : dockPanel.tileBorder
                                    Behavior on color { ColorAnimation { duration: 150 } }
                                    RowLayout {
                                        anchors.fill: parent
                                        anchors.margins: 10
                                        spacing: 10
                                        Item {
                                            Layout.preferredWidth: 20
                                            Layout.preferredHeight: 16
                                            Row {
                                                anchors.bottom: parent.bottom
                                                spacing: 1
                                                Repeater {
                                                    model: 4
                                                    delegate: Rectangle {
                                                        required property int index
                                                        width: 4
                                                        height: 4 + index * 4
                                                        radius: 1
                                                        color: {
                                                            const sig = modelData.signal;
                                                            const th = [25, 50, 75, 100][index];
                                                            return sig >= th
                                                                ? (modelData.active ? "#ffffff" : dockPanel.textMain)
                                                                : "#30ffffff";
                                                        }
                                                    }
                                                }
                                            }
                                        }
                                        Text {
                                            Layout.fillWidth: true
                                            text: modelData.ssid
                                            font.pixelSize: 12
                                            color: modelData.active ? "#ffffff" : dockPanel.textMain
                                            elide: Text.ElideRight
                                        }
                                        Text {
                                            visible: modelData.sec && modelData.sec !== "--" && modelData.sec !== ""
                                            text: "\uf023"
                                            font.pixelSize: 11
                                            color: modelData.active ? "#ffffff" : dockPanel.textDim
                                        }
                                        Rectangle {
                                            visible: modelData.active
                                            Layout.preferredWidth: 70
                                            Layout.preferredHeight: 20
                                            radius: 10
                                            color: "#30ffffff"
                                            Text {
                                                anchors.centerIn: parent
                                                text: "Connected"
                                                font.pixelSize: 9
                                                color: "#ffffff"
                                            }
                                        }
                                    }
                                    MouseArea {
                                        id: netHover
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: dockPanel.connectOrDisconnectWifi(modelData)
                                    }
                                }
                            }

                            Text {
                                visible: dockPanel.wifiEnabled && dockPanel.wifiNetworks.length === 0
                                Layout.fillWidth: true
                                text: "Scanning for networks…"
                                font.pixelSize: 11
                                color: dockPanel.textDim
                                horizontalAlignment: Text.AlignHCenter
                            }
                        }

                        // ============ BLUETOOTH VIEW ============
                        ColumnLayout {
                            visible: dockPanel.ccView === "bluetooth"
                            Layout.fillWidth: true
                            spacing: 10
                            opacity: ccPanel.viewAnim
                            transform: Translate { x: (1 - ccPanel.viewAnim) * ccPanel.viewDirection * 30 }

                            Rectangle {
                                Layout.fillWidth: true
                                Layout.preferredHeight: 60
                                radius: dockPanel.buttonRadius - 4
                                color: dockPanel.tileBg
                                border.width: 1; border.color: dockPanel.tileBorder
                                RowLayout {
                                    anchors.fill: parent
                                    anchors.margins: 12
                                    spacing: 10
                                    Text {
                                        text: "\uf293"
                                        font.pixelSize: 20
                                        color: dockPanel.btEnabled ? dockPanel.accent : dockPanel.textDim
                                        Behavior on color { ColorAnimation { duration: 200 } }
                                    }
                                    ColumnLayout {
                                        spacing: 2
                                        Text {
                                            text: "Bluetooth"
                                            font.pixelSize: 13; font.bold: true
                                            color: dockPanel.textMain
                                        }
                                        Text {
                                            text: dockPanel.btEnabled ? "On" : "Off"
                                            font.pixelSize: 11
                                            color: dockPanel.textDim
                                        }
                                    }
                                    Item { Layout.fillWidth: true }
                                    Rectangle {
                                        Layout.preferredWidth: 44
                                        Layout.preferredHeight: 24
                                        radius: 12
                                        color: dockPanel.btEnabled ? dockPanel.accent : "#30ffffff"
                                        Behavior on color { ColorAnimation { duration: 220; easing.type: Easing.OutCubic } }
                                        Rectangle {
                                            x: dockPanel.btEnabled ? parent.width - width - 2 : 2
                                            y: 2
                                            width: 20; height: 20; radius: 10
                                            color: "#ffffff"
                                            Behavior on x { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }
                                        }
                                        MouseArea {
                                            anchors.fill: parent
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: dockPanel.toggleBt()
                                        }
                                    }
                                }
                            }

                            RowLayout {
                                Layout.fillWidth: true
                                Layout.preferredHeight: 32
                                Text {
                                    text: dockPanel.btEnabled ? "Paired devices" : "Bluetooth is off"
                                    font.pixelSize: 12; font.bold: true
                                    color: dockPanel.textMain
                                }
                                Item { Layout.fillWidth: true }
                                Rectangle {
                                    visible: dockPanel.btEnabled
                                    Layout.preferredWidth: 80
                                    Layout.preferredHeight: 28
                                    radius: 14
                                    color: btRefreshHover.containsMouse ? dockPanel.tileBgHover : "transparent"
                                    Behavior on color { ColorAnimation { duration: 150 } }
                                    Text {
                                        anchors.centerIn: parent
                                        text: "Refresh"
                                        font.pixelSize: 11
                                        color: dockPanel.textMain
                                    }
                                    MouseArea {
                                        id: btRefreshHover
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: btDevicesProc.running = true
                                    }
                                }
                            }

                            Repeater {
                                model: dockPanel.btEnabled ? dockPanel.btDevices : []
                                delegate: Rectangle {
                                    required property var modelData
                                    Layout.fillWidth: true
                                    Layout.preferredHeight: 48
                                    radius: dockPanel.buttonRadius - 8
                                    color: modelData.connected ? dockPanel.accent
                                        : (btHover.containsMouse ? dockPanel.tileBgHover : dockPanel.tileBg)
                                    border.width: 1
                                    border.color: modelData.connected ? dockPanel.accent : dockPanel.tileBorder
                                    Behavior on color { ColorAnimation { duration: 150 } }
                                    RowLayout {
                                        anchors.fill: parent
                                        anchors.margins: 10
                                        spacing: 10
                                        Text {
                                            text: "\uf293"
                                            font.pixelSize: 16
                                            color: modelData.connected ? "#ffffff" : dockPanel.textMain
                                        }
                                        ColumnLayout {
                                            Layout.fillWidth: true
                                            spacing: 2
                                            Text {
                                                text: modelData.name || "Unknown"
                                                font.pixelSize: 12
                                                color: modelData.connected ? "#ffffff" : dockPanel.textMain
                                                elide: Text.ElideRight
                                            }
                                            Text {
                                                text: modelData.mac
                                                font.pixelSize: 10
                                                color: modelData.connected ? "#ddffffff" : dockPanel.textDim
                                            }
                                        }
                                        Rectangle {
                                            Layout.preferredWidth: 90
                                            Layout.preferredHeight: 28
                                            radius: 14
                                            color: "#30ffffff"
                                            Text {
                                                anchors.centerIn: parent
                                                text: modelData.connected ? "Disconnect" : "Connect"
                                                font.pixelSize: 10
                                                color: modelData.connected ? "#ffffff" : dockPanel.textMain
                                            }
                                        }
                                    }
                                    MouseArea {
                                        id: btHover
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: dockPanel.toggleBtDevice(modelData)
                                    }
                                }
                            }

                            Text {
                                visible: dockPanel.btEnabled && dockPanel.btDevices.length === 0
                                Layout.fillWidth: true
                                text: "No paired devices\nPair with bluetoothctl"
                                font.pixelSize: 11
                                color: dockPanel.textDim
                                horizontalAlignment: Text.AlignHCenter
                            }
                        }

                        // ============ WALLPAPER VIEW ============
                        ColumnLayout {
                            visible: dockPanel.ccView === "wallpapers"
                            Layout.fillWidth: true
                            spacing: 10
                            opacity: ccPanel.viewAnim
                            transform: Translate { x: (1 - ccPanel.viewAnim) * ccPanel.viewDirection * 30 }

                            Text {
                                Layout.fillWidth: true
                                text: "Wallpapers are found from the following folders: ~/Pictures, "
                                      + "~/Pictures/Wallpapers, ~/Wallpapers, ~/.local/share/wallpapers, "
                                      + "~/Downloads and /usr/share/wallpapers"
                                font.pixelSize: 11
                                color: dockPanel.textDim
                                wrapMode: Text.WordWrap
                            }

                            Item {
                                Layout.fillWidth: true
                                Layout.preferredHeight: wpGrid.height
                                Grid {
                                    id: wpGrid
                                    width: parent.width
                                    columns: Math.max(1, Math.floor(width / 112))
                                    rowSpacing: 8
                                    columnSpacing: 8
                                    Repeater {
                                        model: dockPanel.wallpapers
                                        delegate: Rectangle {
                                            required property var modelData
                                            width: 104; height: 68
                                            radius: 8
                                            color: dockPanel.tileBg
                                            border.width: dockPanel.wallpaperPath === modelData ? 2 : 1
                                            border.color: dockPanel.wallpaperPath === modelData
                                                ? dockPanel.accent : dockPanel.tileBorder
                                            scale: wpHover.containsMouse ? 1.04 : 1.0
                                            Behavior on scale { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }
                                            Behavior on border.color { ColorAnimation { duration: 160 } }
                                            Image {
                                                anchors.fill: parent
                                                anchors.margins: 2
                                                source: "file://" + modelData
                                                fillMode: Image.PreserveAspectCrop
                                                sourceSize.width: 208
                                                sourceSize.height: 136
                                                asynchronous: true
                                                cache: false
                                                smooth: true
                                            }
                                            MouseArea {
                                                id: wpHover
                                                anchors.fill: parent
                                                hoverEnabled: true
                                                cursorShape: Qt.PointingHandCursor
                                                onClicked: dockPanel.applyWallpaper(modelData)
                                            }
                                        }
                                    }
                                }
                            }

                            Text {
                                visible: dockPanel.wallpapers.length === 0
                                Layout.fillWidth: true
                                text: "No images found in the folders listed above"
                                font.pixelSize: 11
                                color: dockPanel.textDim
                                horizontalAlignment: Text.AlignHCenter
                                wrapMode: Text.WordWrap
                            }
                        }

                        // ============ DISPLAY / MONITORS VIEW ============
                        ColumnLayout {
                            visible: dockPanel.ccView === "display"
                            Layout.fillWidth: true
                            spacing: 10
                            opacity: ccPanel.viewAnim
                            transform: Translate { x: (1 - ccPanel.viewAnim) * ccPanel.viewDirection * 30 }

                            Text {
                                Layout.fillWidth: true
                                text: "Changes apply immediately and are stored in "
                                      + "~/.config/quickshell/monitors.json and "
                                      + "~/.config/hypr/quickshell-monitors.lua."
                                font.pixelSize: 11
                                color: dockPanel.textDim
                                wrapMode: Text.WordWrap
                            }

                            Text {
                                visible: dockPanel.monitorStatus !== ""
                                Layout.fillWidth: true
                                text: dockPanel.monitorStatus
                                font.pixelSize: 10
                                color: dockPanel.danger
                                wrapMode: Text.WordWrap
                            }

                            Repeater {
                                model: dockPanel.displayMonitors
                                delegate: Rectangle {
                                    id: monCard
                                    required property var modelData
                                    Layout.fillWidth: true
                                    Layout.preferredHeight: cardCol.implicitHeight + 20
                                    radius: dockPanel.buttonRadius - 4
                                    color: dockPanel.tileBg
                                    border.width: 1
                                    border.color: monCard.modelData.focused
                                        ? dockPanel.accent : dockPanel.tileBorder
                                    Behavior on border.color { ColorAnimation { duration: 200 } }

                                    ColumnLayout {
                                        id: cardCol
                                        anchors.fill: parent
                                        anchors.margins: 10
                                        spacing: 8

                                        RowLayout {
                                            Layout.fillWidth: true
                                            spacing: 8
                                            Text {
                                                text: monCard.modelData.name
                                                font.pixelSize: 12
                                                font.bold: true
                                                color: dockPanel.textMain
                                            }
                                            Text {
                                                Layout.fillWidth: true
                                                text: monCard.modelData.disabled
                                                    ? "disabled"
                                                    : monCard.modelData.width + "×" + monCard.modelData.height
                                                        + " @ " + monCard.modelData.refresh + " Hz · "
                                                        + Number(monCard.modelData.scale).toFixed(2) + "x"
                                                font.pixelSize: 10
                                                color: dockPanel.textDim
                                                elide: Text.ElideRight
                                            }
                                            Rectangle {
                                                Layout.preferredWidth: 66
                                                Layout.preferredHeight: 22
                                                radius: 11
                                                color: monPowerHover.containsMouse ? dockPanel.tileBgHover : "transparent"
                                                border.width: 1
                                                border.color: dockPanel.tileBorder
                                                Behavior on color { ColorAnimation { duration: 150 } }
                                                Text {
                                                    anchors.centerIn: parent
                                                    text: monCard.modelData.disabled ? "Enable" : "Disable"
                                                    font.pixelSize: 10
                                                    color: dockPanel.textMain
                                                }
                                                MouseArea {
                                                    id: monPowerHover
                                                    anchors.fill: parent
                                                    hoverEnabled: true
                                                    cursorShape: Qt.PointingHandCursor
                                                    onClicked: monCard.modelData.disabled
                                                        ? dockPanel.enableMonitor(monCard.modelData.name)
                                                        : dockPanel.disableMonitor(monCard.modelData.name)
                                                }
                                            }
                                        }

                                        // Resolution
                                        Text {
                                            visible: !monCard.modelData.disabled
                                            text: "Resolution"
                                            font.pixelSize: 10
                                            color: dockPanel.textDim
                                        }
                                        Flickable {
                                            visible: !monCard.modelData.disabled
                                            Layout.fillWidth: true
                                            Layout.preferredHeight: 26
                                            contentWidth: resChips.width
                                            clip: true
                                            boundsBehavior: Flickable.StopAtBounds
                                            Row {
                                                id: resChips
                                                spacing: 6
                                                Repeater {
                                                    model: monCard.modelData.resolutions
                                                    delegate: Rectangle {
                                                        required property var modelData
                                                        width: chipLabel.implicitWidth + 20
                                                        height: 26
                                                        radius: 13
                                                        color: modelData.active
                                                            ? dockPanel.accent
                                                            : (resChipHover.containsMouse
                                                                ? dockPanel.tileBgHover : "transparent")
                                                        border.width: 1
                                                        border.color: modelData.active
                                                            ? dockPanel.accent : dockPanel.tileBorder
                                                        Behavior on color { ColorAnimation { duration: 150 } }
                                                        Text {
                                                            id: chipLabel
                                                            anchors.centerIn: parent
                                                            text: modelData.label
                                                            font.pixelSize: 10
                                                            color: modelData.active ? "#ffffff" : dockPanel.textMain
                                                        }
                                                        MouseArea {
                                                            id: resChipHover
                                                            anchors.fill: parent
                                                            hoverEnabled: true
                                                            cursorShape: Qt.PointingHandCursor
                                                            onClicked: {
                                                                let r = 0;
                                                                for (const rt of modelData.rates)
                                                                    if (rt.active) r = rt.r;
                                                                if (!r && modelData.rates.length > 0)
                                                                    r = modelData.rates[0].r;
                                                                dockPanel.applyMonitor(monCard.modelData.name,
                                                                    modelData.w, modelData.h, r,
                                                                    monCard.modelData.scale);
                                                            }
                                                        }
                                                    }
                                                }
                                            }
                                        }

                                        // Refresh rate
                                        Text {
                                            visible: !monCard.modelData.disabled
                                            text: "Refresh rate"
                                            font.pixelSize: 10
                                            color: dockPanel.textDim
                                        }
                                        Row {
                                            visible: !monCard.modelData.disabled
                                            spacing: 6
                                            Repeater {
                                                model: dockPanel.activeRates(monCard.modelData)
                                                delegate: Rectangle {
                                                    required property var modelData
                                                    width: rateLabel.implicitWidth + 20
                                                    height: 26
                                                    radius: 13
                                                    color: modelData.active
                                                        ? dockPanel.accent
                                                        : (rateHover.containsMouse
                                                            ? dockPanel.tileBgHover : "transparent")
                                                    border.width: 1
                                                    border.color: modelData.active
                                                        ? dockPanel.accent : dockPanel.tileBorder
                                                    Behavior on color { ColorAnimation { duration: 150 } }
                                                    Text {
                                                        id: rateLabel
                                                        anchors.centerIn: parent
                                                        text: modelData.label
                                                        font.pixelSize: 10
                                                        color: modelData.active ? "#ffffff" : dockPanel.textMain
                                                    }
                                                    MouseArea {
                                                        id: rateHover
                                                        anchors.fill: parent
                                                        hoverEnabled: true
                                                        cursorShape: Qt.PointingHandCursor
                                                        onClicked: dockPanel.applyMonitor(
                                                            monCard.modelData.name,
                                                            monCard.modelData.width,
                                                            monCard.modelData.height,
                                                            modelData.r,
                                                            monCard.modelData.scale)
                                                    }
                                                }
                                            }
                                        }

                                        // Scale
                                        RowLayout {
                                            visible: !monCard.modelData.disabled
                                            Layout.fillWidth: true
                                            spacing: 8
                                            Text {
                                                text: "Scale"
                                                font.pixelSize: 10
                                                color: dockPanel.textDim
                                                Layout.preferredWidth: 44
                                            }
                                            Slider {
                                                id: scaleSlider
                                                Layout.fillWidth: true
                                                from: 0.5
                                                to: 3.0
                                                stepSize: 0.05
                                                value: monCard.modelData.scale
                                                onPressedChanged: if (!pressed)
                                                    dockPanel.setMonitorScale(monCard.modelData.name, value)
                                                background: Rectangle {
                                                    x: scaleSlider.leftPadding
                                                    y: scaleSlider.topPadding + scaleSlider.availableHeight / 2 - height / 2
                                                    implicitWidth: 200; implicitHeight: 6
                                                    width: scaleSlider.availableWidth
                                                    height: implicitHeight
                                                    radius: 3
                                                    color: "#30ffffff"
                                                    Rectangle {
                                                        width: scaleSlider.visualPosition * parent.width
                                                        height: parent.height
                                                        radius: 3
                                                        color: dockPanel.accent
                                                    }
                                                }
                                                handle: Rectangle {
                                                    x: scaleSlider.leftPadding + scaleSlider.visualPosition * (scaleSlider.availableWidth - width)
                                                    y: scaleSlider.topPadding + scaleSlider.availableHeight / 2 - height / 2
                                                    width: 16; height: 16; radius: 8
                                                    color: "#ffffff"
                                                    border.width: 2
                                                    border.color: dockPanel.accent
                                                    scale: scaleSlider.pressed ? 1.15 : 1.0
                                                    Behavior on scale { NumberAnimation { duration: 150 } }
                                                }
                                            }
                                            Text {
                                                text: Number(scaleSlider.value).toFixed(2) + "x"
                                                font.pixelSize: 10
                                                color: dockPanel.textDim
                                                Layout.preferredWidth: 40
                                            }
                                        }
                                    }
                                }
                            }

                            Text {
                                visible: dockPanel.displayMonitors.length === 0
                                Layout.fillWidth: true
                                text: "No monitors reported by hyprctl"
                                font.pixelSize: 11
                                color: dockPanel.textDim
                                horizontalAlignment: Text.AlignHCenter
                            }
                        }

                        // ============ INPUT VIEW ============
                        ColumnLayout {
                            visible: dockPanel.ccView === "input"
                            Layout.fillWidth: true
                            spacing: 10
                            opacity: ccPanel.viewAnim
                            transform: Translate { x: (1 - ccPanel.viewAnim) * ccPanel.viewDirection * 30 }

                            Text {
                                Layout.fillWidth: true
                                text: "Saved to ~/.config/hypr/quickshell-input.lua and applied live "
                                      + "through hyprctl where possible."
                                font.pixelSize: 11
                                color: dockPanel.textDim
                                wrapMode: Text.WordWrap
                            }

                            // Keyboard
                            Rectangle {
                                Layout.fillWidth: true
                                Layout.preferredHeight: kbCol.implicitHeight + 20
                                radius: dockPanel.buttonRadius - 4
                                color: dockPanel.tileBg
                                border.width: 1; border.color: dockPanel.tileBorder
                                ColumnLayout {
                                    id: kbCol
                                    anchors.fill: parent
                                    anchors.margins: 10
                                    spacing: 8
                                    RowLayout {
                                        Layout.fillWidth: true
                                        Text { text: "\uf11c"; font.pixelSize: 16; color: dockPanel.textMain }
                                        Text {
                                            text: "Keyboard"
                                            font.pixelSize: 12; font.bold: true
                                            color: dockPanel.textMain
                                        }
                                        Item { Layout.fillWidth: true }
                                    }
                                    GridLayout {
                                        Layout.fillWidth: true
                                        columns: 2
                                        columnSpacing: 8
                                        rowSpacing: 6

                                        Text { text: "Layout"; font.pixelSize: 10; color: dockPanel.textDim; Layout.preferredWidth: 56 }
                                        TextField {
                                            Layout.fillWidth: true
                                            text: dockPanel.inputCfg.kb_layout
                                            placeholderText: "us"
                                            color: dockPanel.textMain
                                            placeholderTextColor: dockPanel.textDim
                                            font.pixelSize: 11
                                            selectByMouse: true
                                            background: Rectangle {
                                                radius: dockPanel.searchRadius
                                                color: dockPanel.inputTop
                                                border.width: 1
                                                border.color: dockPanel.tileBorder
                                            }
                                            onEditingFinished: dockPanel.setInputValue("kb_layout", text)
                                        }

                                        Text { text: "Variant"; font.pixelSize: 10; color: dockPanel.textDim }
                                        TextField {
                                            Layout.fillWidth: true
                                            text: dockPanel.inputCfg.kb_variant
                                            placeholderText: ""
                                            color: dockPanel.textMain
                                            placeholderTextColor: dockPanel.textDim
                                            font.pixelSize: 11
                                            selectByMouse: true
                                            background: Rectangle {
                                                radius: dockPanel.searchRadius
                                                color: dockPanel.inputTop
                                                border.width: 1
                                                border.color: dockPanel.tileBorder
                                            }
                                            onEditingFinished: dockPanel.setInputValue("kb_variant", text)
                                        }

                                        Text { text: "Model"; font.pixelSize: 10; color: dockPanel.textDim }
                                        TextField {
                                            Layout.fillWidth: true
                                            text: dockPanel.inputCfg.kb_model
                                            color: dockPanel.textMain
                                            placeholderTextColor: dockPanel.textDim
                                            font.pixelSize: 11
                                            selectByMouse: true
                                            background: Rectangle {
                                                radius: dockPanel.searchRadius
                                                color: dockPanel.inputTop
                                                border.width: 1
                                                border.color: dockPanel.tileBorder
                                            }
                                            onEditingFinished: dockPanel.setInputValue("kb_model", text)
                                        }

                                        Text { text: "Options"; font.pixelSize: 10; color: dockPanel.textDim }
                                        TextField {
                                            Layout.fillWidth: true
                                            text: dockPanel.inputCfg.kb_options
                                            placeholderText: "grp:alt_shift_toggle"
                                            color: dockPanel.textMain
                                            placeholderTextColor: dockPanel.textDim
                                            font.pixelSize: 11
                                            selectByMouse: true
                                            background: Rectangle {
                                                radius: dockPanel.searchRadius
                                                color: dockPanel.inputTop
                                                border.width: 1
                                                border.color: dockPanel.tileBorder
                                            }
                                            onEditingFinished: dockPanel.setInputValue("kb_options", text)
                                        }

                                        Text { text: "Rules"; font.pixelSize: 10; color: dockPanel.textDim }
                                        TextField {
                                            Layout.fillWidth: true
                                            text: dockPanel.inputCfg.kb_rules
                                            color: dockPanel.textMain
                                            placeholderTextColor: dockPanel.textDim
                                            font.pixelSize: 11
                                            selectByMouse: true
                                            background: Rectangle {
                                                radius: dockPanel.searchRadius
                                                color: dockPanel.inputTop
                                                border.width: 1
                                                border.color: dockPanel.tileBorder
                                            }
                                            onEditingFinished: dockPanel.setInputValue("kb_rules", text)
                                        }
                                    }
                                }
                            }

                            // Mouse
                            Rectangle {
                                Layout.fillWidth: true
                                Layout.preferredHeight: mouseCol.implicitHeight + 20
                                radius: dockPanel.buttonRadius - 4
                                color: dockPanel.tileBg
                                border.width: 1; border.color: dockPanel.tileBorder
                                ColumnLayout {
                                    id: mouseCol
                                    anchors.fill: parent
                                    anchors.margins: 10
                                    spacing: 8
                                    RowLayout {
                                        Layout.fillWidth: true
                                        Text { text: "\uf245"; font.pixelSize: 16; color: dockPanel.textMain }
                                        Text {
                                            text: "Mouse & Touchpad"
                                            font.pixelSize: 12; font.bold: true
                                            color: dockPanel.textMain
                                        }
                                        Item { Layout.fillWidth: true }
                                    }

                                    RowLayout {
                                        Layout.fillWidth: true
                                        spacing: 8
                                        Text {
                                            text: "Follow mouse"
                                            font.pixelSize: 10
                                            color: dockPanel.textDim
                                            Layout.preferredWidth: 80
                                        }
                                        Row {
                                            spacing: 6
                                            Repeater {
                                                model: [0, 1, 2, 3]
                                                delegate: Rectangle {
                                                    required property var modelData
                                                    width: 34; height: 24; radius: 12
                                                    readonly property bool sel: Number(dockPanel.inputCfg.follow_mouse) === Number(modelData)
                                                    color: sel ? dockPanel.accent
                                                        : (fmHover.containsMouse ? dockPanel.tileBgHover : "transparent")
                                                    border.width: 1
                                                    border.color: sel ? dockPanel.accent : dockPanel.tileBorder
                                                    Behavior on color { ColorAnimation { duration: 140 } }
                                                    Text {
                                                        anchors.centerIn: parent
                                                        text: String(modelData)
                                                        font.pixelSize: 10
                                                        color: sel ? "#ffffff" : dockPanel.textMain
                                                    }
                                                    MouseArea {
                                                        id: fmHover
                                                        anchors.fill: parent
                                                        hoverEnabled: true
                                                        cursorShape: Qt.PointingHandCursor
                                                        onClicked: dockPanel.setInputValue("follow_mouse", modelData)
                                                    }
                                                }
                                            }
                                        }
                                        Item { Layout.fillWidth: true }
                                    }

                                    RowLayout {
                                        Layout.fillWidth: true
                                        spacing: 8
                                        Text {
                                            text: "Sensitivity"
                                            font.pixelSize: 10
                                            color: dockPanel.textDim
                                            Layout.preferredWidth: 80
                                        }
                                        Slider {
                                            id: sensSlider
                                            Layout.fillWidth: true
                                            from: -1.0
                                            to: 1.0
                                            stepSize: 0.05
                                            value: Number(dockPanel.inputCfg.sensitivity)
                                            onPressedChanged: if (!pressed)
                                                dockPanel.setInputValue("sensitivity", Math.round(value * 100) / 100)
                                            background: Rectangle {
                                                x: sensSlider.leftPadding
                                                y: sensSlider.topPadding + sensSlider.availableHeight / 2 - height / 2
                                                implicitWidth: 200; implicitHeight: 6
                                                width: sensSlider.availableWidth
                                                height: implicitHeight
                                                radius: 3
                                                color: "#30ffffff"
                                                Rectangle {
                                                    width: sensSlider.visualPosition * parent.width
                                                    height: parent.height
                                                    radius: 3
                                                    color: dockPanel.accent
                                                }
                                            }
                                            handle: Rectangle {
                                                x: sensSlider.leftPadding + sensSlider.visualPosition * (sensSlider.availableWidth - width)
                                                y: sensSlider.topPadding + sensSlider.availableHeight / 2 - height / 2
                                                width: 16; height: 16; radius: 8
                                                color: "#ffffff"
                                                border.width: 2
                                                border.color: dockPanel.accent
                                            }
                                        }
                                        Text {
                                            text: Number(sensSlider.value).toFixed(2)
                                            font.pixelSize: 10
                                            color: dockPanel.textDim
                                            Layout.preferredWidth: 36
                                        }
                                    }

                                    RowLayout {
                                        Layout.fillWidth: true
                                        spacing: 8
                                        Text {
                                            text: "Natural scroll"
                                            font.pixelSize: 10
                                            color: dockPanel.textDim
                                            Layout.preferredWidth: 80
                                        }
                                        Item { Layout.fillWidth: true }
                                        Rectangle {
                                            Layout.preferredWidth: 44
                                            Layout.preferredHeight: 24
                                            radius: 12
                                            color: dockPanel.inputCfg.natural_scroll ? dockPanel.accent : "#30ffffff"
                                            Behavior on color { ColorAnimation { duration: 220; easing.type: Easing.OutCubic } }
                                            Rectangle {
                                                x: dockPanel.inputCfg.natural_scroll ? parent.width - width - 2 : 2
                                                y: 2
                                                width: 20; height: 20; radius: 10
                                                color: "#ffffff"
                                                Behavior on x { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }
                                            }
                                            MouseArea {
                                                anchors.fill: parent
                                                cursorShape: Qt.PointingHandCursor
                                                onClicked: dockPanel.setInputValue("natural_scroll", !dockPanel.inputCfg.natural_scroll)
                                            }
                                        }
                                    }
                                }
                            }

                            // Gestures
                            Rectangle {
                                Layout.fillWidth: true
                                Layout.preferredHeight: gestCol.implicitHeight + 20
                                radius: dockPanel.buttonRadius - 4
                                color: dockPanel.tileBg
                                border.width: 1; border.color: dockPanel.tileBorder
                                ColumnLayout {
                                    id: gestCol
                                    anchors.fill: parent
                                    anchors.margins: 10
                                    spacing: 8
                                    RowLayout {
                                        Layout.fillWidth: true
                                        Text { text: "\uf1b0"; font.pixelSize: 16; color: dockPanel.textMain }
                                        Text {
                                            text: "Gestures"
                                            font.pixelSize: 12; font.bold: true
                                            color: dockPanel.textMain
                                        }
                                        Item { Layout.fillWidth: true }
                                    }

                                    RowLayout {
                                        Layout.fillWidth: true
                                        spacing: 8
                                        Text {
                                            text: "Fingers"
                                            font.pixelSize: 10
                                            color: dockPanel.textDim
                                            Layout.preferredWidth: 80
                                        }
                                        Row {
                                            spacing: 6
                                            Repeater {
                                                model: [3, 4]
                                                delegate: Rectangle {
                                                    required property var modelData
                                                    width: 34; height: 24; radius: 12
                                                    readonly property bool sel: Number(dockPanel.inputCfg.gesture_fingers) === Number(modelData)
                                                    color: sel ? dockPanel.accent
                                                        : (gfHover.containsMouse ? dockPanel.tileBgHover : "transparent")
                                                    border.width: 1
                                                    border.color: sel ? dockPanel.accent : dockPanel.tileBorder
                                                    Behavior on color { ColorAnimation { duration: 140 } }
                                                    Text {
                                                        anchors.centerIn: parent
                                                        text: String(modelData)
                                                        font.pixelSize: 10
                                                        color: sel ? "#ffffff" : dockPanel.textMain
                                                    }
                                                    MouseArea {
                                                        id: gfHover
                                                        anchors.fill: parent
                                                        hoverEnabled: true
                                                        cursorShape: Qt.PointingHandCursor
                                                        onClicked: dockPanel.setInputValue("gesture_fingers", modelData)
                                                    }
                                                }
                                            }
                                        }
                                        Item { Layout.fillWidth: true }
                                    }

                                    RowLayout {
                                        Layout.fillWidth: true
                                        spacing: 8
                                        Text {
                                            text: "Direction"
                                            font.pixelSize: 10
                                            color: dockPanel.textDim
                                            Layout.preferredWidth: 80
                                        }
                                        Row {
                                            spacing: 6
                                            Repeater {
                                                model: ["horizontal", "vertical"]
                                                delegate: Rectangle {
                                                    required property var modelData
                                                    width: gdLabel.implicitWidth + 20
                                                    height: 24; radius: 12
                                                    readonly property bool sel: String(dockPanel.inputCfg.gesture_direction) === String(modelData)
                                                    color: sel ? dockPanel.accent
                                                        : (gdHover.containsMouse ? dockPanel.tileBgHover : "transparent")
                                                    border.width: 1
                                                    border.color: sel ? dockPanel.accent : dockPanel.tileBorder
                                                    Behavior on color { ColorAnimation { duration: 140 } }
                                                    Text {
                                                        id: gdLabel
                                                        anchors.centerIn: parent
                                                        text: String(modelData)
                                                        font.pixelSize: 10
                                                        color: sel ? "#ffffff" : dockPanel.textMain
                                                    }
                                                    MouseArea {
                                                        id: gdHover
                                                        anchors.fill: parent
                                                        hoverEnabled: true
                                                        cursorShape: Qt.PointingHandCursor
                                                        onClicked: dockPanel.setInputValue("gesture_direction", modelData)
                                                    }
                                                }
                                            }
                                        }
                                        Item { Layout.fillWidth: true }
                                    }

                                    RowLayout {
                                        Layout.fillWidth: true
                                        spacing: 8
                                        Text {
                                            text: "Action"
                                            font.pixelSize: 10
                                            color: dockPanel.textDim
                                            Layout.preferredWidth: 80
                                        }
                                        Row {
                                            spacing: 6
                                            Repeater {
                                                model: ["workspace", "fullscreen", "special", "float"]
                                                delegate: Rectangle {
                                                    required property var modelData
                                                    width: gaLabel.implicitWidth + 20
                                                    height: 24; radius: 12
                                                    readonly property bool sel: String(dockPanel.inputCfg.gesture_action) === String(modelData)
                                                    color: sel ? dockPanel.accent
                                                        : (gaHover.containsMouse ? dockPanel.tileBgHover : "transparent")
                                                    border.width: 1
                                                    border.color: sel ? dockPanel.accent : dockPanel.tileBorder
                                                    Behavior on color { ColorAnimation { duration: 140 } }
                                                    Text {
                                                        id: gaLabel
                                                        anchors.centerIn: parent
                                                        text: String(modelData)
                                                        font.pixelSize: 10
                                                        color: sel ? "#ffffff" : dockPanel.textMain
                                                    }
                                                    MouseArea {
                                                        id: gaHover
                                                        anchors.fill: parent
                                                        hoverEnabled: true
                                                        cursorShape: Qt.PointingHandCursor
                                                        onClicked: dockPanel.setInputValue("gesture_action", modelData)
                                                    }
                                                }
                                            }
                                        }
                                        Item { Layout.fillWidth: true }
                                    }
                                }
                            }

                            // Per-device
                            Rectangle {
                                Layout.fillWidth: true
                                Layout.preferredHeight: devCol.implicitHeight + 20
                                radius: dockPanel.buttonRadius - 4
                                color: dockPanel.tileBg
                                border.width: 1; border.color: dockPanel.tileBorder
                                ColumnLayout {
                                    id: devCol
                                    anchors.fill: parent
                                    anchors.margins: 10
                                    spacing: 8
                                    RowLayout {
                                        Layout.fillWidth: true
                                        Text { text: "\uf2db"; font.pixelSize: 16; color: dockPanel.textMain }
                                        Text {
                                            text: "Per-device"
                                            font.pixelSize: 12; font.bold: true
                                            color: dockPanel.textMain
                                        }
                                        Item { Layout.fillWidth: true }
                                    }
                                    GridLayout {
                                        Layout.fillWidth: true
                                        columns: 2
                                        columnSpacing: 8
                                        rowSpacing: 6
                                        Text { text: "Name"; font.pixelSize: 10; color: dockPanel.textDim; Layout.preferredWidth: 56 }
                                        TextField {
                                            Layout.fillWidth: true
                                            text: dockPanel.inputCfg.device_name
                                            placeholderText: "epic-mouse-v1"
                                            color: dockPanel.textMain
                                            placeholderTextColor: dockPanel.textDim
                                            font.pixelSize: 11
                                            selectByMouse: true
                                            background: Rectangle {
                                                radius: dockPanel.searchRadius
                                                color: dockPanel.inputTop
                                                border.width: 1
                                                border.color: dockPanel.tileBorder
                                            }
                                            onEditingFinished: dockPanel.setInputValue("device_name", text)
                                        }
                                        Text { text: "Sens."; font.pixelSize: 10; color: dockPanel.textDim }
                                        TextField {
                                            Layout.fillWidth: true
                                            text: dockPanel.inputCfg.device_sensitivity
                                            placeholderText: "-0.5"
                                            color: dockPanel.textMain
                                            placeholderTextColor: dockPanel.textDim
                                            font.pixelSize: 11
                                            selectByMouse: true
                                            background: Rectangle {
                                                radius: dockPanel.searchRadius
                                                color: dockPanel.inputTop
                                                border.width: 1
                                                border.color: dockPanel.tileBorder
                                            }
                                            onEditingFinished: dockPanel.setInputValue("device_sensitivity", text)
                                        }
                                    }
                                }
                            }

                            Text {
                                Layout.fillWidth: true
                                text: "Written to ~/.config/hypr/quickshell-input.lua and sourced from hyprland.lua."
                                font.pixelSize: 10
                                color: dockPanel.textDim
                                wrapMode: Text.WordWrap
                            }
                        }

                        // ============ ICON THEME VIEW ============
                        ColumnLayout {
                            visible: dockPanel.ccView === "icons"
                            Layout.fillWidth: true
                            spacing: 10
                            opacity: ccPanel.viewAnim
                            transform: Translate { x: (1 - ccPanel.viewAnim) * ccPanel.viewDirection * 30 }

                            Text {
                                Layout.fillWidth: true
                                text: "Icons are read straight from the pack you pick — the dock and the "
                                      + "app launcher update instantly, no restart."
                                font.pixelSize: 11
                                color: dockPanel.textDim
                                wrapMode: Text.WordWrap
                            }

                            Text {
                                Layout.fillWidth: true
                                visible: dockPanel.iconCount > 0
                                text: dockPanel.iconCount + " icons indexed from "
                                      + (dockPanel.iconTheme || "the system theme")
                                font.pixelSize: 10
                                color: dockPanel.textDim
                            }

                            Text {
                                visible: dockPanel.availableIconThemes.length === 0
                                Layout.fillWidth: true
                                text: "No icon themes found in ~/.local/share/icons or /usr/share/icons"
                                font.pixelSize: 11
                                color: dockPanel.textDim
                                horizontalAlignment: Text.AlignHCenter
                            }

                            Repeater {
                                model: dockPanel.availableIconThemes
                                delegate: Rectangle {
                                    required property var modelData
                                    Layout.fillWidth: true
                                    Layout.preferredHeight: 44
                                    radius: dockPanel.buttonRadius - 8
                                    color: (String(dockPanel.iconTheme).toLowerCase() === String(modelData.id).toLowerCase())
                                        ? dockPanel.accent
                                        : (themeHover.containsMouse ? dockPanel.tileBgHover : dockPanel.tileBg)
                                    border.width: 1
                                    border.color: (String(dockPanel.iconTheme).toLowerCase() === String(modelData.id).toLowerCase())
                                        ? dockPanel.accent : dockPanel.tileBorder
                                    Behavior on color { ColorAnimation { duration: 160; easing.type: Easing.OutCubic } }
                                    RowLayout {
                                        anchors.centerIn: parent
                                        spacing: 10
                                        Rectangle {
                                            Layout.alignment: Qt.AlignVCenter
                                            Layout.preferredWidth: 20
                                            Layout.preferredHeight: 20
                                            radius: 10
                                            color: (String(dockPanel.iconTheme).toLowerCase() === String(modelData.id).toLowerCase())
                                                ? "#ffffff" : "transparent"
                                            border.width: 2
                                            border.color: (String(dockPanel.iconTheme).toLowerCase() === String(modelData.id).toLowerCase())
                                                ? "#ffffff" : dockPanel.textDim
                                            Rectangle {
                                                anchors.centerIn: parent
                                                width: 8; height: 8; radius: 4
                                                color: dockPanel.accent
                                                visible: (String(dockPanel.iconTheme).toLowerCase() === String(modelData.id).toLowerCase())
                                            }
                                        }
                                        ColumnLayout {
                                            Layout.alignment: Qt.AlignVCenter
                                            spacing: 2
                                            Text {
                                                text: modelData.name
                                                font.pixelSize: 12
                                                color: (String(dockPanel.iconTheme).toLowerCase() === String(modelData.id).toLowerCase())
                                                    ? "#ffffff" : dockPanel.textMain
                                                horizontalAlignment: Text.AlignHCenter
                                                elide: Text.ElideRight
                                                Layout.maximumWidth: 260
                                            }
                                            Text {
                                                text: modelData.id
                                                font.pixelSize: 10
                                                color: (String(dockPanel.iconTheme).toLowerCase() === String(modelData.id).toLowerCase())
                                                    ? "#ddffffff" : dockPanel.textDim
                                                horizontalAlignment: Text.AlignHCenter
                                                elide: Text.ElideRight
                                                Layout.maximumWidth: 260
                                            }
                                        }
                                    }
                                    MouseArea {
                                        id: themeHover
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: dockPanel.setIconTheme(modelData.id)
                                    }
                                }
                            }
                        }
                    }
                }

                // WiFi password modal
                Rectangle {
                    anchors.fill: parent
                    anchors.margins: 24
                    radius: dockPanel.panelRadius
                    color: dockPanel.darkMode ? "#ee000000" : "#eeffffff"
                    border.width: 1
                    border.color: dockPanel.tileBorder
                    visible: dockPanel.wifiPasswordTarget !== ""
                    z: 200
                    opacity: visible ? 1 : 0
                    Behavior on opacity { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }
                    ColumnLayout {
                        anchors.centerIn: parent
                        width: parent.width - 60
                        spacing: 14
                        Text {
                            Layout.fillWidth: true
                            text: "Connect to " + dockPanel.wifiPasswordTarget
                            font.pixelSize: 14; font.bold: true
                            color: dockPanel.textMain
                            horizontalAlignment: Text.AlignHCenter
                        }
                        TextField {
                            Layout.fillWidth: true
                            placeholderText: "Password"
                            placeholderTextColor: dockPanel.textDim
                            echoMode: TextInput.Password
                            color: dockPanel.textMain
                            font.pixelSize: 13
                            selectByMouse: true
                            text: dockPanel.wifiPasswordPrompt
                            onTextChanged: dockPanel.wifiPasswordPrompt = text
                            background: Rectangle {
                                radius: dockPanel.searchRadius
                                color: dockPanel.tileBg
                                border.width: 1
                                border.color: dockPanel.tileBorder
                            }
                            Keys.onReturnPressed: dockPanel.submitWifiPassword()
                            Keys.onEnterPressed: dockPanel.submitWifiPassword()
                            Keys.onPressed: (event) => {
                                if (event.key === Qt.Key_Escape) {
                                    dockPanel.wifiPasswordTarget = "";
                                    dockPanel.wifiPasswordPrompt = "";
                                    event.accepted = true;
                                }
                            }
                            onVisibleChanged: if (visible) forceActiveFocus()
                        }
                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 10
                            Rectangle {
                                Layout.fillWidth: true
                                Layout.preferredHeight: 36
                                radius: 18
                                color: cancelHover.containsMouse ? dockPanel.tileBgHover : dockPanel.tileBg
                                Behavior on color { ColorAnimation { duration: 150 } }
                                Text {
                                    anchors.centerIn: parent
                                    text: "Cancel"
                                    font.pixelSize: 12
                                    color: dockPanel.textMain
                                }
                                MouseArea {
                                    id: cancelHover
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: {
                                        dockPanel.wifiPasswordTarget = "";
                                        dockPanel.wifiPasswordPrompt = "";
                                    }
                                }
                            }
                            Rectangle {
                                Layout.fillWidth: true
                                Layout.preferredHeight: 36
                                radius: 18
                                color: connectHover.containsMouse
                                    ? Qt.lighter(dockPanel.accent, 1.1)
                                    : dockPanel.accent
                                Behavior on color { ColorAnimation { duration: 150 } }
                                Text {
                                    anchors.centerIn: parent
                                    text: "Connect"
                                    font.pixelSize: 12; font.bold: true
                                    color: "#ffffff"
                                }
                                MouseArea {
                                    id: connectHover
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: dockPanel.submitWifiPassword()
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    // ================= Clock =================
    Rectangle {
        id: clockRect
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.rightMargin: 16
        anchors.bottomMargin: 8
        height: 64
        width: clockColumn.implicitWidth + 40
        radius: dockPanel.buttonRadius
        color: dockPanel.glass
        border.width: 1
        border.color: dockPanel.tileBorder
        ColumnLayout {
            id: clockColumn
            anchors.centerIn: parent
            spacing: 2
            Text {
                Layout.alignment: Qt.AlignHCenter
                text: Qt.formatTime(dockPanel.now, "HH:mm")
                color: dockPanel.textMain
                font.pixelSize: 22
                font.weight: Font.DemiBold
            }
            Text {
                Layout.alignment: Qt.AlignHCenter
                text: Qt.formatDate(dockPanel.now, "ddd, MMM d")
                color: dockPanel.textDim
                font.pixelSize: 11
            }
        }
    }
}
