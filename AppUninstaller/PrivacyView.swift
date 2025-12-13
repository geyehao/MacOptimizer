import SwiftUI

struct PrivacyView: View {
    @Binding var selectedModule: AppModule
    @StateObject private var service = PrivacyScannerService()
    @ObservedObject private var loc = LocalizationManager.shared
    
    // UI State
    @State private var scanState: PrivacyScanState = .initial
    @State private var pulse = false
    @State private var cleaningProgress: Double = 0
    @State private var cleanedSize: Int64 = 0
    @State private var showPermissionAlert = false
    @State private var showingCloseBrowserAlert = false
    
    // Selection State
    @State private var selectedSidebarItem: SidebarCategory = .permissions
    
    enum SidebarCategory: Hashable, Equatable {
        case permissions
        case recentItems
        case wifi
        case chat
        case browser(BrowserType)
        
        static func == (lhs: SidebarCategory, rhs: SidebarCategory) -> Bool {
            switch (lhs, rhs) {
            case (.permissions, .permissions): return true
            case (.recentItems, .recentItems): return true
            case (.wifi, .wifi): return true
            case (.chat, .chat): return true
            case (.browser(let b1), .browser(let b2)): return b1 == b2
            default: return false
            }
        }
        
        func hash(into hasher: inout Hasher) {
            switch self {
            case .permissions: hasher.combine(0)
            case .recentItems: hasher.combine(1)
            case .wifi: hasher.combine(2)
            case .chat: hasher.combine(3)
            case .browser(let b): 
                hasher.combine(4)
                hasher.combine(b)
            }
        }
        
        var title: String {
            switch self {
            case .permissions: return LocalizationManager.shared.currentLanguage == .chinese ? "应用权限" : "Application Permissions"
            case .recentItems: return LocalizationManager.shared.currentLanguage == .chinese ? "最近项目列表" : "Recent Items List"
            case .wifi: return LocalizationManager.shared.currentLanguage == .chinese ? "Wi-Fi 网络" : "Wi-Fi Networks"
            case .chat: return LocalizationManager.shared.currentLanguage == .chinese ? "聊天信息" : "Chat Data"
            case .browser(let b): return b.rawValue
            }
        }
        
        var icon: String {
            switch self {
            case .permissions: return "lock.shield"
            case .recentItems: return "clock"
            case .wifi: return "wifi"
            case .chat: return "message"
            case .browser(let b): return b.icon
            }
        }
    }
    
