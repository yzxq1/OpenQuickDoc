import Cocoa
import FinderSync

/// FinderSync 的菜单会被序列化后交给 Finder 进程显示，点击回调时 `representedObject` 已丢失，
/// 只有 title / tag / image 等基本属性会保留。因此用 tag 区分菜单项（原版同样使用 tag 分发）。
private enum Tag {
    static let builtin = 1000   // + FileItemDefinition.all 下标
    static let custom  = 3000   // + customExtensions 下标
    static let editor  = 2000   // + EditorTarget.allCases 下标
}

final class FinderSync: FIFinderSync {

    private let bundle = Bundle(for: FinderSync.self)
    // tag 在扩展进程内保持稳定，不依赖点击时可能已改变的设置数组下标。
    private var customMenuRegistry = CustomMenuRegistry(startTag: Tag.custom)

    override init() {
        super.init()
        let dirs = Self.monitoredDirectories()
        FIFinderSyncController.default().directoryURLs = Set(dirs)
        DiagnosticLog.write("扩展已加载")
    }

    /// "/" 覆盖本机与外接卷；iCloud Drive 在 Finder 中是独立的位置，需要显式加入（原版同样如此）
    private static func monitoredDirectories() -> [URL] {
        let home = SharedPaths.realHome
        return [
            URL(fileURLWithPath: "/"),
            URL(fileURLWithPath: "/Volumes"),
            home.appendingPathComponent("Library/Mobile Documents"),
            home.appendingPathComponent("Library/Mobile Documents/com~apple~CloudDocs"),
        ]
    }

    // MARK: - 工具栏

    override var toolbarItemName: String { "OpenQuickDoc" }
    override var toolbarItemToolTip: String { "新建文件 / 在编辑器中打开 / 复制路径" }
    override var toolbarItemImage: NSImage { symbol("doc.badge.plus") }

    // MARK: - 菜单

