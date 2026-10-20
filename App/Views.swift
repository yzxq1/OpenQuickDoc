import SwiftUI
import AppKit

struct ContentView: View {
    @State private var settings = AppSettings.load()
    @State private var newExt = ""

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            HSplitView {
                typeList.frame(minWidth: 300)
                options.frame(minWidth: 300)
            }
        }
        .frame(minWidth: 660, minHeight: 500)
        // 任一设置变化即保存，替代每个控件各写一个 onChange
        .onChange(of: settings) { newValue in newValue.save() }
    }

    // MARK: 顶栏

    private var header: some View {
        HStack(spacing: 12) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 40, height: 40)
            VStack(alignment: .leading, spacing: 2) {
                Text("OpenQuickDoc").font(.headline)
                Text("Finder 右键新建文件 · 在编辑器中打开 · 拷贝路径")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            Spacer()
            Button { openExtensionSettings() } label: { Label("扩展设置", systemImage: "puzzlepiece.extension") }
            Button { restartFinder() } label: { Label("重启访达", systemImage: "arrow.clockwise") }
        }
        .padding()
    }

    // MARK: 文件类型

    private var typeList: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("右键新建的文件类型").font(.subheadline).bold()
                Spacer()
                Text("拖动排序").font(.caption).foregroundColor(.secondary)
            }
            .padding(.horizontal)
            .padding(.top, 10)

            List {
                ForEach(settings.menuOrder, id: \.self) { id in
                    if let def = FileItemDefinition.find(id) {
                        HStack(spacing: 10) {
                            Toggle("", isOn: enabledBinding(id)).labelsHidden()
                            Image(systemName: def.symbol)
                                .frame(width: 20)
                                .foregroundColor(.accentColor)
                            Text(def.name)
                            Spacer()
                        }
                        .padding(.vertical, 2)
                    }
                }
                .onMove { from, to in settings.menuOrder.move(fromOffsets: from, toOffset: to) }
            }
            .listStyle(.inset(alternatesRowBackgrounds: true))
        }
    }

    private func enabledBinding(_ id: String) -> Binding<Bool> {
        Binding(
            get: { settings.enabledTypes.contains(id) },
            set: { on in
                settings.enabledTypes.removeAll { $0 == id }
                if on { settings.enabledTypes.append(id) }
            }
        )
    }

    // MARK: 选项

    private var options: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                GroupBox(label: Label("菜单样式", systemImage: "list.bullet")) {
                    VStack(alignment: .leading, spacing: 8) {
                        Toggle("收纳为二级菜单（新建文件 ›）", isOn: $settings.useSubmenu)
                        Toggle("新建后直接打开文件（否则在访达中选中）", isOn: $settings.openFileAfterCreation)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(6)
                }

                GroupBox(label: Label("在编辑器中打开", systemImage: "chevron.left.forwardslash.chevron.right")) {
                    VStack(alignment: .leading, spacing: 8) {
                        editorToggle("在 VS Code 中打开", isOn: $settings.openInVSCodeEnabled, editor: .vscode)
                        editorToggle("在 PyCharm 中打开", isOn: $settings.openInPyCharmEnabled, editor: .pycharm)
                        Text("右键文件夹 → 打开该文件夹；空白处右键 → 打开当前目录。")
                            .font(.caption).foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(6)
                }

                GroupBox(label: Label("快捷操作", systemImage: "sparkles")) {
                    VStack(alignment: .leading, spacing: 8) {
                        Toggle("拷贝路径（多选时每行一个）", isOn: $settings.pathCopyEnabled)
                        Toggle("终端直达", isOn: $settings.terminalDirectEnabled)
                        if settings.terminalDirectEnabled {
                            Picker("终端：", selection: $settings.selectedTerminal) {
                                ForEach(TerminalType.allCases) { t in
                                    Text(t.rawValue + (isInstalled([t.bundleIdentifier]) ? "" : "（未安装）")).tag(t)
                                }
                            }
                            .frame(maxWidth: 260)
                            .padding(.leading, 18)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(6)
                }

                GroupBox(label: Label("自定义后缀", systemImage: "plus.square.on.square")) {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            TextField("例如 .yaml", text: $newExt).onSubmit(addExtension)
                            Button("添加", action: addExtension)
                                .disabled(FileItemDefinition.sanitizeExtension(newExt) == nil)
                        }
                        ForEach(settings.customExtensions, id: \.self) { ext in
                            HStack {
                                Text("新建 \(ext.uppercased()) 文件").font(.callout)
                                Spacer()
                                Button { settings.customExtensions.removeAll { $0 == ext } } label: {
                                    Image(systemName: "minus.circle.fill").foregroundColor(.red)
                                }
                                .buttonStyle(.borderless)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(6)
                }

                GroupBox(label: Label("自定义模板", systemImage: "folder.badge.gearshape")) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("在模板目录放入 template.md、template.docx 等，新建时优先使用。")
                            .font(.caption).foregroundColor(.secondary)
                        Button("打开模板文件夹") {
                            SharedPaths.ensureDirectories()
                            NSWorkspace.shared.open(SharedPaths.templates)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(6)
                }

                HStack {
                    Spacer()
                    Button("恢复默认设置") { settings = .defaults }
                }
            }
            .padding()
        }
    }

    private func editorToggle(_ title: String, isOn: Binding<Bool>, editor: EditorTarget) -> some View {
        HStack {
            Toggle(title, isOn: isOn)
            if !isInstalled(editor.bundleIdentifiers) {
                Text("未安装").font(.caption).foregroundColor(.orange)
            }
        }
    }

    private func addExtension() {
        guard let ext = FileItemDefinition.sanitizeExtension(newExt) else { return }
        settings.customExtensions.append(ext)
        settings.normalize()   // 去重、过滤内置类型
        newExt = ""
    }

    // MARK: 工具

    private func isInstalled(_ ids: [String]) -> Bool {
        ids.contains { NSWorkspace.shared.urlForApplication(withBundleIdentifier: $0) != nil }
    }

    private func openExtensionSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.ExtensionsPreferences") {
            NSWorkspace.shared.open(url)
        }
    }

    private func restartFinder() {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/killall")
        task.arguments = ["Finder"]
        try? task.run()
    }
}