    var body: some View {
        ZStack {
            // 背景渐变
            AppModule.privacy.backgroundGradient
                .ignoresSafeArea()
            
            VStack(spacing: 0) {
                // 顶部标题 - 仅在非初始状态或根据设计需求显示
                if scanState != .initial {
                    headerView
                }
                
                // 主要内容区域
                contentView
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .onAppear {
            // If the service has already scanned and has items, go to completed state
            if !service.privacyItems.isEmpty && scanState == .initial {
                scanState = .completed
                selectFirstAvailableCategory()
            }
        }
        .alert(loc.currentLanguage == .chinese ? "关闭浏览器" : "Close Browsers", isPresented: $showingCloseBrowserAlert) {
            Button(loc.currentLanguage == .chinese ? "关闭并清理" : "Close and Clean", role: .destructive) {
                Task {
                    await performClean(closeBrowsers: true)
                }
            }
            Button(loc.L("cancel"), role: .cancel) { }
        } message: {
            Text(loc.currentLanguage == .chinese ? "检测到浏览器正在运行，清理前需要将其关闭以确保数据被彻底清除。" : "Browsers are running. They need to be closed to ensure data is completely removed.")
        }
    }
    
    // MARK: - 头部视图
    private var headerView: some View {
        HStack {
            Spacer()
            // 可以在右上角添加"助手"按钮等，参考设计图
            Button(action: {}) {
                HStack(spacing: 4) {
                    Circle().fill(Color.green).frame(width: 8, height: 8)
                    Text(loc.currentLanguage == .chinese ? "助手" : "Assistant")
                        .font(.caption)
                        .foregroundColor(.white)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Color.black.opacity(0.3))
                .cornerRadius(12)
            }
            .buttonStyle(.plain)
        }
        .padding()
    }
    
    // MARK: - 内容视图路由
    @ViewBuilder
    private var contentView: some View {
        switch scanState {
        case .initial:
            initialView
        case .scanning:
            scanningView
        case .completed:
            resultsView
        case .cleaning:
            cleaningView
        case .finished:
            finishedView
        }
    }
    
    // MARK: - 1. 初始页面 (Initial)
    private var initialView: some View {
        VStack(spacing: 40) {
            Spacer()
            
            // 标题文本
            VStack(alignment: .leading, spacing: 16) {
                Text(loc.currentLanguage == .chinese ? "隐私" : "Privacy")
                    .font(.system(size: 32, weight: .bold))
                    .foregroundColor(.white)
                
                Text(loc.currentLanguage == .chinese ? "立即移除浏览历史以及在线和离线活动的痕迹。" : "Remove browsing history and traces of online and offline activity instantly.")
                    .font(.system(size: 14))
                    .foregroundColor(.white.opacity(0.8))
                    .frame(maxWidth: 400, alignment: .leading)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 60)
            
            HStack(spacing: 40) {
                // 左侧功能列表
                VStack(alignment: .leading, spacing: 24) {
                    FeatureRow(icon: "theatermasks", title: loc.currentLanguage == .chinese ? "移除浏览痕迹" : "Remove Browsing Traces", description: loc.currentLanguage == .chinese ? "清理浏览历史，包括常用浏览器存储的自动填写表单和其他数据。" : "Clean browsing history, including autofill forms and other data stored by common browsers.")
                    FeatureRow(icon: "message", title: loc.currentLanguage == .chinese ? "清理聊天数据" : "Clean Chat Data", description: loc.currentLanguage == .chinese ? "您可以清理 Skype 和其他信息应用程序的聊天历史记录。" : "You can clean chat history for Skype and other messaging applications.")
                    FeatureRow(icon: "exclamationmark.triangle", title: loc.currentLanguage == .chinese ? "授予完全磁盘访问权限，清理更多内容" : "Grant Full Disk Access to Clean More", description: loc.currentLanguage == .chinese ? "MacOptimizer 需要完全磁盘访问权限才能清理隐私项目。" : "MacOptimizer requires Full Disk Access to clean privacy items.", isWarning: true)
                    
                    Button(action: {
                        // 打开系统设置
                        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles") {
                            NSWorkspace.shared.open(url)
                        }
                    }) {
                        Text(loc.currentLanguage == .chinese ? "授权访问" : "Grant Access")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(.black)
                            .padding(.horizontal, 20)
                            .padding(.vertical, 8)
                            .background(Color.yellow) // 匹配设计图黄色按钮
                            .cornerRadius(6)
                    }
                    .buttonStyle(.plain)
                    .padding(.leading, 40) // Indent under the warning icon
                }
                .frame(maxWidth: 500)
                
                // 右侧大停止标志 (Design Image 1)
                ZStack {
                    PolygonShape(sides: 8)
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color(red: 1.0, green: 0.6, blue: 0.8), // 亮粉
                                    Color(red: 0.8, green: 0.2, blue: 0.5)  // 深粉
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 240, height: 240)
                        .shadow(color: Color.black.opacity(0.3), radius: 20, x: 0, y: 10)
                        .overlay(
                            PolygonShape(sides: 8)
                                .stroke(Color.white.opacity(0.2), lineWidth: 2)
                        )
                    
                    Image(systemName: "hand.raised.fill")
                        .font(.system(size: 100))
                        .foregroundColor(.white.opacity(0.9))
                }
            }
            
            Spacer()
            
            // 底部扫描按钮
            Button(action: startScan) {
                ZStack {
                     Circle()
                        .fill(Color.white.opacity(0.1))
                        .frame(width: 80, height: 80)
                    
                    Circle()
                        .stroke(Color.white.opacity(0.3), lineWidth: 2)
                        .frame(width: 76, height: 76)
                    
                    Text(loc.currentLanguage == .chinese ? "扫描" : "Scan")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(.white)
                }
            }
            .buttonStyle(.plain)
            .padding(.bottom, 40)
        }
    }
    
