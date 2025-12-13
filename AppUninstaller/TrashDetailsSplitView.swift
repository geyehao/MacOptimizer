import SwiftUI

struct TrashDetailsSplitView: View {
    @ObservedObject var scanner: TrashScanner
    @ObservedObject private var loc = LocalizationManager.shared
    @Environment(\.presentationMode) var presentationMode
    @State private var selectedCategory: String = "trash_on_mac" // Default selection
    @State private var searchText = ""
    @State private var showCleanConfirmation = false
    
    // 模拟的分类数据，根据设计图只有 "mac 上的废纸篓"
    private let categories = ["trash_on_mac"]
    
    var body: some View {
        HStack(spacing: 0) {
            // 左侧侧边栏
            VStack(spacing: 0) {
                // 顶部返回按钮 area
                HStack {
                    Button(action: {
                        presentationMode.wrappedValue.dismiss()
                    }) {
                        HStack(spacing: 4) {
                            Image(systemName: "chevron.left")
                            Text(loc.currentLanguage == .chinese ? "返回" : "Back")
                        }
                        .foregroundColor(.secondaryText)
                    }
                    .buttonStyle(.plain)
                    Spacer()
                }
                .padding(16)
                
                // 全选/取消全选 (设计图左上角有个 "取消全选" 按钮)
                HStack {
                    Button(loc.L("deselectAll")) {
                        // TODO: Implement selection logic
                    }
                    .font(.caption)
                    .foregroundColor(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.white.opacity(0.1))
                    .cornerRadius(4)
                    
                    Spacer()
                    
                    Text(loc.currentLanguage == .chinese ? "排序方式按 大小" : "Sort by Size")
                        .font(.caption)
                        .foregroundColor(.secondaryText)
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 8)
                
                // 分类列表
                ScrollView {
                    VStack(spacing: 2) {
                        ForEach(categories, id: \.self) { category in
                            categoryRow(title: loc.L(category), size: scanner.formattedTotalSize, isSelected: selectedCategory == category)
                                .onTapGesture {
                                    selectedCategory = category
                                }
                        }
                    }
                    .padding(.horizontal, 8)
                }
            }
            .frame(width: 260)
            .background(Color.black.opacity(0.2)) // Darker sidebar
            
            // 右侧文件列表
            VStack(spacing: 0) {
                // 顶部工具栏 (搜索等)
                HStack {
                    Text(loc.L("trash"))
                        .font(.headline)
                        .foregroundColor(.white)
                    
                    Spacer()
                    
                    // 搜索框
                    HStack {
                        Image(systemName: "magnifyingglass")
                            .foregroundColor(.secondaryText)
                        TextField(loc.currentLanguage == .chinese ? "搜索" : "Search", text: $searchText)
                            .textFieldStyle(.plain)
                            .foregroundColor(.white)
                    }
                    .padding(6)
                    .background(Color.white.opacity(0.1))
                    .cornerRadius(6)
                    .frame(width: 200)
                    
                    // 助手按钮 (Mock)
                    Button(action: {}) {
                        HStack {
                            Circle().fill(Color.green).frame(width: 6, height: 6)
                            Text(loc.currentLanguage == .chinese ? "助手" : "Assistant")
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(Color.white.opacity(0.1))
                        .cornerRadius(12)
                    }
                    .buttonStyle(.plain)
                }
                .padding(12)
                .background(Color.white.opacity(0.05))
                
                // 列表标题区域
                VStack(alignment: .leading, spacing: 4) {
                    Text(loc.L("trash_on_mac"))
                        .font(.title2)
                        .bold()
                        .foregroundColor(.white)
                    Text(loc.currentLanguage == .chinese ? "系统废纸篓文件夹存储先前删除的项目，但是它们仍然占用磁盘空间。" : "System Trash folder stores deleted items which still take up space.")
                        .font(.caption)
                        .foregroundColor(.secondaryText)
                }
                .padding(20)
                .frame(maxWidth: .infinity, alignment: .leading)
                
                // 排序栏
                HStack {
                    Spacer()
                    Text(loc.currentLanguage == .chinese ? "排序方式按 大小" : "Sort by Size")
                        .font(.caption)
                        .foregroundColor(.secondaryText)
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 8)
                
                // 文件列表
                List {
                    ForEach(scanner.items) { item in
                        TrashDetailRow(item: item)
                            .listRowInsets(EdgeInsets(top: 4, leading: 20, bottom: 4, trailing: 20))
                            .listRowBackground(Color.clear)
                            .listRowSeparator(.hidden)
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
                
                // 底部清理栏
                HStack {
                    Spacer()
                    // 圆形清理按钮 (带文字)
                    Button(action: {
                        showCleanConfirmation = true
                    }) {
                        ZStack {
                            Circle()
                                .stroke(LinearGradient(colors: [Color.blue.opacity(0.5), Color.blue], startPoint: .top, endPoint: .bottom), lineWidth: 2)
                                .frame(width: 70, height: 70)
                                .background(Circle().fill(Color.blue.opacity(0.2)))
                            
                            Text(loc.L("empty_trash")) // "清倒"
                                .font(.system(size: 14, weight: .medium))
                                .foregroundColor(.white)
                        }
                    }
                    .buttonStyle(.plain)
                    
                    Text(scanner.formattedTotalSize)
                        .font(.title3)
                        .foregroundColor(.secondaryText)
                        .padding(.leading, 10)
                    
                    Spacer()
                }
                .padding(.vertical, 10)
                .background(Color.black.opacity(0.3))
            }
        }
        .confirmationDialog(loc.L("empty_trash"), isPresented: $showCleanConfirmation) {
            Button(loc.L("empty_trash"), role: .destructive) {
                Task {
                   _ = await scanner.emptyTrash()
                   // Back to main view or show finished
                   // 这里需要处理状态，可能要把 showCleaningFinished 状态提升或者通过 callback
                   // 简化起见，直接 dismiss? 或者 scanner 会触发 finished page
                }
            }
            Button(loc.L("cancel"), role: .cancel) {}
        } message: {
            Text(loc.currentLanguage == .chinese ? "此操作不可撤销，所有文件将被永久删除。" : "This cannot be undone.")
        }
    }
    
    private func categoryRow(title: String, size: String, isSelected: Bool) -> some View {
        HStack {
            Image(systemName: "checkmark.circle.fill") // Mock selection state
                .foregroundColor(.blue)
            Image(systemName: "trash")
                .foregroundColor(.white)
            Text(title)
                .foregroundColor(.white)
                .font(.system(size: 13))
            Spacer()
            Text(size)
                .font(.caption)
                .foregroundColor(.white.opacity(0.7))
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 12)
        .background(isSelected ? Color.white.opacity(0.1) : Color.clear)
        .cornerRadius(6)
    }
}

struct TrashDetailRow: View { // Renamed from TrashItemRow to avoid conflict if in same file context, but previously it was inside TrashView scope or global? Swift allows file private or global. TrashItemRow was global in previous file snippet.
    // Let's reuse TrashItemRow but modify it to match design Img 1 (Checkbox style)
    let item: TrashItem
    
    var body: some View {
        HStack {
            Image(systemName: "checkmark.circle.fill") // Checkbox
                .foregroundColor(.blue)
                .font(.system(size: 14))
            
            // Icon
            Image(nsImage: NSWorkspace.shared.icon(forFile: item.url.path))
                .resizable()
                .frame(width: 24, height: 24)
            
            Text(item.name)
                .font(.system(size: 13))
                .foregroundColor(.white)
                .lineLimit(1)
            
            Spacer()
            
            Text(item.formattedSize)
                .font(.system(size: 12))
                .foregroundColor(.white)
        }
        .padding(.vertical, 4)
    }
}
