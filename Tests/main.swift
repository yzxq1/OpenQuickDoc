import Foundation

// 直接测试 Shared/ 中的真实代码（Config.swift + FileFactory.swift）
// 运行：./test.sh

var failures = 0
func check(_ cond: @autoclosure () -> Bool, _ msg: String, line: Int = #line) {
    if cond() { print("  ✅ \(msg)") } else { print("  ❌ \(msg)  (line \(line))"); failures += 1 }
}

let fm = FileManager.default
let tmp = fm.temporaryDirectory.appendingPathComponent("oqd-test-\(UUID().uuidString)")
try! fm.createDirectory(at: tmp, withIntermediateDirectories: true)
defer { try? fm.removeItem(at: tmp) }

let resources = URL(fileURLWithPath: CommandLine.arguments[1])  // Resources 目录
let emptyTemplates = tmp.appendingPathComponent("no-templates")

print("① 沙盒路径：配置必须落在真实家目录，而不是容器目录")
check(!SharedPaths.settingsFile.path.contains("/Library/Containers/"), "settingsFile = \(SharedPaths.settingsFile.path)")
check(SharedPaths.realHome.path == NSHomeDirectoryForUser(NSUserName()), "realHome 与系统记录一致")

print("② 旧版配置兼容：缺字段 / 未知终端值 不应导致整份配置被重置")
let oldJSON = #"{"enabledTypes":["md","docx"],"menuOrder":["md","docx","txt"],"selectedTerminal":"VS Code","useSubmenu":true}"#
let s = AppSettings.decode(Data(oldJSON.utf8))
check(s != nil, "旧配置可以解码")
check(s?.enabledTypes == ["md", "docx"], "保留用户的 enabledTypes")
check(s?.useSubmenu == true, "保留用户的 useSubmenu")
check(s?.selectedTerminal == .terminal, "已删除的终端值回落为系统终端")
check(s?.openInVSCodeEnabled == AppSettings.defaults.openInVSCodeEnabled, "新增字段取默认值")
check(s?.menuOrder.count == FileItemDefinition.all.count, "新增的文件类型被补进 menuOrder")
check(s?.menuOrder.prefix(3) == ["md", "docx", "txt"], "保留用户原有排序")

print("③ 配置读写往返")
let cfg = tmp.appendingPathComponent("settings.json")
var s2 = AppSettings.defaults
s2.enabledTypes = ["py"]; s2.selectedTerminal = .iterm2
s2.save(to: cfg)
check(AppSettings.load(from: cfg) == s2, "save → load 结果一致")
check(AppSettings.load(from: tmp.appendingPathComponent("nope.json")) == .defaults, "文件不存在时返回默认值（且不写盘）")
check(!fm.fileExists(atPath: tmp.appendingPathComponent("nope.json").path), "load 无写入副作用")

print("④ 防重名")
let md = FileItemDefinition.find("md")!
let names = (0..<3).map { _ in try! FileFactory.create(md, in: tmp, templatesDir: emptyTemplates).lastPathComponent }
check(names == ["新建 Markdown 文件.md", "新建 Markdown 文件 2.md", "新建 Markdown 文件 3.md"], "依次生成 \(names)")
let blank = FileItemDefinition.find("blank")!
let b1 = try! FileFactory.create(blank, in: tmp, templatesDir: emptyTemplates).lastPathComponent
let b2 = try! FileFactory.create(blank, in: tmp, templatesDir: emptyTemplates).lastPathComponent
check([b1, b2] == ["新建空白文件", "新建空白文件 2"], "无扩展名文件 \([b1, b2])")