    // MARK: - 2. 扫描中页面 (Scanning)
    private var scanningView: some View {
        VStack {
            Spacer()
            
            // 扫描动画 - 停止标志微动
            ZStack {
                PolygonShape(sides: 8)
                    .fill(
                        LinearGradient(
                            colors: [
                                Color(red: 0.9, green: 0.4, blue: 0.6),
                                Color(red: 0.7, green: 0.2, blue: 0.4)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 180, height: 180)
                    .scaleEffect(pulse ? 1.05 : 1.0)
                    .animation(Animation.easeInOut(duration: 1.0).repeatForever(autoreverses: true), value: pulse)
                
                Image(systemName: "hand.raised.fill")
                    .font(.system(size: 80))
                    .foregroundColor(.white)
            }
            .padding(.bottom, 40)
            
            // 扫描状态文本
            Text(loc.currentLanguage == .chinese ? "正在查找隐私项..." : "Searching for privacy items...")
                .font(.title2)
                .foregroundColor(.white)
            
            // 当前扫描路径/项目显示
            if let lastItem = service.privacyItems.last {
                Text(lastItem.displayPath)
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.6))
                    .padding(.top, 8)
                    .transition(.opacity)
                    .id("ScanPath")
            }
            
            Spacer()
            
            // 停止按钮
            Button(action: stopScan) {
                ZStack {
                    Circle()
                        .fill(Color.white.opacity(0.1))
                        .frame(width: 60, height: 60)
                    
                    Text(loc.currentLanguage == .chinese ? "停止" : "Stop")
                        .font(.system(size: 14))
                        .foregroundColor(.white)
                }
            }
            .buttonStyle(.plain)
            .padding(.bottom, 40)
        }
        .onAppear {
            pulse = true
        }
    }
    
    // MARK: - 3. 扫描结果页面 (Results)
    private var resultsView: some View {
        VStack(spacing: 0) {
            resultsHeaderView
            resultsTitleView
            resultsSplitView
            resultsBottomBar
        }
    }
    
    private var resultsHeaderView: some View {
        HStack {
            Button(action: {
                scanState = .initial
                service.privacyItems.removeAll()
            }) {
                HStack {
                    Image(systemName: "chevron.left")
                    Text(loc.currentLanguage == .chinese ? "返回" : "Back")
                }
                .foregroundColor(.white.opacity(0.8))
            }
            .buttonStyle(.plain)
            
            Spacer()
            
            Text(loc.currentLanguage == .chinese ? "隐私" : "Privacy")
                .font(.headline)
                .foregroundColor(.white.opacity(0.8))
            
            Spacer()
            
            // 搜索框占位
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.white.opacity(0.5))
                Text(loc.currentLanguage == .chinese ? "搜索" : "Search")
                    .foregroundColor(.white.opacity(0.5))
                Spacer()
            }
            .frame(width: 200, height: 32)
            .background(Color.white.opacity(0.1))
            .cornerRadius(6)
            
