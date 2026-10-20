import Foundation

/// 新建文件的纯逻辑，与 Finder / UI 无关，便于单元测试。
public enum FileFactory {

    public enum CreateError: Error {
        case noAvailableName
    }

    /// 生成不重名的目标路径（沿用原版规则）：
    /// 新建 Markdown 文件.md → 新建 Markdown 文件 2.md → …，最多尝试 999 个
    public static func uniqueURL(for def: FileItemDefinition, in dir: URL,
                                 fileManager fm: FileManager = .default) -> URL? {
        let base = def.title
        func name(_ n: Int) -> String {
            let stem = n == 1 ? base : "\(base) \(n)"
            return def.ext.isEmpty ? stem : "\(stem).\(def.ext)"
        }
        for n in 1..<1000 {
            let url = dir.appendingPathComponent(name(n))
            if !fm.fileExists(atPath: url.path) { return url }
        }
        return nil
    }

    /// 内置的骨架内容（没有自定义模板、也没有内置二进制模板时使用）
    public static func defaultContent(for def: FileItemDefinition, date: Date = Date()) -> Data {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd HH:mm"
        let now = f.string(from: date)

        let text: String
        switch def.ext {
        case "md":
            text = "# \n\n> 创建于 \(now)\n\n"
        case "py":
            text = """
            #!/usr/bin/env python3
            \"\"\"Created on \(now)\"\"\"


            def main() -> None:
                pass


            if __name__ == "__main__":
                main()

            """
        case "sh":
            text = "#!/usr/bin/env bash\nset -euo pipefail\n\n"
        case "json":
            text = "{}\n"
        case "html":
            text = """
            <!DOCTYPE html>
            <html lang="zh-CN">
            <head>
              <meta charset="UTF-8">
              <meta name="viewport" content="width=device-width, initial-scale=1.0">
              <title></title>
            </head>
            <body>

            </body>
            </html>

            """
        case "rtf":
            // 空 .rtf 文件会被 TextEdit 当成纯文本，这里给一个最小合法 RTF
            text = "{\\rtf1\\ansi\\ansicpg936\\deff0{\\fonttbl{\\f0 PingFangSC-Regular;}}\\f0\\fs24 }\n"
        case "csv":
            // UTF-8 BOM，防止 Excel 打开中文乱码
            return Data([0xEF, 0xBB, 0xBF])
        default:
            text = ""
        }
        return Data(text.utf8)
    }

    /// 创建文件。模板优先级：用户自定义模板 > 内置二进制模板 > 骨架内容
    @discardableResult
    public static func create(_ def: FileItemDefinition,
                              in dir: URL,
                              templatesDir: URL = SharedPaths.templates,
                              bundle: Bundle = .main,
                              fileManager fm: FileManager = .default) throws -> URL {
        guard let target = uniqueURL(for: def, in: dir, fileManager: fm) else {
            throw CreateError.noAvailableName
        }

        let userTemplate = templatesDir.appendingPathComponent(def.ext.isEmpty ? "blank" : "template.\(def.ext)")
        if fm.fileExists(atPath: userTemplate.path) {
            try fm.copyItem(at: userTemplate, to: target)
        } else if let name = def.bundledTemplate,
                  let path = bundle.path(forResource: name, ofType: nil) {
            try fm.copyItem(atPath: path, toPath: target.path)
        } else {
            // withoutOverwriting：极端并发下也不会覆盖已有文件
            try defaultContent(for: def).write(to: target, options: .withoutOverwriting)
        }

        if def.isExecutable {
            try? fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: target.path)
        }
        return target
    }
}
