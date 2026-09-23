pragma Singleton

import Quickshell
import Quickshell.Io
import QtQuick
import "." as QsServices

Singleton {
    id: root

    property bool ready: false
    property bool muted: false
    property real volume: 0
    readonly property int percentage: Math.round(volume * 100)

    property bool sourceReady: false
    property bool sourceMuted: false
    property real sourceVolume: 0
    readonly property int sourcePercentage: Math.round(sourceVolume * 100)

    // Backend management: "wpctl" or "pactl"
    property string backend: "wpctl"

    Component.onCompleted: {
        checkBackendProc.exec(["sh", "-c", "command -v wpctl || command -v pactl"])
    }

    Process {
        id: checkBackendProc
        stdout: StdioCollector {
            onStreamFinished: {
                const path = text.trim()
                if (path.includes("pactl") && !path.includes("wpctl")) {
                    root.backend = "pactl"
                } else {
                    root.backend = "wpctl"
                }
                QsServices.Logger.info("Audio", `Using backend: ${root.backend}`)
            }
        }
    }

    Timer {
        interval: 1000
        running: true
        repeat: true
        onTriggered: {
            if (root.backend === "pactl") {
                if (!getPactlSink.running) getPactlSink.running = true
                if (!getPactlSource.running) getPactlSource.running = true
            } else {
                if (!getSink.running) getSink.running = true
                if (!getSource.running) getSource.running = true
            }
        }
    }

    // --- WirePlumber (wpctl) Processes ---
    Process {
        id: getSink
        command: ["wpctl", "get-volume", "@DEFAULT_AUDIO_SINK@"]
        stdout: StdioCollector {
            onStreamFinished: {
                const s = text.trim()
                const m = s.match(/Volume:\s*([0-9.]+)/)
                if (m) {
                    const v = parseFloat(m[1])
                    if (!isNaN(v)) {
                        root.ready = true
                        root.volume = Math.max(0, Math.min(1.5, v))
                    }
                }
                root.muted = /\[MUTED\]/.test(s)
            }
        }
    }

    Process {
        id: getSource
        command: ["wpctl", "get-volume", "@DEFAULT_AUDIO_SOURCE@"]
        stdout: StdioCollector {
            onStreamFinished: {
                const s = text.trim()
                const m = s.match(/Volume:\s*([0-9.]+)/)
                if (m) {
                    const v = parseFloat(m[1])
                    if (!isNaN(v)) {
                        root.sourceReady = true
                        root.sourceVolume = Math.max(0, Math.min(1.5, v))
                    }
                }
                root.sourceMuted = /\[MUTED\]/.test(s)
            }
        }
    }

    // --- PulseAudio (pactl) Processes ---
    Process {
        id: getPactlSink
        command: ["pactl", "get-sink-volume", "@DEFAULT_SINK@"]
        stdout: StdioCollector {
            onStreamFinished: {
                const s = text.trim()
                const m = s.match(/(\d+)%/)
                if (m) {
                    const pct = parseInt(m[1])
                    if (!isNaN(pct)) {
                        root.ready = true
                        root.volume = Math.max(0, Math.min(1.5, pct / 100.0))
                    }
                }
                if (!getPactlSinkMute.running) getPactlSinkMute.running = true
            }
        }
    }

    Process {
        id: getPactlSinkMute
        command: ["pactl", "get-sink-mute", "@DEFAULT_SINK@"]
        stdout: StdioCollector {
            onStreamFinished: {
                root.muted = /yes/i.test(text.trim())
            }
        }
    }

    Process {
        id: getPactlSource
        command: ["pactl", "get-source-volume", "@DEFAULT_SOURCE@"]
        stdout: StdioCollector {
            onStreamFinished: {
                const s = text.trim()
                const m = s.match(/(\d+)%/)
                if (m) {
                    const pct = parseInt(m[1])
                    if (!isNaN(pct)) {
                        root.sourceReady = true
                        root.sourceVolume = Math.max(0, Math.min(1.5, pct / 100.0))
                    }
                }
                if (!getPactlSourceMute.running) getPactlSourceMute.running = true
            }
        }
    }

    Process {
        id: getPactlSourceMute
        command: ["pactl", "get-source-mute", "@DEFAULT_SOURCE@"]
        stdout: StdioCollector {
            onStreamFinished: {
                root.sourceMuted = /yes/i.test(text.trim())
            }
        }
    }

    // --- Action Methods ---
    function setVolume(newVolume) {
        setMute(false)
        const targetVol = Math.max(0, Math.min(1.5, newVolume))
        if (backend === "pactl") {
            const pct = Math.round(targetVol * 100)
            setVolProc.command = ["pactl", "set-sink-volume", "@DEFAULT_SINK@", `${pct}%`]
        } else {
            setVolProc.command = ["wpctl", "set-volume", "@DEFAULT_AUDIO_SINK@", targetVol.toFixed(3)]
        }
        setVolProc.running = true
    }

    function increaseVolume() {
        setVolume(volume + 0.05)
    }

    function decreaseVolume() {
        setVolume(volume - 0.05)
    }

    function setMute(m) {
        if (backend === "pactl") {
            setMuteProc.command = ["pactl", "set-sink-mute", "@DEFAULT_SINK@", m ? "1" : "0"]
        } else {
            setMuteProc.command = ["wpctl", "set-mute", "@DEFAULT_AUDIO_SINK@", m ? "1" : "0"]
        }
        setMuteProc.running = true
    }

    function toggleMute() {
        if (backend === "pactl") {
            setMuteProc.command = ["pactl", "set-sink-mute", "@DEFAULT_SINK@", "toggle"]
        } else {
            setMuteProc.command = ["wpctl", "set-mute", "@DEFAULT_AUDIO_SINK@", "toggle"]
        }
        setMuteProc.running = true
    }

    function setSourceVolume(newVolume) {
        setSourceMute(false)
        const targetVol = Math.max(0, Math.min(1.5, newVolume))
        if (backend === "pactl") {
            const pct = Math.round(targetVol * 100)
            setSourceVolProc.command = ["pactl", "set-source-volume", "@DEFAULT_SOURCE@", `${pct}%`]
        } else {
            setSourceVolProc.command = ["wpctl", "set-volume", "@DEFAULT_AUDIO_SOURCE@", targetVol.toFixed(3)]
        }
        setSourceVolProc.running = true
    }

    function setSourceMute(m) {
        if (backend === "pactl") {
            setSourceMuteProc.command = ["pactl", "set-source-mute", "@DEFAULT_SOURCE@", m ? "1" : "0"]
        } else {
            setSourceMuteProc.command = ["wpctl", "set-mute", "@DEFAULT_AUDIO_SOURCE@", m ? "1" : "0"]
        }
        setSourceMuteProc.running = true
    }

    function toggleSourceMute() {
        if (backend === "pactl") {
            setSourceMuteProc.command = ["pactl", "set-source-mute", "@DEFAULT_SOURCE@", "toggle"]
        } else {
            setSourceMuteProc.command = ["wpctl", "set-mute", "@DEFAULT_AUDIO_SOURCE@", "toggle"]
        }
        setSourceMuteProc.running = true
    }

    Process { id: setVolProc }
    Process { id: setMuteProc }
    Process { id: setSourceVolProc }
    Process { id: setSourceMuteProc }
}