            // 助手按钮
            Button(action: {}) {
                HStack(spacing: 4) {
                    Circle().fill(Color.blue).frame(width: 8, height: 8)
                    Text(loc.currentLanguage == .chinese ? "助手" : "Assistant")
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Color.black.opacity(0.3))
                .cornerRadius(12)
            }
            .buttonStyle(.plain)
            .foregroundColor(.white)
        }
        .padding()
    }
    
    private var resultsTitleView: some View {
        HStack {
            VStack(alignment: .leading) {
                Text(selectedSidebarItem.title)
                    .font(.title)
                    .bold()
                    .foregroundColor(.white)
                
                Text(loc.currentLanguage == .chinese ? "您的任何应用都可以请求获得更多权限..." : "Any application can request more permissions...")
                    .font(.subheadline)
                    .foregroundColor(.white.opacity(0.7))
                    .lineLimit(2)
            }
            Spacer()
        }
        .padding(.horizontal)
        .padding(.bottom)
    }
    
    private var resultsSplitView: some View {
        HStack(spacing: 0) {
            categoryListView
                .frame(width: 250)
                .background(Color.black.opacity(0.2))
            
            detailListView
                .background(Color.white.opacity(0.05))
        }
    }
    
    private var categoryListView: some View {
        VStack(spacing: 0) {
            // 表头
            HStack {
                Spacer()
                Text(loc.currentLanguage == .chinese ? "排序方式按 名称" : "Sort by Name")
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.6))
            }
            .padding(8)
            
            ScrollView {
                VStack(spacing: 4) {
                    // Application Permissions
                    if service.totalPermissionsCount > 0 || true { // Always show permissions if needed or check empty
                        categoryRow(for: .permissions, count: service.totalPermissionsCount)
                    }
                    
                    // Recent Items
                    let recentCount = service.privacyItems.filter { $0.type == .recentItems }.count
                    if recentCount > 0 {
                        categoryRow(for: .recentItems, count: recentCount)
                    }
                    
                    // Browsers
                    ForEach(BrowserType.allCases.filter { $0 != .system }, id: \.self) { browser in
                        let count = service.privacyItems.filter { $0.browser == browser }.count
                        if count > 0 {
                            categoryRow(for: .browser(browser), count: count)
                        }
                    }
                    
                    // Wi-Fi
                    let wifiCount = service.privacyItems.filter { $0.type == .wifi }.count
                    if wifiCount > 0 {
                        categoryRow(for: .wifi, count: wifiCount)
                    }
                    
                    // Chat
                    let chatCount = service.privacyItems.filter { $0.type == .chat }.count
                    if chatCount > 0 {
                        categoryRow(for: .chat, count: chatCount)
                    }
                }
                .padding(.horizontal, 12)
            }
        }
    }
    
    // Helper to build a clickable row
    private func categoryRow(for item: SidebarCategory, count: Int) -> some View {
        PrivacyCategoryRow(
            icon: item.icon,
            title: item.title,
            count: count,
            isSelected: selectedSidebarItem == item
        )
        .onTapGesture {
            selectedSidebarItem = item
        }
    }
    
    private var detailListView: some View {
        VStack(spacing: 0) {
            HStack {
                Text(loc.currentLanguage == .chinese ? "分组方式 许可类型" : "Group by Type")
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.6))
                Spacer()
                Text(loc.currentLanguage == .chinese ? "排序方式按 名称" : "Sort by Name")
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.6))
            }
            .padding(8)
            
            List {
                ForEach(filteredItems) { item in
                    PrivacyRow(item: item, service: service)
                        .listRowBackground(Color.clear)
                        .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
        }
    }
    
    private var filteredItems: [PrivacyItem] {
        switch selectedSidebarItem {
        case .permissions:
            return service.privacyItems.filter { $0.type == .permissions }
        case .recentItems:
            return service.privacyItems.filter { $0.type == .recentItems }
        case .wifi:
            return service.privacyItems.filter { $0.type == .wifi }
        case .chat:
            return service.privacyItems.filter { $0.type == .chat }
        case .browser(let b):
            return service.privacyItems.filter { $0.browser == b }
        }
    }
    
    private var resultsBottomBar: some View {
        HStack {
            Spacer()
            Button(action: startClean) {
                ZStack {
                    Circle()
                    .fill(Color.white.opacity(0.2))
                    .frame(width: 70, height: 70)
                    
                    VStack(spacing: 2) {
                        Text(loc.currentLanguage == .chinese ? "移除" : "Remove")
                            .font(.system(size: 14))
                    }
                    .foregroundColor(.white)
                }
            }
            .buttonStyle(.plain)
            Spacer()
        }
        .frame(height: 100)
        .background(Color.black.opacity(0.3))
    }
    
    private func selectFirstAvailableCategory() {
        if service.totalPermissionsCount > 0 { selectedSidebarItem = .permissions }
        else if service.privacyItems.contains(where: { $0.type == .recentItems }) { selectedSidebarItem = .recentItems }
        else if let b = BrowserType.allCases.first(where: { br in service.privacyItems.contains(where: { $0.browser == br }) }) { selectedSidebarItem = .browser(b) }
        else if service.privacyItems.contains(where: { $0.type == .wifi }) { selectedSidebarItem = .wifi }
        else if service.privacyItems.contains(where: { $0.type == .chat }) { selectedSidebarItem = .chat }
    }

    
    // MARK: - 4. 清理页面 (Cleaning)
    private var cleaningView: some View {
        VStack(spacing: 40) {
            Spacer()
            
            ZStack {
                PolygonShape(sides: 8)
                    .fill(
                        LinearGradient(
                            colors: [Color.pink.opacity(0.8), Color.purple.opacity(0.8)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 200, height: 200)
                
                 Image(systemName: "hand.raised.fill")
                    .font(.system(size: 80))
                    .foregroundColor(.white)
            }
            
            Text(loc.currentLanguage == .chinese ? "正在清理活动痕迹..." : "Cleaning activity traces...")
                .font(.title)
                .bold()
                .foregroundColor(.white)
            
            // 清理进度项 (模拟)
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Image(systemName: "clock") // Icon
                        .font(.title2)
                        .foregroundColor(.blue)
                        
                    Text(loc.currentLanguage == .chinese ? "最近项目列表" : "Recent Items List")
                        .foregroundColor(.white)
                    Spacer()
                    Text(loc.currentLanguage == .chinese ? "15 个痕迹" : "15 traces")
                        .foregroundColor(.white.opacity(0.7))
                    Image(systemName: "checkmark.square.fill")
                        .foregroundColor(.blue)
                }
                .padding(.horizontal, 40)
                
                HStack {
                    Image(systemName: "lock.shield")
                        .font(.title2)
                        .foregroundColor(.blue)
                        
                    Text(loc.currentLanguage == .chinese ? "应用权限" : "Application Permissions")
                        .foregroundColor(.white)
                    Spacer()
                    Image(systemName: "ellipsis")
                        .foregroundColor(.white.opacity(0.5))
                }
                .padding(.horizontal, 40)
            }
            .frame(maxWidth: 400)
            
            Spacer()
            
            // 停止按钮
             Button(action: {
                // Cancel clean logic ?
             }) {
                ZStack {
                    Circle()
                        .trim(from: 0, to: 0.3) // Progress ring
                        .stroke(Color.green, lineWidth: 4)
                        .frame(width: 64, height: 64)
                        .rotationEffect(.degrees(-90))
                    
                    Circle()
                        .stroke(Color.white.opacity(0.2), lineWidth: 4)
                        .frame(width: 64, height: 64)
                    
                    Text(loc.currentLanguage == .chinese ? "停止" : "Stop")
                        .font(.system(size: 13))
                        .foregroundColor(.white)
                }
            }
            .buttonStyle(.plain)
            .padding(.bottom, 40)
        }
    }
    
    // MARK: - 5. 完成页面 (Finished)
    private var finishedView: some View {
        VStack(spacing: 30) {
            Spacer()
            
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 80))
                .foregroundColor(.green)
                .shadow(color: .green.opacity(0.5), radius: 10)
            
            Text(loc.currentLanguage == .chinese ? "清理完成" : "Cleanup Complete")
                .font(.largeTitle)
                .bold()
                .foregroundColor(.white)
            
            Text(ByteCountFormatter.string(fromByteCount: cleanedSize, countStyle: .file))
                .font(.title2)
                .foregroundColor(.white.opacity(0.8))
            
            Spacer()
            
            Button(action: {
                scanState = .initial
            }) {
                Text(loc.currentLanguage == .chinese ? "完成" : "Done")
                    .font(.headline)
                    .foregroundColor(.white)
                    .padding(.horizontal, 40)
                    .padding(.vertical, 12)
                    .background(Capsule().fill(Color.white.opacity(0.2)))
            }
            .buttonStyle(.plain)
            .padding(.bottom, 50)
        }
    }
    
    // MARK: - Logic Actions
    
    private func startScan() {
        withAnimation { scanState = .scanning }
        Task {
            await service.scanAll()
            // 如果未停止，则进入完成并显示结果
            if !service.shouldStop {
                withAnimation { scanState = .completed }
            } else {
                // If stopped, reset to initial
                withAnimation { scanState = .initial }
                service.shouldStop = false // Reset flag
            }
        }
    }
    
    private func stopScan() {
        service.stopScan()
        withAnimation { scanState = .initial }
    }
    
    private func startClean() {
        let runningBrowsers = service.checkRunningBrowsers()
        if !runningBrowsers.isEmpty {
            showingCloseBrowserAlert = true
        } else {
            Task {
                await performClean(closeBrowsers: false)
            }
        }
    }
    
    private func performClean(closeBrowsers: Bool) async {
        withAnimation { scanState = .cleaning }
        if closeBrowsers {
            _ = await service.closeBrowsers()
        }
        
        // Simulate progress or wait for service
        let result = await service.cleanSelected()
        await MainActor.run {
            cleanedSize = result.cleaned
            withAnimation { scanState = .finished }
        }
    }
}

