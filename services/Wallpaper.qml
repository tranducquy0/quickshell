pragma Singleton

import Quickshell
import Quickshell.Io
import QtQuick 6.10
import "." as QsServices

Singleton {
    id: root

    property var wallpapers: []
    property int currentIndex: -1
    property string currentWallpaper: currentIndex >= 0 && currentIndex < wallpapers.length ? wallpapers[currentIndex] : ""

    Component.onCompleted: {
        findWallpapersProc.exec(["sh", "-c", "find \"$HOME/Pictures\" -type f \\( -iname \"*.jpg\" -o -iname \"*.jpeg\" -o -iname \"*.png\" -o -iname \"*.webp\" \\) 2>/dev/null | sort"])
    }

    Process {
        id: findWallpapersProc
        stdout: StdioCollector {
            onStreamFinished: {
                const list = text.trim().split('\n').filter(p => p.length > 0)
                root.wallpapers = list
                QsServices.Logger.info("Wallpaper", `Found ${list.length} wallpapers`)
            }
        }
    }

    function setWallpaper(path: string): void {
        if (!path || path.trim().length === 0) return

        const idx = wallpapers.indexOf(path)
        if (idx !== -1) {
            currentIndex = idx
        } else {
            wallpapers.push(path)
            currentIndex = wallpapers.length - 1
        }

        QsServices.Logger.info("Wallpaper", `Setting wallpaper: ${path}`)

        // 1. Run pywal
        walProc.exec(["wal", "-i", path, "-n", "-q"])

        // 2. Set compositor wallpaper (swww -> swaybg -> hyprpaper)
        applyWallpaperProc.exec(["sh", "-c", "if command -v swww >/dev/null 2>&1; then swww img \"$1\"; elif command -v swaybg >/dev/null 2>&1; then pkill swaybg; swaybg -i \"$1\" -m fill & elif command -v hyprctl >/dev/null 2>&1; then hyprctl hyprpaper unload all; hyprctl hyprpaper preload \"$1\"; hyprctl hyprpaper wallpaper \", $1\"; fi", "sh", path])
    }

    function nextWallpaper(): void {
        if (wallpapers.length === 0) {
            findWallpapersProc.exec(["sh", "-c", "find \"$HOME/Pictures\" -type f \\( -iname \"*.jpg\" -o -iname \"*.jpeg\" -o -iname \"*.png\" -o -iname \"*.webp\" \\) 2>/dev/null | sort"])
            return
        }
        const nextIdx = (currentIndex + 1) % wallpapers.length
        setWallpaper(wallpapers[nextIdx])
    }

    function previousWallpaper(): void {
        if (wallpapers.length === 0) return
        const prevIdx = (currentIndex - 1 + wallpapers.length) % wallpapers.length
        setWallpaper(wallpapers[prevIdx])
    }

    Process { id: walProc }
    Process { id: applyWallpaperProc }
}
