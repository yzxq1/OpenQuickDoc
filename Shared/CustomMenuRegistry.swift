import Foundation

/// Finder 序列化菜单后只保留 tag。为每种自定义类型分配稳定编号，
/// 避免菜单展示后设置发生变化，点击旧菜单却创建另一种文件。
public struct CustomMenuRegistry {
    private var nextTag: Int
    private var tags: [String: Int] = [:]
    private var definitions: [Int: FileItemDefinition] = [:]

    public init(startTag: Int = 3000) { nextTag = startTag }

    public mutating func tag(for definition: FileItemDefinition) -> Int {
        if let tag = tags[definition.id] { return tag }
        let tag = nextTag
        nextTag += 1
        tags[definition.id] = tag
        definitions[tag] = definition
        return tag
    }

    public func definition(for tag: Int) -> FileItemDefinition? { definitions[tag] }
}