// MARK: - Reusable Components

struct FeatureRow: View {
    let icon: String
    let title: String
    let description: String
    var isWarning: Bool = false
    
    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            Image(systemName: icon)
                .font(.system(size: 24))
                .foregroundColor(isWarning ? .yellow : .white.opacity(0.7))
                .frame(width: 32)
            
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(isWarning ? .yellow : .white)
                
                Text(description)
                    .font(.system(size: 12))
                    .foregroundColor(.white.opacity(0.6))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

struct PrivacyCategoryRow: View {
    let icon: String
    let title: String
    let count: Int
    let isSelected: Bool
    var isHidden: Bool = false
    
    var body: some View {
        if !isHidden {
            HStack {
                // Radio button mock
                Circle()
                    .stroke(Color.white.opacity(0.5), lineWidth: 1)
                    .frame(width: 16, height: 16)
                    .overlay(
                        Circle()
                            .fill(isSelected ? Color.blue : Color.clear)
                            .frame(width: 8, height: 8)
                    )
                
                Image(systemName: icon)
                    .frame(width: 24)
                    .foregroundColor(.white) // design colorful icons based on type
                
                Text(title)
                    .foregroundColor(.white)
                    .font(.system(size: 13))
                
                Spacer()
                
                Text("\(count) 项")
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.5))
            }
            .padding(.vertical, 8)
            .padding(.horizontal, 12)
            .contentShape(Rectangle())
            .background(isSelected ? Color.white.opacity(0.1) : Color.clear)
            .cornerRadius(8)
        }
    }
}