    override func menu(for menuKind: FIMenuKind) -> NSMenu? {
        let settings = AppSettings.load()
        let menu = NSMenu(title: "")

        // 1. 新建文件
        var fileItems: [NSMenuItem] = []
        for def in settings.orderedEnabledDefinitions {
            guard let i = FileItemDefinition.all.firstIndex(of: def) else { continue }
            fileItems.append(makeItem(def.title, #selector(createFile(_:)), image: symbol(def.symbol), tag: Tag.builtin + i))
        }
        for def in settings.customDefinitions {
            fileItems.append(makeItem(def.title, #selector(createFile(_:)), image: symbol(def.symbol),
                                      tag: customMenuRegistry.tag(for: def)))
        }

        if settings.useSubmenu {
            let root = NSMenuItem(title: "新建文件", action: nil, keyEquivalent: "")
            root.image = symbol("doc.badge.plus")
            let sub = NSMenu(title: "新建文件")
            if fileItems.isEmpty {
                let placeholder = NSMenuItem(title: "未启用新建文件类型", action: nil, keyEquivalent: "")
                placeholder.isEnabled = false
                sub.addItem(placeholder)
            } else {
                fileItems.forEach(sub.addItem)
            }
            root.submenu = sub
            menu.addItem(root)
        } else {
            fileItems.forEach(menu.addItem)
        }

        // 2. 工具项
        var tools: [NSMenuItem] = []
        if settings.openInVSCodeEnabled { tools.append(editorItem(.vscode)) }
        if settings.openInPyCharmEnabled { tools.append(editorItem(.pycharm)) }
        if settings.terminalDirectEnabled {
            let t = settings.selectedTerminal
            let title = t == .terminal ? "在终端中打开" : "在 \(t.rawValue) 中打开"
            tools.append(makeItem(title, #selector(openTerminal(_:)), image: appIcon([t.bundleIdentifier]) ?? symbol("terminal")))
        }
        if settings.pathCopyEnabled {
            tools.append(makeItem("复制当前路径", #selector(copyPath(_:)), image: symbol("doc.on.doc")))
        }
        if !tools.isEmpty {
            if !menu.items.isEmpty && !settings.useSubmenu { menu.addItem(.separator()) }
            tools.forEach(menu.addItem)
        }
        return menu.items.isEmpty ? nil : menu
    }

    private func makeItem(_ title: String, _ action: Selector, image: NSImage?, tag: Int = 0) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        item.image = image
        item.tag = tag
        return item
    }

    private func editorItem(_ editor: EditorTarget) -> NSMenuItem {
        makeItem(editor.title, #selector(openInEditor(_:)),
                 image: appIcon(editor.bundleIdentifiers) ?? symbol(editor.fallbackSymbol),
                 tag: Tag.editor + (EditorTarget.allCases.firstIndex(of: editor) ?? 0))
    }

    // MARK: - 图标

    private func symbol(_ name: String) -> NSImage {
        let img = NSImage(systemSymbolName: name, accessibilityDescription: nil) ?? NSImage()
        img.isTemplate = true
        return img
    }

    private func appIcon(_ bundleIDs: [String]) -> NSImage? {
        guard let url = appURL(bundleIDs) else { return nil }
        let img = NSWorkspace.shared.icon(forFile: url.path)
        img.size = NSSize(width: 16, height: 16)
        return img
    }

    private func appURL(_ bundleIDs: [String]) -> URL? {
        bundleIDs.lazy.compactMap { NSWorkspace.shared.urlForApplication(withBundleIdentifier: $0) }.first
    }

    // MARK: - 目标定位

    private var controller: FIFinderSyncController { .default() }

    /// 选中的项目；若在空白处右键则为当前目录
    private var selectedOrCurrent: [URL] {
        if let sel = controller.selectedItemURLs(), !sel.isEmpty { return sel }
        if let cur = controller.targetedURL() { return [cur] }
        return []
    }

    /// 新建文件的目录：空白处 → 当前目录；右键单个文件夹 → 该文件夹；右键文件 → 其所在目录
    private var creationDirectory: URL? {
        if let sel = controller.selectedItemURLs(), sel.count == 1 {
            return isDirectory(sel[0]) ? sel[0] : sel[0].deletingLastPathComponent()
        }
        return controller.targetedURL()
    }

    private func isDirectory(_ url: URL) -> Bool {
        (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
    }

    // MARK: - 动作

    @objc private func createFile(_ sender: NSMenuItem) {
        DiagnosticLog.write("点击新建菜单")
        let settings = AppSettings.load()
        let def: FileItemDefinition
        switch sender.tag {
        case Tag.builtin..<(Tag.builtin + FileItemDefinition.all.count):
            def = FileItemDefinition.all[sender.tag - Tag.builtin]
        default:
            guard let custom = customMenuRegistry.definition(for: sender.tag) else {
                DiagnosticLog.write("未知菜单项")
                return
            }
            def = custom
        }
        guard let dir = creationDirectory else {
            DiagnosticLog.write("无法确定目标文件夹")
            showAlert("无法确定目标文件夹。")
            return
        }
        do {
            let url = try FileFactory.create(def, in: dir, bundle: bundle)
            DiagnosticLog.write("已创建文件")
            if settings.openFileAfterCreation {
                NSWorkspace.shared.open(url)
            } else {
                NSWorkspace.shared.activateFileViewerSelecting([url])
            }
        } catch {
            DiagnosticLog.write("创建文件失败")
            showAlert("创建文件失败：", detail: "\(dir.path)\n\n\(error.localizedDescription)")
        }
    }

    @objc private func openInEditor(_ sender: NSMenuItem) {
        let i = sender.tag - Tag.editor
        guard EditorTarget.allCases.indices.contains(i) else { return }
        let editor = EditorTarget.allCases[i]
        DiagnosticLog.write("请求在编辑器中打开")
        open(selectedOrCurrent, withAnyOf: editor.bundleIdentifiers, appName: editor.title)
    }

    @objc private func openTerminal(_ sender: NSMenuItem) {
        let terminal = AppSettings.load().selectedTerminal
        // 终端只接受目录：选中文件时取其所在目录
        guard let dir = selectedOrCurrent.first.map({ isDirectory($0) ? $0 : $0.deletingLastPathComponent() }) else { return }
        DiagnosticLog.write("请求在终端中打开")
        // 终端收到文件夹不会 cd 过去（实测 iTerm2 只开在主目录），需要 AppleScript；
        // 沙盒里不能发 Apple Events，所以交给主程序执行（见 TerminalRequest）。
        guard let url = TerminalRequest(terminal: terminal, path: dir.path).url else { return }
        let config = NSWorkspace.OpenConfiguration()
        config.activates = false
        NSWorkspace.shared.open(url, configuration: config) { _, error in
            if let error {
                DiagnosticLog.write("唤起主程序失败")
                self.showAlert("唤起 OpenQuickDoc 失败：", detail: error.localizedDescription)
            }
        }
    }

    @objc private func copyPath(_ sender: NSMenuItem) {
        let paths = selectedOrCurrent.map(\.path)
        guard !paths.isEmpty else { return }
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(paths.joined(separator: "\n"), forType: .string)
        DiagnosticLog.write("已复制路径")
    }

    private func open(_ urls: [URL], withAnyOf bundleIDs: [String], appName: String) {
        guard !urls.isEmpty else { return }
        guard let app = appURL(bundleIDs) else {
            DiagnosticLog.write("目标应用未安装")
            showAlert("未找到应用", detail: "\(appName) 似乎没有安装。")
            return
        }
        NSWorkspace.shared.open(urls, withApplicationAt: app, configuration: NSWorkspace.OpenConfiguration()) { _, error in
            if error != nil { DiagnosticLog.write("打开失败") }
        }
    }

    private func showAlert(_ message: String, detail: String = "") {
        DispatchQueue.main.async {
            let alert = NSAlert()
            alert.messageText = message
            alert.informativeText = detail
            alert.alertStyle = .warning
            alert.runModal()
        }
    }
}

/// 诊断日志默认关闭；调试时显式设置 OPENQUICKDOC_DIAGNOSTICS=1。
/// 不记录路径/文件名/错误详情，不删除或截断已有日志。
enum DiagnosticLog {
    private static let queue = DispatchQueue(label: "oqd.log")
    private static let formatter = ISO8601DateFormatter()

    static func write(_ message: String) {
        guard ProcessInfo.processInfo.environment["OPENQUICKDOC_DIAGNOSTICS"] == "1" else { return }
        queue.async {
            let url = SharedPaths.appSupport.appendingPathComponent("finder-sync.log")
            try? FileManager.default.createDirectory(at: SharedPaths.appSupport, withIntermediateDirectories: true)
            if let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize, size > 512_000 {
                return
            }
            let line = Data("[\(formatter.string(from: Date()))] \(message)\n".utf8)
            let fm = FileManager.default
            if !fm.fileExists(atPath: url.path) {
                // 原子排他创建，避免覆盖并发写入或跟随符号链接。
                let fd = Darwin.open(url.path, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW, 0o600)
                if fd >= 0 { Darwin.close(fd) }
            }
            let fd = Darwin.open(url.path, O_WRONLY | O_APPEND | O_NOFOLLOW | O_NONBLOCK)
            guard fd >= 0 else { return }
            defer { Darwin.close(fd) }
            var info = stat()
            guard fstat(fd, &info) == 0, (info.st_mode & S_IFMT) == S_IFREG else { return }
            guard fchmod(fd, 0o600) == 0 else { return }
            _ = line.withUnsafeBytes { Darwin.write(fd, $0.baseAddress, $0.count) }
        }
    }
}
