import Foundation

/// 扩展 → 主程序 的终端请求。动作只允许打开目录或启动 Pi，不接受任意命令。
///
/// Finder 扩展在沙盒内不能发送 Apple Events，因此通过 URL 交给主程序执行 AppleScript。
/// 原有 URL 保持不变；启动 Pi 时附加 `action=pi`。
public struct TerminalRequest: Equatable {
    public enum Action: String {
        case shell
        case pi
    }

    public static let scheme = "openquickdoc"
    public static let host = "open-terminal"

    public let terminal: TerminalType
    public let path: String
    public let action: Action

    public init(terminal: TerminalType, path: String, action: Action = .shell) {
        self.terminal = terminal
        self.path = path
        self.action = action
    }

    /// 终端会把文本作为按键输入；拒绝换行、ESC 等控制字符，避免改变命令边界。
    public static func isSafePath(_ path: String) -> Bool {
        path.hasPrefix("/") && !path.unicodeScalars.contains {
            CharacterSet.controlCharacters.contains($0) || CharacterSet.newlines.contains($0)
        }
    }

    private var isSupported: Bool { action == .shell || terminal.supportsPi }

    public var url: URL? {
        guard Self.isSafePath(path), isSupported else { return nil }
        var c = URLComponents()
        c.scheme = Self.scheme
        c.host = Self.host
        c.queryItems = [
            URLQueryItem(name: "app", value: terminal.bundleIdentifier),
            URLQueryItem(name: "path", value: path),
        ]
        if action != .shell {
            c.queryItems?.append(URLQueryItem(name: "action", value: action.rawValue))
        }
        return c.url
    }

    public init?(url: URL) {
        guard let c = URLComponents(url: url, resolvingAgainstBaseURL: false),
              c.scheme == Self.scheme, c.host == Self.host,
              c.user == nil, c.password == nil, c.port == nil,
              c.path.isEmpty, c.fragment == nil,
              let items = c.queryItems,
              items.allSatisfy({ ["app", "path", "action"].contains($0.name) }),
              items.filter({ $0.name == "path" }).count == 1,
              items.filter({ $0.name == "app" }).count == 1,
              items.filter({ $0.name == "action" }).count <= 1,
              let path = items.first(where: { $0.name == "path" })?.value, Self.isSafePath(path),
              let app = items.first(where: { $0.name == "app" })?.value,
              let terminal = TerminalType.allCases.first(where: { $0.bundleIdentifier == app })
        else { return nil }
        let action: Action
        if let item = items.first(where: { $0.name == "action" }) {
            guard let value = item.value, let parsed = Action(rawValue: value) else { return nil }
            action = parsed
        } else {
            action = .shell
        }
        guard action == .shell || terminal.supportsPi else { return nil }
        self.init(terminal: terminal, path: path, action: action)
    }

    /// 把路径安全地放进 AppleScript 字符串字面量。
    static func appleScriptLiteral(_ s: String) -> String {
        "\"" + s.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"") + "\""
    }

    /// 目录用单引号作为一个 Shell 参数；cd 失败时不会启动 Pi。
    public var shellCommand: String? {
        guard Self.isSafePath(path), isSupported else { return nil }
        let quotedPath = "'" + path.replacingOccurrences(of: "'", with: "'\\''") + "'"
        let cd = "cd -- " + quotedPath
        switch action {
        case .pi: return cd + " && pi"
        case .shell: return terminal == .iterm2 ? cd + " && clear" : cd
        }
    }

    /// 需要 AppleScript 的终端返回脚本；可直接用“打开文件夹”方式处理的返回 nil。
    public var appleScript: String? {
        guard let command = shellCommand else { return nil }
        let input = Self.appleScriptLiteral(command)
        switch terminal {
        case .iterm2:
            // 已有窗口 → 新开标签页；刚启动 → 复用它自动打开的那个窗口，避免出现两个窗口。
            return """
            set terminalCommand to \(input)
            set wasRunning to application id "com.googlecode.iterm2" is running
            tell application id "com.googlecode.iterm2"
                activate
                if not wasRunning then
                    repeat 30 times
                        if (count of windows) > 0 then exit repeat
                        delay 0.1
                    end repeat
                end if
                if (count of windows) = 0 then
                    set s to current session of (create window with default profile)
                else if wasRunning then
                    tell current window to set s to current session of (create tab with default profile)
                else
                    set s to current session of current window
                end if
                tell s to write text terminalCommand
            end tell
            """
        case .terminal:
            return """
            set terminalCommand to \(input)
            tell application id "com.apple.Terminal"
                do script terminalCommand
                activate
            end tell
            """
        case .warp, .ghostty:
            return nil
        }
    }
}
