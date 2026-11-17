import SwiftUI
import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var window: NSWindow?
    /// 是否由终端 URL 请求唤起；仅这种情况下执行后退出。
    private var launchedForURL = false
    private var receivedURL = false

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
        // launchIsDefaultLaunchKey=false 也可能是 open -n 等普通启动，
        // 不能仅据此进入无窗口模式。等待实际 URL 事件决定启动方式。
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            if !self.receivedURL { self.showSettingsWindow() }
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
        receivedURL = true
        if window == nil { launchedForURL = true }
        // URL 事件可能先于 didFinishLaunching 到达；延后检查启动状态，
        // 无效请求也必须清理无窗口的临时进程。
        defer {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                if self.launchedForURL { NSApp.terminate(nil) }
            }
        }
        guard let s = event.paramDescriptor(forKeyword: keyDirectObject)?.stringValue,
              let url = URL(string: s), let request = TerminalRequest(url: url) else { return }
        TerminalLauncher.run(request)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}

enum TerminalLauncher {
    static func run(_ request: TerminalRequest) {
        var isDirectory: ObjCBool = false
        guard TerminalRequest.isSafePath(request.path),
              FileManager.default.fileExists(atPath: request.path, isDirectory: &isDirectory),
              isDirectory.boolValue else { return }
        let dir = URL(fileURLWithPath: request.path)

        // 自定义 URL scheme 可由网页或其他应用调用，不能据此认定来自 Finder。
        // 每次明确确认后才向终端发送命令；默认按钮为取消。
        let confirm = NSAlert()
        confirm.messageText = "在 \(request.terminal.rawValue) 中打开文件夹？"
        confirm.informativeText = "目标：\(request.path)\n\n仅当这是你刚刚发起的操作时才继续。外部链接也能发起此请求。"
        confirm.addButton(withTitle: "取消")
        confirm.addButton(withTitle: "打开")
        NSApp.activate(ignoringOtherApps: true)
        guard confirm.runModal() == .alertSecondButtonReturn else { return }

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
