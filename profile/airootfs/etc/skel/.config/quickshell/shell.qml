//@ pragma UseQApplication
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.Pipewire
import "." as Cyber
import "bar" as Bar
import "power" as Power
import "launcher" as Launcher
import "osd" as Osd

ShellRoot {
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
    LazyLoader { id: osd; Osd.Osd {} }

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
