import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let statsProvider = StatsProvider()
    private var timer: Timer?
    private var latestSnapshot: SystemSnapshot?

    private let cpuItem = NSMenuItem(title: "CPU: --", action: nil, keyEquivalent: "")
    private let memoryItem = NSMenuItem(title: "Memory: --", action: nil, keyEquivalent: "")
    private let temperatureItem = NSMenuItem(title: "Temperature: --", action: nil, keyEquivalent: "")
    private let thermalItem = NSMenuItem(title: "Thermal State: --", action: nil, keyEquivalent: "")
    private let updatedItem = NSMenuItem(title: "Updated: --", action: nil, keyEquivalent: "")

    func applicationDidFinishLaunching(_ notification: Notification) {
        configureStatusButton()
        configureMenu()
        refresh()

        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.refresh()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        timer?.invalidate()
    }

    private func configureStatusButton() {
        guard let button = statusItem.button else { return }
        button.font = NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .medium)
        button.toolTip = "MacStats"
    }

    private func configureMenu() {
        let menu = NSMenu()
        menu.addItem(cpuItem)
        menu.addItem(memoryItem)
        menu.addItem(temperatureItem)
        menu.addItem(thermalItem)
        menu.addItem(NSMenuItem.separator())
        menu.addItem(updatedItem)
        menu.addItem(NSMenuItem.separator())

        let copyItem = NSMenuItem(title: "Copy Snapshot", action: #selector(copySnapshot), keyEquivalent: "c")
        copyItem.target = self
        menu.addItem(copyItem)

        let quitItem = NSMenuItem(title: "Quit MacStats", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        menu.addItem(quitItem)
        statusItem.menu = menu
    }

    private func refresh() {
        let snapshot = statsProvider.snapshot()
        latestSnapshot = snapshot

        if let button = statusItem.button {
            button.title = snapshot.menuBarTitle
            button.toolTip = snapshot.tooltip
        }

        cpuItem.title = "CPU: \(snapshot.cpu.formattedLong)"
        memoryItem.title = "Memory: \(snapshot.memory.formattedLong)"
        temperatureItem.title = "Temperature: \(snapshot.temperature.formattedLong)"
        thermalItem.title = "Thermal State: \(snapshot.thermalState.displayName)"
        updatedItem.title = "Updated: \(snapshot.updated.formatted(date: .omitted, time: .standard))"
    }

    @objc private func copySnapshot() {
        guard let latestSnapshot else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(latestSnapshot.clipboardText, forType: .string)
    }
}
