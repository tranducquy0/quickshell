pragma Singleton

import Quickshell
import Quickshell.Io
import QtQuick
import "." as QsServices

Singleton {
    id: root

    readonly property list<AccessPoint> networks: []
    readonly property AccessPoint active: networks.find(n => n.active) ?? null
    property bool wifiEnabled: true
    readonly property bool scanning: rescanProc.running || iwctlScanProc.running
    
    // Convenience properties for Control Center
    readonly property bool connected: active !== null
    readonly property string ssid: active?.ssid ?? "Not Connected"
    readonly property int signalStrength: active?.strength ?? 0
    
    property var savedNetworks: []
    
    // Backend: "nmcli" or "iwctl"
    property string backend: "nmcli"
    property string stationDevice: "wlan0"

    // Consumer visibility control - set to false to pause polling when UI is hidden
    property bool pollingActive: true

    Component.onCompleted: {
        checkBackendProc.exec(["sh", "-c", "command -v iwctl || command -v nmcli"])
    }

    Process {
        id: checkBackendProc
        stdout: StdioCollector {
            onStreamFinished: {
                const path = text.trim()
                if (path.includes("iwctl") && !path.includes("nmcli")) {
                    root.backend = "iwctl"
                } else {
                    root.backend = "nmcli"
                }
                QsServices.Logger.info("Network", `Using backend: ${root.backend}`)
                if (root.backend === "iwctl") {
                    getStationDeviceProc.exec(["iwctl", "device", "list"])
                } else {
                    refreshSavedNetworks()
                    getWifiStatus()
                }
            }
        }
    }

    Process {
        id: getStationDeviceProc
        stdout: StdioCollector {
            onStreamFinished: {
                const clean = text.replace(/\x1B\[[0-9;]*[a-zA-Z]/g, "")
                const lines = clean.split('\n')
                for (const line of lines) {
                    const match = line.match(/^\s*([\w-]+)\s+station/i)
                    if (match) {
                        root.stationDevice = match[1].trim()
                        break
                    }
                }
                QsServices.Logger.info("Network", `iwctl station device: ${root.stationDevice}`)
                refreshSavedNetworks()
                getWifiStatus()
            }
        }
    }

    function enableWifi(enabled: bool): void {
        if (backend === "iwctl") {
            const cmd = enabled ? "on" : "off"
            enableWifiProc.exec(["iwctl", "device", stationDevice, "set-property", "Powered", cmd])
        } else {
            const cmd = enabled ? "on" : "off"
            enableWifiProc.exec(["nmcli", "radio", "wifi", cmd])
        }
    }

    function toggleWifi(): void {
        enableWifi(!wifiEnabled)
    }

    function rescanWifi(): void {
        if (backend === "iwctl") {
            iwctlScanProc.exec(["iwctl", "station", stationDevice, "scan"])
        } else {
            rescanProc.running = true
        }
    }

    function connectToNetwork(ssid: string, password: string): void {
        // Validate SSID to prevent command injection
        if (!ssid || ssid.trim().length === 0) {
            QsServices.Logger.warn("Network", "Invalid SSID: empty")
            return
        }
        
        // Check for dangerous characters that could be used for injection
        const dangerousChars = [";", "`", "$", "|", "&", "\n", "\r", "\\"]
        for (let i = 0; i < dangerousChars.length; i++) {
            if (ssid.includes(dangerousChars[i])) {
                QsServices.Logger.warn("Network", "Invalid SSID: contains dangerous character")
                return
            }
        }
        
        QsServices.Logger.info("Network", `Connecting to: ${ssid} ${password.length > 0 ? "(with password)" : "(saved)"}`)
        
        if (backend === "iwctl") {
            if (password && password.length > 0) {
                connectProc.exec(["iwctl", "--passphrase", password, "station", stationDevice, "connect", ssid])
            } else {
                connectProc.exec(["iwctl", "station", stationDevice, "connect", ssid])
            }
        } else {
            if (password && password.length > 0) {
                connectProc.exec(["nmcli", "dev", "wifi", "connect", ssid, "password", password])
            } else {
                connectProc.exec(["nmcli", "connection", "up", "id", ssid])
            }
        }
    }

    function refreshSavedNetworks(): void {
        if (backend === "iwctl") {
            checkSavedIwctlProc.running = true
        } else {
            checkSavedProc.running = true
        }
    }
    
    function isNetworkSaved(ssid: string): bool {
        return savedNetworks.includes(ssid)
    }

    function disconnectFromNetwork(): void {
        if (backend === "iwctl") {
            disconnectProc.exec(["iwctl", "station", stationDevice, "disconnect"])
        } else {
            if (active) {
                disconnectProc.exec(["nmcli", "connection", "down", active.ssid])
            }
        }
    }

    function getWifiStatus(): void {
        if (backend === "iwctl") {
            wifiStatusIwctlProc.exec(["iwctl", "device", stationDevice, "show"])
        } else {
            wifiStatusProc.running = true
        }
    }

    // Monitoring Process for nmcli
    Process {
        running: root.backend === "nmcli"
        command: ["nmcli", "m"]
        stdout: SplitParser {
            onRead: getNetworks.running = true
        }
    }

    Process {
        id: wifiStatusProc
        command: ["nmcli", "radio", "wifi"]
        environment: ({
                LANG: "C.UTF-8",
                LC_ALL: "C.UTF-8"
            })
        stdout: StdioCollector {
            onStreamFinished: {
                root.wifiEnabled = text.trim() === "enabled"
            }
        }
    }

    Process {
        id: wifiStatusIwctlProc
        stdout: StdioCollector {
            onStreamFinished: {
                const clean = text.replace(/\x1B\[[0-9;]*[a-zA-Z]/g, "")
                root.wifiEnabled = /Powered\s+on/i.test(clean) || !/Powered\s+off/i.test(clean)
            }
        }
    }

    Process {
        id: enableWifiProc
        onExited: {
            root.getWifiStatus()
            getNetworks.running = true
        }
    }

    Process {
        id: rescanProc
        command: ["nmcli", "dev", "wifi", "list", "--rescan", "yes"]
        onExited: {
            getNetworks.running = true
        }
    }

    Process {
        id: iwctlScanProc
        onExited: {
            getNetworks.running = true
        }
    }

    Process {
        id: connectProc
        stdout: SplitParser {
            onRead: data => {
                QsServices.Logger.debug("Network", `Connection output: ${data}`)
                getNetworks.running = true
            }
        }
        stderr: StdioCollector {
            onStreamFinished: {
                if (text.trim().length > 0) {
                    QsServices.Logger.warn("Network", `Connection error: ${text.trim()}`)
                }
            }
        }
        onExited: (code, status) => {
            QsServices.Logger.debug("Network", `Connection exited code=${code} status=${status}`)
            getNetworks.running = true
        }
    }

    Process {
        id: disconnectProc
        stdout: SplitParser {
            onRead: getNetworks.running = true
        }
        onExited: {
            getNetworks.running = true
        }
    }
    
    Process {
        id: checkSavedProc
        command: ["nmcli", "-g", "NAME", "connection", "show"]
        environment: ({
                LANG: "C.UTF-8",
                LC_ALL: "C.UTF-8"
            })
        stdout: StdioCollector {
            onStreamFinished: {
                root.savedNetworks = text.trim().split('\n').filter(n => n.length > 0)
                updateSavedNetworksLog()
            }
        }
    }

    Process {
        id: checkSavedIwctlProc
        command: ["iwctl", "known-networks", "list"]
        stdout: StdioCollector {
            onStreamFinished: {
                const clean = text.replace(/\x1B\[[0-9;]*[a-zA-Z]/g, "")
                const lines = clean.split('\n')
                const saved = []
                for (const line of lines) {
                    if (line.includes("---") || line.includes("Known networks") || line.includes("Name")) continue
                    const parts = line.trim().split(/\s{2,}/)
                    if (parts[0] && parts[0].length > 0) {
                        saved.push(parts[0])
                    }
                }
                root.savedNetworks = saved
                updateSavedNetworksLog()
            }
        }
    }

    function updateSavedNetworksLog() {
        const current = root.savedNetworks
        const prev = root._prevSavedNetworks
        let changed = current.length !== prev.length
        if (!changed) {
            for (let i = 0; i < current.length; i++) {
                if (current[i] !== prev[i]) {
                    changed = true
                    break
                }
            }
        }
        if (changed) {
            root._prevSavedNetworks = current.slice(0)
            QsServices.Logger.debug("Network", `Saved networks: ${root.savedNetworks.length}`)
        }
    }

    property var _prevSavedNetworks: []
    
    Timer {
        interval: 10000 // Refresh saved networks & networks list
        running: root.pollingActive
        repeat: true
        onTriggered: {
            refreshSavedNetworks()
            if (!getNetworks.running) getNetworks.running = true
        }
    }

    Process {
        id: getNetworks
        running: true
        command: backend === "iwctl" ? ["iwctl", "station", stationDevice, "get-networks"] : ["nmcli", "-g", "ACTIVE,SIGNAL,FREQ,SSID,BSSID,SECURITY", "d", "w"]
        environment: ({
                LANG: "C.UTF-8",
                LC_ALL: "C.UTF-8"
            })
        stdout: StdioCollector {
            onStreamFinished: {
                let allNetworks = []

                if (root.backend === "iwctl") {
                    const clean = text.replace(/\x1B\[[0-9;]*[a-zA-Z]/g, "")
                    const lines = clean.split("\n")
                    for (const line of lines) {
                        if (line.includes("---") || line.includes("Available networks") || line.includes("Network name")) continue
                        const isActive = line.startsWith("*") || line.startsWith(">") || /^\s*[\*\>]/.test(line)
                        const trimmedLine = line.replace(/^\s*[\*\>]\s*/, "").trim()
                        if (trimmedLine.length === 0) continue

                        const parts = trimmedLine.split(/\s{2,}/)
                        if (parts.length >= 3) {
                            const netSsid = parts[0].trim()
                            const netSec = parts[1].trim()
                            const signalStr = parts[2].trim()
                            let netStrength = 0
                            if (signalStr.includes("*")) {
                                netStrength = Math.min(100, (signalStr.match(/\*/g) || []).length * 25)
                            } else {
                                netStrength = parseInt(signalStr) || 50
                            }
                            allNetworks.push({
                                active: isActive,
                                strength: netStrength,
                                frequency: 2400,
                                ssid: netSsid,
                                bssid: "",
                                security: netSec.toLowerCase() === "open" ? "" : netSec
                            })
                        }
                    }
                } else {
                    const PLACEHOLDER = "STRINGWHICHHOPEFULLYWONTBEUSED"
                    const rep = new RegExp("\\\\:", "g")
                    const rep2 = new RegExp(PLACEHOLDER, "g")

                    allNetworks = text.trim().split("\n").map(n => {
                        const net = n.replace(rep, PLACEHOLDER).split(":")
                        return {
                            active: net[0] === "yes",
                            strength: parseInt(net[1]),
                            frequency: parseInt(net[2]),
                            ssid: net[3]?.replace(rep2, ":") ?? "",
                            bssid: net[4]?.replace(rep2, ":") ?? "",
                            security: net[5] ?? ""
                        }
                    }).filter(n => n.ssid && n.ssid.length > 0)
                }

                // Group networks by SSID and prioritize connected ones
                const networkMap = new Map()
                for (const network of allNetworks) {
                    const existing = networkMap.get(network.ssid)
                    if (!existing) {
                        networkMap.set(network.ssid, network)
                    } else {
                        if (network.active && !existing.active) {
                            networkMap.set(network.ssid, network)
                        } else if (!network.active && !existing.active) {
                            if (network.strength > existing.strength) {
                                networkMap.set(network.ssid, network)
                            }
                        }
                    }
                }

                const networks = Array.from(networkMap.values())
                const rNetworks = root.networks

                const destroyed = rNetworks.filter(rn => !networks.find(n => n.ssid === rn.ssid))
                for (const network of destroyed)
                    rNetworks.splice(rNetworks.indexOf(network), 1).forEach(n => n.destroy())

                for (const network of networks) {
                    const match = rNetworks.find(n => n.ssid === network.ssid)
                    if (match) {
                        match.lastIpcObject = network
                    } else {
                        rNetworks.push(apComp.createObject(root, {
                            lastIpcObject: network
                        }))
                    }
                }
            }
        }
    }

    component AccessPoint: QtObject {
        required property var lastIpcObject
        readonly property string ssid: lastIpcObject.ssid
        readonly property string bssid: lastIpcObject.bssid
        readonly property int strength: lastIpcObject.strength
        readonly property int frequency: lastIpcObject.frequency
        readonly property bool active: lastIpcObject.active
        readonly property string security: lastIpcObject.security
        readonly property bool isSecure: security.length > 0
    }

    Component {
        id: apComp

        AccessPoint {}
    }
}