// Polygon Shape for Stop Sign
struct PolygonShape: Shape {
    var sides: Int
    
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let center = CGPoint(x: rect.width / 2, y: rect.height / 2)
        let radius = min(rect.width, rect.height) / 2
        let angle = CGFloat.pi * 2 / CGFloat(sides)
        let rotationOffset = CGFloat.pi / CGFloat(sides) // Rotate to have flat top/bottom for octagon? No, flat side for stop sign usually requires 22.5 deg offset
        
        let startAngle = -CGFloat.pi / 2 + rotationOffset // Start from top
        
        for i in 0..<sides {
            let currentAngle = startAngle + angle * CGFloat(i)
            let x = center.x + radius * cos(currentAngle)
            let y = center.y + radius * sin(currentAngle)
            
            if i == 0 {
                path.move(to: CGPoint(x: x, y: y))
            } else {
                path.addLine(to: CGPoint(x: x, y: y))
            }
        }
        path.closeSubpath()
        return path
    }
}

struct PrivacyRow: View {
    let item: PrivacyItem
    @ObservedObject var service: PrivacyScannerService
    
    var body: some View {
        HStack {
            Toggle("", isOn: Binding(
                get: { item.isSelected },
                set: { newValue in
                    if let index = service.privacyItems.firstIndex(where: { $0.id == item.id }) {
                        service.privacyItems[index].isSelected = newValue
                    }
                    service.objectWillChange.send()
                }
            ))
            .toggleStyle(CheckboxStyle())
            .labelsHidden()
            
            Image(systemName: item.type.icon)
                .foregroundColor(.white)
            
            Text(item.displayPath)
                .font(.system(size: 13))
                .foregroundColor(.white)
            
            Spacer()
            
            Text(ByteCountFormatter.string(fromByteCount: item.size, countStyle: .file))
                .font(.system(size: 12))
                .foregroundColor(.white.opacity(0.6))
        }
        .padding(.vertical, 4)
    }
}
