import Foundation

/// 扩展 → 主程序 的“在终端中打开”请求。
///
/// 为什么要绕一道：iTerm2 / Terminal 收到文件夹时并不会 cd 过去（实测 iTerm2 只会在主目录开会话），
/// 必须用 AppleScript 让它执行 `cd`。而 Finder 扩展运行在沙盒里，不能发送 Apple Events，
/// 所以扩展只负责拼出 `openquickdoc://open-terminal?app=…&path=…`，由不在沙盒里的主程序执行 AppleScript。
public struct TerminalRequest: Equatable {
    public static let scheme = "openquickdoc"
    public static let host = "open-terminal"

    public let terminal: TerminalType
    public let path: String

    public init(terminal: TerminalType, path: String) {
        self.terminal = terminal
        self.path = path
    }

    /// 终端会把文本作为按键输入；拒绝换行、ESC 等控制字符，避免改变命令边界。
    public static func isSafePath(_ path: String) -> Bool {
        path.hasPrefix("/") && !path.unicodeScalars.contains {
            CharacterSet.controlCharacters.contains($0) || CharacterSet.newlines.contains($0)
        }
    }

    public var url: URL? {
        guard Self.isSafePath(path) else { return nil }
        var c = URLComponents()
        c.scheme = Self.scheme
        c.host = Self.host
        c.queryItems = [
            URLQueryItem(name: "app", value: terminal.bundleIdentifier),
            URLQueryItem(name: "path", value: path),
        ]
        return c.url
    }

    public init?(url: URL) {
        guard let c = URLComponents(url: url, resolvingAgainstBaseURL: false),
              c.scheme == Self.scheme, c.host == Self.host,
              c.user == nil, c.password == nil, c.port == nil,
              c.path.isEmpty, c.fragment == nil,
              let items = c.queryItems, items.count == 2,
              items.filter({ $0.name == "path" }).count == 1,
              items.filter({ $0.name == "app" }).count == 1,
              let path = items.first(where: { $0.name == "path" })?.value, Self.isSafePath(path),
              let app = items.first(where: { $0.name == "app" })?.value,
              let terminal = TerminalType.allCases.first(where: { $0.bundleIdentifier == app })
        else { return nil }
        self.terminal = terminal
        self.path = path
    }

    /// 把路径安全地放进 AppleScript 字符串字面量
    static func appleScriptLiteral(_ s: String) -> String {
        "\"" + s.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"") + "\""
    }

    /// 需要 AppleScript 的终端返回脚本；可直接用“打开文件夹”方式处理的返回 nil
    public var appleScript: String? {
        guard Self.isSafePath(path) else { return nil }
        let p = Self.appleScriptLiteral(path)
        switch terminal {
        case .iterm2:
            // 已有窗口 → 新开标签页；刚启动 → 复用它自动打开的那个窗口，避免出现两个窗口
            return """
            set targetPath to \(p)
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
                tell s to write text "cd " & quoted form of targetPath & " && clear"
            end tell
            """
        case .terminal:
            return """
            set targetPath to \(p)
            tell application id "com.apple.Terminal"
                do script "cd " & quoted form of targetPath
                activate
            end tell
            """
        case .warp, .ghostty:
            return nil
        }
    }
}
