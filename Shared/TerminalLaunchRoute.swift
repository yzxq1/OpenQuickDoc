import AppKit

/// 固定由 Finder 扩展所在应用处理请求，避免同 Bundle ID 的旧副本接收 URL。
public struct TerminalLaunchRoute {
    public let url: URL
    public let applicationURL: URL
    public let configuration: NSWorkspace.OpenConfiguration

    public init?(request: TerminalRequest, extensionURL: URL) {
        let plugins = extensionURL.deletingLastPathComponent()
        let contents = plugins.deletingLastPathComponent()
        let application = contents.deletingLastPathComponent()
        guard extensionURL.isFileURL, extensionURL.pathExtension == "appex",
              plugins.lastPathComponent == "PlugIns", contents.lastPathComponent == "Contents",
              application.pathExtension == "app", let url = request.url else { return nil }
        self.url = url
        self.applicationURL = application
        let config = NSWorkspace.OpenConfiguration()
        config.activates = false
        // 仅指定应用 URL 仍可能复用同 Bundle ID 的旧进程；每个请求启动配套的新实例。
        config.createsNewApplicationInstance = true
        self.configuration = config
    }
}
