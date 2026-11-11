//@ pragma UseQApplication
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.Pipewire
import Quickshell.Services.Notifications
import "." as Cyber
import "bar" as Bar
import "power" as Power
import "launcher" as Launcher
import "osd" as Osd
import "notify" as Notify
import "popups" as Popups
import "apps" as Apps

ShellRoot {
    id: shell

    // Do-not-disturb: flipped by `qs ipc call notify dnd` and by clicking
    // bar/NotifyChip.qml. Named distinctly from the IpcHandler's `dnd()`
    // function below on purpose -- that function and this property would
    // otherwise share the identifier "dnd" on two different QML objects
    // (ShellRoot vs. the nested IpcHandler), and a bare `dnd` reference
    // written *inside* the function would resolve to the function itself
    // (the nearest scope), not this property. Qualifying every write/read
    // as `shell.dnd` sidesteps that ambiguity entirely.
    property bool dnd: false

    Variants {
        model: Quickshell.screens
        delegate: Bar.Bar { required property var modelData; screen: modelData }
    }

    Cyber.DesktopClock {}

    // Popup surfaces land here (launcher in a later task). LazyLoader keeps
    // startup cheap and a broken popup from taking the bar down.
    //
    // bar/Bar.qml (the power chip), bar/Battery.qml, and the apps chip all
    // reference `powerMenu`/`launcher` by bare id despite living in
    // bar/*.qml, not this file -- that resolves (verified at runtime, see
    // final-fix-report.md) because Bar.Bar is instantiated as a child of
    // this ShellRoot via the Variants delegate above, which puts every Bar
    // instance in the same QML object scope as these ids. Not a bug to fix.
    LazyLoader {
        id: powerMenu
        Power.PowerMenu { onCloseRequested: powerMenu.active = false }
    }
    LazyLoader {
        id: launcher
        Launcher.Launcher { onCloseRequested: launcher.active = false }
    }
    LazyLoader {
        id: winswitch
        Popups.WinSwitch { onCloseRequested: winswitch.active = false }
    }
    LazyLoader {
        id: emoji
        Popups.EmojiPicker { onCloseRequested: emoji.active = false }
    }
    LazyLoader {
        id: calc
        Popups.Calc { onCloseRequested: calc.active = false }
    }
    LazyLoader {
        id: clip
        Popups.ClipHist { onCloseRequested: clip.active = false }
    }
    LazyLoader {
        id: wifi
        Popups.WifiPanel { onCloseRequested: wifi.active = false }
    }
    LazyLoader {
        id: bt
        Popups.BluetoothPanel { onCloseRequested: bt.active = false }
    }
    LazyLoader {
        id: mixer
        Popups.Mixer { onCloseRequested: mixer.active = false }
    }
    LazyLoader {
        id: powerprofile
        Popups.PowerPanel { onCloseRequested: powerprofile.active = false }
    }
    LazyLoader {
        id: images
        Apps.Images {}
    }
    LazyLoader {
        id: files
        Apps.Files {}
    }
    LazyLoader { id: osd; Osd.Osd {} }

    // Replaces mako. actionsSupported/imageSupported/bodySupported tell the
    // sending client (via GetCapabilities) that this server can render
    // those fields -- without them some apps degrade their notifications
    // (e.g. drop the body). keepOnReload survives a qs config reload
    // (Super+Shift+R) without dropping notifications live on screen.
    //
    // Tracking idiom (verified against quickshell-service-notifications.
    // qmltypes): NotificationServerQml does NOT auto-track anything --
    // `trackedNotifications` only ever contains notifications whose own
    // `tracked` property (read isTracked/write setTracked, both present in
    // the qmltypes) has been explicitly set true. The `notification` signal
    // hands over the freshly-arrived Notification; setting `.tracked = true`
    // on it in the handler is the only thing that makes it show up in
    // `trackedNotifications.values` for NotifyPopups.qml to render.
    NotificationServer {
        id: notifServer
        keepOnReload: true
        actionsSupported: true
        imageSupported: true
        bodySupported: true
        onNotification: notification => notification.tracked = true
    }

    // Always active (not toggled like the popups above): notifications can
    // arrive at any time, so the panel must be ready from login -- it stays
    // invisible on its own (NotifyPopups.qml's `visible` binding) whenever
    // there is nothing tracked or DND is on, so there is no idle-surface
    // cost to keeping it loaded.
    LazyLoader {
        id: notifyPopups
        active: true
        Notify.NotifyPopups { server: notifServer; dnd: shell.dnd }
    }

    // Always active, not toggled like the popups above: bar/SystemHealthChip.qml
    // needs a live overallStatus to colour itself even while the panel is
    // closed, the same reason notifyPopups above is always active. The panel
    // window itself is invisible until opened (SystemHealth.qml's own
    // `visible: root.opened`), so there is no idle on-screen cost.
    LazyLoader {
        id: systemhealth
        active: true
        Popups.SystemHealth {}
    }

    // Always active for the same reason as systemhealth above:
    // bar/MusicFlowChip.qml reads `player` from here to colour/label itself
    // even while the panel is closed, and both need to agree on which MPRIS
    // player is "active" when more than one is running.
    LazyLoader {
        id: musicflow
        active: true
        Popups.MusicFlow {}
    }

    // Always active for the same reason as systemhealth/musicflow above:
    // bar/MonitorChip.qml needs a live "any external display connected"
    // count to colour itself even while the panel is closed.
    LazyLoader {
        id: monitorArrange
        active: true
        Popups.MonitorArrange {}
    }

    // Always active for the same reason as monitorArrange/systemhealth
    // above: bar/CloudDrivesChip.qml needs a live "any drive mounted"
    // count to colour itself even while the panel is closed.
    LazyLoader {
        id: cloudDrives
        active: true
        Popups.CloudDrives {}
    }

    // `qs ipc call notify dnd` -- replaces mako's own notification pipeline;
    // toggles do-not-disturb (see bar/NotifyChip.qml for the bar-side toggle).
    IpcHandler {
        target: "notify"
        function dnd(): void { shell.dnd = !shell.dnd; }
    }

    // `qs ipc call power toggle` opens the menu if closed, closes it if open.
    IpcHandler {
        target: "power"
        function toggle(): void {
            powerMenu.activeAsync ? powerMenu.active = false : powerMenu.activeAsync = true
        }
    }

    // `qs ipc call launcher toggle` -- replaces `rofi -show drun`.
    IpcHandler {
        target: "launcher"
        function toggle(): void {
            launcher.activeAsync ? launcher.active = false : launcher.activeAsync = true
        }
    }

    // `qs ipc call winswitch toggle` -- replaces `rofi -show window`.
    IpcHandler {
        target: "winswitch"
        function toggle(): void {
            winswitch.activeAsync ? winswitch.active = false : winswitch.activeAsync = true
        }
    }

    // `qs ipc call emoji toggle` -- replaces `rofi -show emoji`.
    IpcHandler {
        target: "emoji"
        function toggle(): void {
            emoji.activeAsync ? emoji.active = false : emoji.activeAsync = true
        }
    }

    // `qs ipc call calc toggle` -- replaces `rofi -show calc`.
    IpcHandler {
        target: "calc"
        function toggle(): void {
            calc.activeAsync ? calc.active = false : calc.activeAsync = true
        }
    }

    // `qs ipc call clip toggle` -- replaces the cliphist|rofi|cliphist|wl-copy pipe.
    IpcHandler {
        target: "clip"
        function toggle(): void {
            clip.activeAsync ? clip.active = false : clip.activeAsync = true
        }
    }

    // `qs ipc call wifi toggle` -- replaces nm-applet/nm-connection-editor.
    IpcHandler {
        target: "wifi"
        function toggle(): void {
            wifi.activeAsync ? wifi.active = false : wifi.activeAsync = true
        }
    }

    // `qs ipc call bt toggle` -- replaces blueman-manager/blueman-applet.
    IpcHandler {
        target: "bt"
        function toggle(): void {
            bt.activeAsync ? bt.active = false : bt.activeAsync = true
        }
    }

    // `qs ipc call mixer toggle` -- replaces pavucontrol-qt.
    IpcHandler {
        target: "mixer"
        function toggle(): void {
            mixer.activeAsync ? mixer.active = false : mixer.activeAsync = true
        }
    }

    // `qs ipc call powerprofile toggle` -- the battery chip's panel: live
    // charge/discharge in watts plus the power-profiles-daemon mode. The
    // sleep/lock/restart/shutdown menu stays on the bar's own power button.
    IpcHandler {
        target: "powerprofile"
        function toggle(): void {
            powerprofile.activeAsync ? powerprofile.active = false : powerprofile.activeAsync = true
        }
    }

    // `qs ipc call images open <path>` -- cyberos-images.desktop execs this,
    // so every mime-opened picture arrives here. Reuses one window: a second
    // open retargets the existing viewer rather than stacking windows.
    // `active`, NOT `activeAsync`: async loading returns before the component
    // exists, so `item` would still be null on the first open and the path
    // would never be applied. The toggle popups can use activeAsync because
    // they carry no argument; an open-with-path handler cannot.
    IpcHandler {
        target: "images"
        function open(path: string): void {
            images.active = true;
            if (images.item) {
                images.item.path = path;
                images.item.visible = true;
            }
        }
    }

    // `qs ipc call files open <path>` -- Super+E and cyberos-files.desktop
    // both land here. An empty path means "open at $HOME", which is the
    // component's own default, so it is left alone in that case.
    // `active`, not `activeAsync` -- see the images handler above: the item
    // must exist by the time we assign to it.
    IpcHandler {
        target: "files"
        function open(path: string): void {
            files.active = true;
            if (files.item) {
                if (path !== "") files.item.path = path;
                files.item.visible = true;
            }
        }
    }

    // `qs ipc call systemhealth toggle` -- bar/SystemHealthChip.qml's own
    // click handler. `systemhealth` is always `active` (see the LazyLoader
    // above), so `.item` exists from startup; unlike images/files above
    // there is no path argument to apply, so plain function calls on the
    // item are enough.
    IpcHandler {
        target: "systemhealth"
        function open(): void { systemhealth.item?.open(); }
        function close(): void { systemhealth.item?.close(); }
        function toggle(): void { systemhealth.item?.toggle(); }
    }

    // `qs ipc call musicflow toggle` -- bar/MusicFlowChip.qml's own click
    // handler, same shape as systemhealth above.
    IpcHandler {
        target: "musicflow"
        function open(): void { musicflow.item?.open(); }
        function close(): void { musicflow.item?.close(); }
        function toggle(): void { musicflow.item?.toggle(); }
    }

    // `qs ipc call monitorarrange toggle` -- bar/MonitorChip.qml's own click
    // handler, same shape as musicflow/systemhealth above.
    IpcHandler {
        target: "monitorarrange"
        function open(): void { monitorArrange.item?.open(); }
        function close(): void { monitorArrange.item?.close(); }
        function toggle(): void { monitorArrange.item?.toggle(); }
    }

    // `qs ipc call clouddrives toggle` -- bar/CloudDrivesChip.qml's own
    // click handler, same shape as monitorarrange/musicflow above.
    IpcHandler {
        target: "clouddrives"
        function open(): void { cloudDrives.item?.open(); }
        function close(): void { cloudDrives.item?.close(); }
        function toggle(): void { cloudDrives.item?.toggle(); }
    }

    // Keeps Pipewire's default-sink properties valid/subscribed for the OSD
    // ipc handlers below, independent of whether the bar's own Audio chip
    // (bar/Audio.qml) happens to be alive -- mirrors its PwObjectTracker use.
    PwObjectTracker { objects: [Pipewire.defaultAudioSink] }

    // brightnessctl has no QML binding, so after a `set` we shell back out
    // to read the level it actually landed on (CSV, field 4 -- see
    // SysStats.qml for the same Process/StdioCollector shape).
    Process {
        id: brightnessRead
        command: ["brightnessctl", "-m"]
        stdout: StdioCollector {
            onStreamFinished: {
                const fields = text.trim().split(",");
                const pct = parseInt(fields[3]);
                if (!isNaN(pct)) Cyber.OsdState.level = pct / 100;
                Cyber.OsdState.icon = "\udb80\udcdf"; // md-brightness_6
                Cyber.OsdState.seq++;
                osd.activeAsync = true;
            }
        }
    }

    // Shared by volumeUp/volumeDown/volumeMute: read the sink back after the
    // change so the OSD always shows the volume it actually ended up at
    // (also picks up the muted state for the icon).
    function showVolume() {
        const sink = Pipewire.defaultAudioSink;
        const vol = sink?.audio.volume ?? 0;
        const muted = sink?.audio.muted ?? false;
        Cyber.OsdState.level = vol;
        // volume-xmark (muted) / volume-up / volume-low / volume-off -- same
        // glyphs and thresholds as bar/Audio.qml, font-cmap-verified there.
        Cyber.OsdState.icon = muted ? "\ueee8" : vol > 0.66 ? "\uf028" : vol > 0.33 ? "\uf027" : "\uf026";
        Cyber.OsdState.seq++;
        osd.activeAsync = true;
    }

    // `qs ipc call osd <fn>` -- replaces the five swayosd-client binds.
    IpcHandler {
        target: "osd"

        function volumeUp(): void {
            const sink = Pipewire.defaultAudioSink;
            if (sink) sink.audio.volume = Math.min(1, sink.audio.volume + 0.05);
            showVolume();
        }
        function volumeDown(): void {
            const sink = Pipewire.defaultAudioSink;
            if (sink) sink.audio.volume = Math.max(0, sink.audio.volume - 0.05);
            showVolume();
        }
        function volumeMute(): void {
            const sink = Pipewire.defaultAudioSink;
            if (sink) sink.audio.muted = !sink.audio.muted;
            showVolume();
        }
        function brightnessUp(): void {
            Quickshell.execDetached(["brightnessctl", "-e4", "-n2", "set", "5%+"]);
            brightnessRead.running = true;
        }
        function brightnessDown(): void {
            Quickshell.execDetached(["brightnessctl", "-e4", "-n2", "set", "5%-"]);
            brightnessRead.running = true;
        }
    }
}
