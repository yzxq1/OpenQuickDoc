import Foundation

// MARK: - 终端类型

public enum TerminalType: String, Codable, CaseIterable, Identifiable {
    case terminal = "终端 (系统自带)"
    case iterm2 = "iTerm2"
    case warp = "Warp"
    case ghostty = "Ghostty"

    public var id: String { rawValue }

    public var bundleIdentifier: String {
        switch self {
        case .terminal: return "com.apple.Terminal"
        case .iterm2:   return "com.googlecode.iterm2"
        case .warp:     return "dev.warp.Warp-Stable"
        case .ghostty:  return "com.mitchellh.ghostty"
        }
    }

    /// 兼容旧配置中已删除的取值（如 "VS Code"），未知值回落到系统终端
    public init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = TerminalType(rawValue: raw) ?? .terminal
    }
}

// MARK: - 编辑器（文件夹直达）

public enum EditorTarget: String, CaseIterable {
    case vscode
    case pycharm

    public var title: String {
        switch self {
        case .vscode:  return "在 VS Code 中打开"
        case .pycharm: return "在 PyCharm 中打开"
        }
    }

    /// 按优先级尝试的 Bundle ID
    public var bundleIdentifiers: [String] {
        switch self {
        case .vscode:  return ["com.microsoft.VSCode", "com.microsoft.VSCodeInsiders"]
        case .pycharm: return ["com.jetbrains.pycharm", "com.jetbrains.pycharm.ce"]
        }
    }

    public var fallbackSymbol: String {
        switch self {
        case .vscode:  return "chevron.left.forwardslash.chevron.right"
        case .pycharm: return "curlybraces.square"
        }
    }
}

// MARK: - 文件类型定义

public struct FileItemDefinition: Identifiable, Equatable {
    public let id: String
    /// 设置界面里显示的名称
    public let name: String
    /// 右键菜单标题，同时也是新文件的基础名（与原版习惯一致：“新建 Markdown 文件.md”）
    public let title: String
    public let ext: String
    /// SF Symbols 名称（系统内置矢量图标，无第三方素材版权问题）
    public let symbol: String
    public let bundledTemplate: String?
    public let isExecutable: Bool

    public init(id: String, name: String, title: String, ext: String, symbol: String,
                bundledTemplate: String? = nil, isExecutable: Bool = false) {
        self.id = id; self.name = name; self.title = title; self.ext = ext
        self.symbol = symbol; self.bundledTemplate = bundledTemplate; self.isExecutable = isExecutable
    }

    public static let all: [FileItemDefinition] = [
        .init(id: "txt",   name: "文本文档 (.txt)",      title: "新建 TXT 文件",          ext: "txt",  symbol: "doc.plaintext"),
        .init(id: "md",    name: "Markdown (.md)",      title: "新建 Markdown 文件",     ext: "md",   symbol: "text.alignleft"),
        .init(id: "docx",  name: "Word 文档 (.docx)",    title: "新建 Word 文档",         ext: "docx", symbol: "doc.richtext", bundledTemplate: "blank.docx"),
        .init(id: "xlsx",  name: "Excel 表格 (.xlsx)",   title: "新建 Excel 表格",        ext: "xlsx", symbol: "tablecells", bundledTemplate: "blank.xlsx"),
        .init(id: "csv",   name: "CSV 表格 (.csv)",      title: "新建 CSV 表格",          ext: "csv",  symbol: "list.bullet.rectangle"),
        .init(id: "pptx",  name: "PPT 演示文稿 (.pptx)", title: "新建 PowerPoint 演示文稿", ext: "pptx", symbol: "rectangle.on.rectangle", bundledTemplate: "blank.pptx"),
        .init(id: "json",  name: "JSON 文件 (.json)",    title: "新建 JSON 文件",         ext: "json", symbol: "curlybraces"),
        .init(id: "blank", name: "空白文件",             title: "新建空白文件",            ext: "",     symbol: "doc"),
        .init(id: "py",    name: "Python 脚本 (.py)",    title: "新建 Python 文件",       ext: "py",   symbol: "chevron.left.forwardslash.chevron.right"),
        .init(id: "html",  name: "HTML 网页 (.html)",    title: "新建 HTML 文件",         ext: "html", symbol: "globe"),
        .init(id: "sh",    name: "Shell 脚本 (.sh)",     title: "新建 Shell 文件",        ext: "sh",   symbol: "terminal", isExecutable: true),
        .init(id: "rtf",   name: "富文本 (.rtf)",        title: "新建 RTF 文件",          ext: "rtf",  symbol: "textformat"),
    ]

