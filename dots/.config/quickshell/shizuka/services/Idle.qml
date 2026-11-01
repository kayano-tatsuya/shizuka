pragma Singleton
import qs.modules.common
import QtQuick
import Quickshell
import Quickshell.Io

/**
 * Wrapper for the "keep system awake" toggle.
 *
 * Hyprland 0.57.0 does not register Quickshell's Wayland idle-inhibitor
 * surface (inhibitingIdle stays 0), so the protocol-based approach silently
 * does nothing. Instead toggle hypridle itself: when keeping awake, kill
 * hypridle (no idle timeouts fire); when releasing, restart it.
 */
Singleton {
    id: root

    property bool inhibit: false

    Connections {
        target: Persistent
        function onReadyChanged() {
            if (!Persistent.isNewHyprlandInstance) {
                root.inhibit = Persistent.states.idle.inhibit;
            } else {
                Persistent.states.idle.inhibit = root.inhibit;
            }
            root.applyInhibit();
        }
    }

    function toggleInhibit(active = null) {
        if (active !== null) {
            root.inhibit = active;
        } else {
            root.inhibit = !root.inhibit;
        }
        Persistent.states.idle.inhibit = root.inhibit;
        root.applyInhibit();
    }

    function applyInhibit() {
        if (root.inhibit) {
            killProc.running = true;
        } else {
            startProc.running = true;
        }
    }

    // Apply persisted state. Persistent may already be ready when this
    // singleton is first instantiated, so handle both cases.
    function applyPersisted() {
        if (Persistent.ready) {
            root.inhibit = Persistent.states.idle.inhibit;
            root.applyInhibit();
        }
    }
    Component.onCompleted: {
        root.applyPersisted();
    }
    Connections {
        target: Persistent
        function onReadyChanged() {
            if (Persistent.ready) {
                root.inhibit = Persistent.states.idle.inhibit;
                root.applyInhibit();
            }
        }
    }

    // Give hypridle time to start (execs.lua) before killing it.
    Timer {
        interval: 3000
        running: true
        repeat: false
        onTriggered: {
            if (root.inhibit) root.applyInhibit();
        }
    }

    Process {
        id: killProc
        command: ["pkill", "hypridle"]
    }

    Process {
        id: startProc
        command: ["bash", "-c", "pgrep -x hypridle >/dev/null || (hypridle & disown)"]
    }
}
