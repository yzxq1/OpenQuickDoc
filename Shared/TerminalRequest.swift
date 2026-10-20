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

    public var url: URL? {
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
              let items = c.queryItems,
              let path = items.first(where: { $0.name == "path" })?.value, path.hasPrefix("/"),
              let app = items.first(where: { $0.name == "app" })?.value
        else { return nil }
        self.terminal = TerminalType.allCases.first { $0.bundleIdentifier == app } ?? .terminal
        self.path = path
    }

    /// 把路径安全地放进 AppleScript 字符串字面量
    static func appleScriptLiteral(_ s: String) -> String {
        "\"" + s.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"") + "\""
    }

    /// 需要 AppleScript 的终端返回脚本；可直接用“打开文件夹”方式处理的返回 nil
    public var appleScript: String? {
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