    public static func find(_ id: String) -> FileItemDefinition? {
        all.first { $0.id == id }
    }

    /// 用户自定义后缀（如 yaml）对应的类型
    public static func custom(_ ext: String) -> FileItemDefinition {
        .init(id: "custom.\(ext)", name: ".\(ext)", title: "新建 \(ext.uppercased()) 文件", ext: ext, symbol: "doc.badge.plus")
    }

    /// 规范化用户输入的后缀：去掉前导点和空格、转小写；非法返回 nil
    public static func sanitizeExtension(_ raw: String) -> String? {
        var s = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        while s.hasPrefix(".") { s.removeFirst() }
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_."))
        guard !s.isEmpty, s.count <= 20, s.unicodeScalars.allSatisfy(allowed.contains), !s.hasSuffix(".") else { return nil }
        return s
    }
}

// MARK: - 共享路径

public enum SharedPaths {
    /// 用户真实的家目录。
    /// 注意：沙盒内的 Finder 扩展调用 `homeDirectoryForCurrentUser` / `NSHomeDirectory()`
    /// 会得到 ~/Library/Containers/<id>/Data，导致与主 App 读写的不是同一份配置。
    /// 因此通过 getpwuid 获取真实路径（扩展的 entitlements 已放行 /Users/ 读写）。
    public static var realHome: URL {
        if let pw = getpwuid(getuid()), let dir = pw.pointee.pw_dir {
            return URL(fileURLWithPath: String(cString: dir), isDirectory: true)
        }
        return FileManager.default.homeDirectoryForCurrentUser
    }

    public static var appSupport: URL {
        realHome.appendingPathComponent("Library/Application Support/OpenQuickDoc", isDirectory: true)
    }

    public static var templates: URL { appSupport.appendingPathComponent("Templates", isDirectory: true) }
    public static var settingsFile: URL { appSupport.appendingPathComponent("settings.json") }

    public static func ensureDirectories() {
        let fm = FileManager.default
        try? fm.createDirectory(at: templates, withIntermediateDirectories: true)
        let readme = templates.appendingPathComponent("README.txt")
        if !fm.fileExists(atPath: readme.path) {
            let note = """
            【OpenQuickDoc 自定义模板】
            在此目录放入 template.<扩展名> 文件，右键新建该类型时会复制它：
              template.md / template.py / template.sh / template.docx / template.xlsx ...
              blank  —— 用于「空白文件」
            """
            try? note.write(to: readme, atomically: true, encoding: .utf8)
        }
    }
}

// MARK: - 设置

public struct AppSettings: Codable, Equatable {
    public var enabledTypes: [String]
    public var menuOrder: [String]
    public var pathCopyEnabled: Bool
    public var terminalDirectEnabled: Bool
    public var openInVSCodeEnabled: Bool
    public var openInPyCharmEnabled: Bool
    public var selectedTerminal: TerminalType
    public var useSubmenu: Bool
    public var openFileAfterCreation: Bool
    /// 自定义后缀（不含点），按添加顺序排在内置类型之后
    public var customExtensions: [String]

    public static let defaults = AppSettings(
        enabledTypes: ["txt", "md", "docx", "xlsx", "pptx", "py"],
        menuOrder: FileItemDefinition.all.map(\.id),
        pathCopyEnabled: true,
        terminalDirectEnabled: true,
        openInVSCodeEnabled: true,
        openInPyCharmEnabled: true,
        selectedTerminal: .terminal,
        useSubmenu: true,           // 与原版一致：新建项收在“新建文件 ›”里，不占一级菜单
        openFileAfterCreation: false,
        customExtensions: []
    )

