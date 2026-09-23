pragma Singleton

import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import QtQuick 6.10

Singleton {
    id: root

    readonly property var toplevels: Hyprland.toplevels
    readonly property var workspaces: Hyprland.workspaces
    readonly property var monitors: Hyprland.monitors

    readonly property var activeToplevel: Hyprland.activeToplevel
    readonly property var focusedWorkspace: Hyprland.focusedWorkspace
    readonly property var focusedMonitor: Hyprland.focusedMonitor

    property int niriActiveWsId: 1
    readonly property int activeWsId: isNiri ? niriActiveWsId : (focusedWorkspace?.id ?? 1)
    property bool isNiri: false

    Component.onCompleted: {
        checkNiriProc.exec(["sh", "-c", "if [ -n \"$NIRI_SOCKET\" ] || pgrep -x niri >/dev/null; then echo \"niri\"; else echo \"hyprland\"; fi"])
    }

    Process {
        id: checkNiriProc
        stdout: StdioCollector {
            onStreamFinished: {
                root.isNiri = text.trim() === "niri"
                if (root.isNiri) {
                    getNiriWsProc.running = true
                }
            }
        }
    }

    Process {
        id: getNiriWsProc
        command: ["niri", "msg", "-j", "workspaces"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const wsList = JSON.parse(text.trim())
                    const activeWs = wsList.find(w => w.is_active || w.is_focused)
                    if (activeWs) {
                        root.niriActiveWsId = activeWs.idx ?? activeWs.id ?? 1
                    }
                } catch (e) {
                }
            }
        }
    }

    function dispatch(request: string): void {
        if (isNiri) {
            const wsMatch = request.match(/^workspace\s+(\d+)/)
            if (wsMatch) {
                const targetIdx = parseInt(wsMatch[1])
                dispatchNiriWsProc.exec(["niri", "msg", "action", "focus-workspace", targetIdx.toString()])
                root.niriActiveWsId = targetIdx
                return
            }
        }
        Hyprland.dispatch(request);
    }

    Process { id: dispatchNiriWsProc }

    function monitorFor(screen: var): var {
        return Hyprland.monitorFor(screen);
    }

    // Get occupied workspaces (workspaces with windows)
    function getOccupiedWorkspaces(): var {
        const occupied = {};
        for (const ws of workspaces.values) {
            occupied[ws.id] = (ws.lastIpcObject?.windows ?? 0) > 0;
        }
        return occupied;
    }

    // Refresh timer to ensure updates when events are missed
    Timer {
        interval: 5000
        running: true
        repeat: true
        onTriggered: {
            if (root.isNiri) {
                if (!getNiriWsProc.running) getNiriWsProc.running = true
            } else {
                Hyprland.refreshWorkspaces();
            }
        }
    }

    Connections {
        target: Hyprland

        function onRawEvent(event: var): void {
            if (root.isNiri) return;

            const n = event.name;
            if (n.endsWith("v2"))
                return;

            // More aggressive refresh for workspace changes
            if (["workspace", "moveworkspace", "activespecial", "focusedmon", "activewindow"].includes(n)) {
                Hyprland.refreshWorkspaces();
                Hyprland.refreshMonitors();
            } else if (["openwindow", "closewindow", "movewindow"].includes(n)) {
                Hyprland.refreshToplevels();
                Hyprland.refreshWorkspaces();
            } else if (n.includes("workspace")) {
                Hyprland.refreshWorkspaces();
            } else if (n.includes("window")) {
                Hyprland.refreshToplevels();
                Hyprland.refreshWorkspaces();
            }
        }
    }
}