print("⑤ 每种类型都能创建，内容符合预期")
let resBundle = Bundle(url: resources) ?? Bundle.main
for def in FileItemDefinition.all {
    let dir = tmp.appendingPathComponent("types-\(def.id)")
    try! fm.createDirectory(at: dir, withIntermediateDirectories: true)
    do {
        let url = try FileFactory.create(def, in: dir, templatesDir: emptyTemplates, bundle: resBundle)
        let data = try Data(contentsOf: url)
        switch def.id {
        case "docx", "xlsx", "pptx":
            check(data.count > 1000 && data.prefix(2) == Data([0x50, 0x4B]), "\(def.id): 来自内置模板 (\(data.count) B, ZIP 头)")
        case "csv":
            check(data == Data([0xEF, 0xBB, 0xBF]), "csv: 写入 UTF-8 BOM")
        case "rtf":
            check(String(decoding: data, as: UTF8.self).hasPrefix("{\\rtf1"), "rtf: 合法 RTF 头")
        case "json":
            check((try? JSONSerialization.jsonObject(with: data)) != nil, "json: 是合法 JSON")
        case "sh":
            let perm = (try fm.attributesOfItem(atPath: url.path)[.posixPermissions] as? Int) ?? 0
            check(perm == 0o755, "sh: 权限 755")
        default:
            check(fm.fileExists(atPath: url.path), "\(def.id): 已创建 \(url.lastPathComponent)")
        }
    } catch {
        check(false, "\(def.id): 创建失败 \(error)")
    }
}

print("⑥ 自定义模板优先")
let tdir = tmp.appendingPathComponent("tpl")
try! fm.createDirectory(at: tdir, withIntermediateDirectories: true)
try! "MY TEMPLATE".write(to: tdir.appendingPathComponent("template.md"), atomically: true, encoding: .utf8)
let out = tmp.appendingPathComponent("tpl-out")
try! fm.createDirectory(at: out, withIntermediateDirectories: true)
let made = try! FileFactory.create(md, in: out, templatesDir: tdir)
check((try? String(contentsOf: made, encoding: .utf8)) == "MY TEMPLATE", "使用了 template.md")

print("⑥b 自定义后缀")
let raw = #"{"customExtensions":[".YAML"," toml ","yaml","md","../x",""]}"#
let cs = AppSettings.decode(Data(raw.utf8))!
check(cs.customExtensions == ["yaml", "toml"], "规范化/去重/过滤内置与非法: \(cs.customExtensions)")
let y = try! FileFactory.create(cs.customDefinitions[0], in: tmp, templatesDir: emptyTemplates)
check(y.lastPathComponent == "新建 YAML 文件.yaml", "创建 \(y.lastPathComponent)")

print("⑦ Python 骨架可被解释器解析")
let py = try! FileFactory.create(FileItemDefinition.find("py")!, in: tmp, templatesDir: emptyTemplates)
let p = Process()
p.executableURL = URL(fileURLWithPath: "/usr/bin/env")
p.arguments = ["python3", "-m", "py_compile", py.path]
try! p.run(); p.waitUntilExit()
check(p.terminationStatus == 0, "py_compile 通过")

print("⑧ 终端请求 URL 往返（含空格、引号、中文路径）")
let weird = "/Users/x/My \"Docs\"/中文 目录"
for t in TerminalType.allCases {
    let r = TerminalRequest(terminal: t, path: weird)
    check(r.url.flatMap(TerminalRequest.init(url:)) == r, "\(t.rawValue): URL 编解码一致")
}
check(TerminalRequest(url: URL(string: "openquickdoc://open-terminal?app=x&path=relative")!) == nil, "拒绝相对路径")
check(TerminalRequest(url: URL(string: "https://open-terminal?path=/a")!) == nil, "拒绝其他 scheme")
let script = TerminalRequest(terminal: .iterm2, path: weird).appleScript!
var compileErr: NSDictionary?
check(NSAppleScript(source: script)!.compileAndReturnError(&compileErr) && compileErr == nil, "iTerm2 AppleScript 可编译")
check(script.contains(#"\"Docs\""#), "路径中的引号已转义")

print(failures == 0 ? "\n🎉 全部通过" : "\n💥 \(failures) 项失败")
exit(failures == 0 ? 0 : 1)