    public init(enabledTypes: [String], menuOrder: [String], pathCopyEnabled: Bool,
                terminalDirectEnabled: Bool, openInVSCodeEnabled: Bool, openInPyCharmEnabled: Bool,
                selectedTerminal: TerminalType, useSubmenu: Bool, openFileAfterCreation: Bool,
                customExtensions: [String]) {
        self.customExtensions = customExtensions
        self.enabledTypes = enabledTypes
        self.menuOrder = menuOrder
        self.pathCopyEnabled = pathCopyEnabled
        self.terminalDirectEnabled = terminalDirectEnabled
        self.openInVSCodeEnabled = openInVSCodeEnabled
        self.openInPyCharmEnabled = openInPyCharmEnabled
        self.selectedTerminal = selectedTerminal
        self.useSubmenu = useSubmenu
        self.openFileAfterCreation = openFileAfterCreation
    }

    /// 宽容解码：缺失字段取默认值，而不是整份配置解码失败后被重置。
    /// 这样以后新增设置项时，用户已有配置不会丢失。
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = AppSettings.defaults
        enabledTypes          = try c.decodeIfPresent([String].self, forKey: .enabledTypes) ?? d.enabledTypes
        menuOrder             = try c.decodeIfPresent([String].self, forKey: .menuOrder) ?? d.menuOrder
        pathCopyEnabled       = try c.decodeIfPresent(Bool.self, forKey: .pathCopyEnabled) ?? d.pathCopyEnabled
        terminalDirectEnabled = try c.decodeIfPresent(Bool.self, forKey: .terminalDirectEnabled) ?? d.terminalDirectEnabled
        openInVSCodeEnabled   = try c.decodeIfPresent(Bool.self, forKey: .openInVSCodeEnabled) ?? d.openInVSCodeEnabled
        openInPyCharmEnabled  = try c.decodeIfPresent(Bool.self, forKey: .openInPyCharmEnabled) ?? d.openInPyCharmEnabled
        selectedTerminal      = try c.decodeIfPresent(TerminalType.self, forKey: .selectedTerminal) ?? d.selectedTerminal
        useSubmenu            = try c.decodeIfPresent(Bool.self, forKey: .useSubmenu) ?? d.useSubmenu
        openFileAfterCreation = try c.decodeIfPresent(Bool.self, forKey: .openFileAfterCreation) ?? d.openFileAfterCreation
        customExtensions      = try c.decodeIfPresent([String].self, forKey: .customExtensions) ?? d.customExtensions
        normalize()
    }

    /// 去掉未知 id，并把新增的类型补到排序末尾
    public mutating func normalize() {
        let known = Set(FileItemDefinition.all.map(\.id))
        var seen = Set<String>()
        menuOrder = menuOrder.filter { known.contains($0) && seen.insert($0).inserted }
        for def in FileItemDefinition.all where !seen.contains(def.id) {
            menuOrder.append(def.id)
        }
        enabledTypes = enabledTypes.filter { known.contains($0) }

        let builtinExts = Set(FileItemDefinition.all.map(\.ext))
        var seenExt = Set<String>()
        customExtensions = customExtensions
            .compactMap(FileItemDefinition.sanitizeExtension)
            .filter { !builtinExts.contains($0) && seenExt.insert($0).inserted }
    }

    /// 按菜单顺序返回已启用的内置类型
    public var orderedEnabledDefinitions: [FileItemDefinition] {
        let enabled = Set(enabledTypes)
        return menuOrder.filter { enabled.contains($0) }.compactMap(FileItemDefinition.find)
    }

    public var customDefinitions: [FileItemDefinition] {
        customExtensions.map(FileItemDefinition.custom)
    }

    public static func decode(_ data: Data) -> AppSettings? {
        try? JSONDecoder().decode(AppSettings.self, from: data)
    }

    /// 读取配置。只读，不产生写入副作用（右键菜单每次弹出都会调用）。
    public static func load(from url: URL = SharedPaths.settingsFile) -> AppSettings {
        guard let data = try? Data(contentsOf: url), let s = decode(data) else { return defaults }
        return s
    }

    public func save(to url: URL = SharedPaths.settingsFile) {
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let data = try? encoder.encode(self) {
            try? data.write(to: url, options: .atomic)
        }
    }
}
