import SwiftUI
import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var window: NSWindow?
    /// 是否只是被扩展唤起来执行一次“在终端中打开”（这种情况下不显示窗口，执行完就退出）
    private var launchedForURL = false

    func applicationWillFinishLaunching(_ notification: Notification) {
        NSAppleEventManager.shared().setEventHandler(
            self, andSelector: #selector(handleGetURL(_:reply:)),
            forEventClass: AEEventClass(kInternetEventClass), andEventID: AEEventID(kAEGetURL))
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        SharedPaths.ensureDirectories()
        if !FileManager.default.fileExists(atPath: SharedPaths.settingsFile.path) {
            AppSettings.defaults.save()
        }
        // 通过 URL 启动时 launchIsDefaultLaunchKey 为 false
        let isDefaultLaunch = (notification.userInfo?[NSApplication.launchIsDefaultUserInfoKey] as? Bool) ?? true
        if isDefaultLaunch {
            showSettingsWindow()
        } else {
            launchedForURL = true
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag { showSettingsWindow() }
        return true
    }

    private func showSettingsWindow() {
        launchedForURL = false
        if window == nil {
            let w = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 700, height: 560),
                styleMask: [.titled, .closable, .miniaturizable, .resizable],
                backing: .buffered, defer: false)
            w.title = "OpenQuickDoc"
            w.contentView = NSHostingView(rootView: ContentView())
            w.isReleasedWhenClosed = false
            w.center()
            window = w
        }
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    // MARK: - openquickdoc://open-terminal?app=…&path=…

    @objc private func handleGetURL(_ event: NSAppleEventDescriptor, reply: NSAppleEventDescriptor) {
        guard let s = event.paramDescriptor(forKeyword: keyDirectObject)?.stringValue,
              let url = URL(string: s), let request = TerminalRequest(url: url) else { return }
        TerminalLauncher.run(request)
        if launchedForURL {
            // 给 AppleScript / 弹窗留出时间后退出，不在 Dock 里常驻
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                if self.launchedForURL { NSApp.terminate(nil) }
            }
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}

enum TerminalLauncher {
    static func run(_ request: TerminalRequest) {
        let dir = URL(fileURLWithPath: request.path)
        guard let script = request.appleScript else {
            // Warp / Ghostty：直接把文件夹交给应用
            if let app = NSWorkspace.shared.urlForApplication(withBundleIdentifier: request.terminal.bundleIdentifier) {
                NSWorkspace.shared.open([dir], withApplicationAt: app, configuration: NSWorkspace.OpenConfiguration(), completionHandler: nil)
            }
            return
        }
        var error: NSDictionary?
        NSAppleScript(source: script)?.executeAndReturnError(&error)
        guard let error else { return }

        let code = error[NSAppleScript.errorNumber] as? Int ?? 0
        let alert = NSAlert()
        alert.alertStyle = .warning
        if code == -1743 {
            alert.messageText = "没有控制 \(request.terminal.rawValue) 的权限"
            alert.informativeText = "请在 系统设置 › 隐私与安全性 › 自动化 中，允许 OpenQuickDoc 控制 \(request.terminal.rawValue)。"
            alert.addButton(withTitle: "打开系统设置")
            alert.addButton(withTitle: "取消")
            NSApp.activate(ignoringOtherApps: true)
            if alert.runModal() == .alertFirstButtonReturn,
               let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation") {
                NSWorkspace.shared.open(url)
            }
        } else {
            alert.messageText = "在 \(request.terminal.rawValue) 中打开失败"
            alert.informativeText = (error[NSAppleScript.errorMessage] as? String ?? "") + " (\(code))"
            NSApp.activate(ignoringOtherApps: true)
            alert.runModal()
        }
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
