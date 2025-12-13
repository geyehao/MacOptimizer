import Foundation
import Combine
import AppKit

// MARK: - 扫描状态
enum PrivacyScanState {
    case initial
    case scanning
    case completed
    case cleaning
    case finished
}

// MARK: - 隐私数据类型
enum PrivacyType: String, CaseIterable, Identifiable {
    case history = "浏览记录"
    case cookies = "Cookie 文件"
    case downloads = "下载记录"
    case permissions = "应用权限"
    case recentItems = "最近项目列表"
    case wifi = "Wi-Fi 网络"
    case chat = "聊天信息"
    
    var id: String { rawValue }
    
    var icon: String {
        switch self {
        case .history: return "clock.arrow.circlepath"
        case .cookies: return "lock.circle"
        case .downloads: return "arrow.down.circle"
        case .permissions: return "lock.shield" // 权限锁
        case .recentItems: return "clock" // 最近项目
        case .wifi: return "wifi" // Wi-Fi
        case .chat: return "message" // 聊天
        }
    }
}

// MARK: - 浏览器类型
enum BrowserType: String, CaseIterable, Identifiable {
    case safari = "Safari"
    case chrome = "Google Chrome"
    case firefox = "Firefox"
    case system = "System" // 系统项
    
    var id: String { rawValue }
    
    var icon: String {
        switch self {
        case .safari: return "safari"
        case .chrome: return "globe"
        case .firefox: return "flame"
        case .system: return "applelogo"
        }
    }
}

// MARK: - 隐私项模型
struct PrivacyItem: Identifiable, Equatable {
    let id = UUID()
    let browser: BrowserType
    let type: PrivacyType
    let path: URL
    let size: Int64
    let displayPath: String // 用于显示更友好的路径或描述
    var isSelected: Bool = true
}

// MARK: - 隐私扫描服务
class PrivacyScannerService: ObservableObject {
    @Published var privacyItems: [PrivacyItem] = []
    @Published var isScanning: Bool = false
    @Published var scanProgress: Double = 0
    @Published var shouldStop = false
    
    // 统计数据
    var totalHistoryCount: Int { count(for: .history) }
    var totalCookiesCount: Int { count(for: .cookies) }
    var totalPermissionsCount: Int { count(for: .permissions) }
    
    private let fileManager = FileManager.default
    
    private func count(for type: PrivacyType) -> Int {
        privacyItems.filter { $0.type == type }.count
    }
    
    var totalSize: Int64 {
        privacyItems.reduce(0) { $0 + $1.size }
    }
    
    var selectedSize: Int64 {
        privacyItems.filter { $0.isSelected }.reduce(0) { $0 + $1.size }
    }
    
    func stopScan() {
        shouldStop = true
        isScanning = false
    }
    
    // MARK: - 扫描方法
    func scanAll() async {
        await MainActor.run {
            isScanning = true
            shouldStop = false
            privacyItems.removeAll()
            scanProgress = 0
        }
        
        // 1. 扫描浏览器数据
        let browsers = BrowserType.allCases.filter { $0 != .system }
        for (index, browser) in browsers.enumerated() {
            if shouldStop { break }
            let items = await scanBrowser(browser)
            await MainActor.run {
                privacyItems.append(contentsOf: items)
                scanProgress = Double(index + 1) / Double(browsers.count + 4)
            }
        }
        
        // 2. 扫描最近项目
        if !shouldStop {
            let recentItems = await scanRecentItems()
            await MainActor.run {
                privacyItems.append(contentsOf: recentItems)
                scanProgress += 0.1
            }
        }
        
        // 3. 扫描应用权限 (TCC)
        if !shouldStop {
            let permissions = await scanPermissions()
            await MainActor.run {
                privacyItems.append(contentsOf: permissions)
                scanProgress += 0.1
            }
        }
        
        // 4. 扫描 Wi-Fi
        if !shouldStop {
            let wifiItems = await scanWiFi()
            await MainActor.run {
                privacyItems.append(contentsOf: wifiItems)
                scanProgress += 0.1
            }
        }
        
        // 5. 扫描聊天数据
        if !shouldStop {
            let chatItems = await scanChatData()
            await MainActor.run {
                privacyItems.append(contentsOf: chatItems)
                scanProgress = 1.0
                isScanning = false
            }
        } else {
             await MainActor.run { isScanning = false }
        }
    }
    
    // MARK: - 辅助方法：添加关联文件 (WAL/SHM)
    private func addWithRelatedFiles(path: URL, type: PrivacyType, browser: BrowserType, description: String, to items: inout [PrivacyItem]) {
        if let size = fileSize(at: path) {
            items.append(PrivacyItem(browser: browser, type: type, path: path, size: size, displayPath: description))
        }
        
        let walPath = path.appendingPathExtension("wal")
        if let size = fileSize(at: walPath) {
            items.append(PrivacyItem(browser: browser, type: type, path: walPath, size: size, displayPath: "\(description) (WAL)"))
        }
        
        let shmPath = path.appendingPathExtension("shm")
        if let size = fileSize(at: shmPath) {
            items.append(PrivacyItem(browser: browser, type: type, path: shmPath, size: size, displayPath: "\(description) (SHM)"))
        }
    }
    
    // MARK: - 进程检测与终止
    func checkRunningBrowsers() -> [BrowserType] {
        var running: [BrowserType] = []
        let apps = NSWorkspace.shared.runningApplications
        
        for app in apps {
            guard let bundleId = app.bundleIdentifier else { continue }
            if bundleId.contains("com.apple.Safari") {
                if !running.contains(.safari) { running.append(.safari) }
            } else if bundleId.contains("com.google.Chrome") {
                if !running.contains(.chrome) { running.append(.chrome) }
            } else if bundleId.contains("org.mozilla.firefox") {
                if !running.contains(.firefox) { running.append(.firefox) }
            }
        }
        return running
    }
    
    func closeBrowsers() async -> Bool {
        let apps = NSWorkspace.shared.runningApplications
        var success = true
        
        for app in apps {
            guard let bundleId = app.bundleIdentifier else { continue }
            if bundleId.contains("com.apple.Safari") || 
               bundleId.contains("com.google.Chrome") || 
               bundleId.contains("org.mozilla.firefox") {
                
                app.terminate()
                
                // 等待一段时间看是否关闭
                try? await Task.sleep(nanoseconds: 500_000_000) // 0.5s
                if !app.isTerminated {
                    app.forceTerminate()
                }
                
                if !app.isTerminated {
                    success = false
                }
            }
        }
        return success
    }
    
    // MARK: - 清理方法
    func cleanSelected() async -> (cleaned: Int64, failed: Int64) {
        var cleaned: Int64 = 0
        var failed: Int64 = 0
        
        let itemsToDelete = privacyItems.filter { $0.isSelected }
        
        for item in itemsToDelete {
            do {
                // 如果是特殊的逻辑类型（如权限），需要特殊处理
                if item.type == .permissions {
                    // Try to reset permission: tccutil reset SERVICE APP_BUNDLE_ID
                    // This is limited and might require higher privileges or specific entitlements.
                    // For now we might just skip or log.
                    // 这里仅做模拟，实际需要 System TCC reset 权限
                    cleaned += 0 // Metadata only
                } else if item.type == .wifi {
                     // Wi-Fi removal usually requires network setup tool
                     // Skip for safety
                } else {
                    // 普通文件删除
                    if fileManager.fileExists(atPath: item.path.path) {
                        try fileManager.removeItem(at: item.path)
                        cleaned += item.size
                    }
                }
            } catch {
                print("Failed to delete \(item.path.path): \(error)")
                failed += item.size
            }
        }
        
        await MainActor.run {
            // Remove deleted items from list
            privacyItems.removeAll { item in
                itemsToDelete.contains { $0.id == item.id }
            }
        }
        
        return (cleaned, failed)
    }
    
    // MARK: - Helper Scanning Methods
    
    private func scanBrowser(_ browser: BrowserType) async -> [PrivacyItem] {
        var items: [PrivacyItem] = []
        
        switch browser {
        case .safari:
            items.append(contentsOf: scanSafari())
        case .chrome:
            items.append(contentsOf: scanChrome())
        case .firefox:
            items.append(contentsOf: scanFirefox())
        case .system:
            break
        }
        
        return items
    }
    
    private func scanSafari() -> [PrivacyItem] {
        var items: [PrivacyItem] = []
        let home = FileManager.default.homeDirectoryForCurrentUser
        
        // 1. History
        let historyURL = home.appendingPathComponent("Library/Safari/History.db")
        addWithRelatedFiles(path: historyURL, type: .history, browser: .safari, description: "Safari 浏览记录数据库", to: &items)
        
        // 2. Downloads
        let downloadsURL = home.appendingPathComponent("Library/Safari/Downloads.plist")
         if let size = fileSize(at: downloadsURL) {
            items.append(PrivacyItem(browser: .safari, type: .downloads, path: downloadsURL, size: size, displayPath: "Safari 下载记录列表"))
        }
        
        // 3. Cookies
        let cookiesURL = home.appendingPathComponent("Library/Cookies/Cookies.binarycookies")
        if let size = fileSize(at: cookiesURL) {
            items.append(PrivacyItem(browser: .safari, type: .cookies, path: cookiesURL, size: size, displayPath: "Safari Cookie 文件"))
        }
        
        return items
    }
    
    private func scanChrome() -> [PrivacyItem] {
        var items: [PrivacyItem] = []
        let home = FileManager.default.homeDirectoryForCurrentUser
        let chromeDir = home.appendingPathComponent("Library/Application Support/Google/Chrome")
        
        guard fileManager.fileExists(atPath: chromeDir.path) else { return [] }
        
        let defaultPath = chromeDir.appendingPathComponent("Default")
        if fileManager.fileExists(atPath: defaultPath.path) {
             let historyURL = defaultPath.appendingPathComponent("History")
             addWithRelatedFiles(path: historyURL, type: .history, browser: .chrome, description: "Chrome 浏览记录 (Default)", to: &items)
             
             let cookiesURL = defaultPath.appendingPathComponent("Cookies")
             addWithRelatedFiles(path: cookiesURL, type: .cookies, browser: .chrome, description: "Chrome Cookies (Default)", to: &items)
        }
        
        return items
    }
    
    private func scanFirefox() -> [PrivacyItem] {
        var items: [PrivacyItem] = []
        let home = FileManager.default.homeDirectoryForCurrentUser
        let profilesPath = home.appendingPathComponent("Library/Application Support/Firefox/Profiles")
        
        guard let profiles = try? fileManager.contentsOfDirectory(at: profilesPath, includingPropertiesForKeys: nil), !profiles.isEmpty else { return [] }
        
        for profile in profiles {
            let historyURL = profile.appendingPathComponent("places.sqlite")
            addWithRelatedFiles(path: historyURL, type: .history, browser: .firefox, description: "Firefox 历史记录 (\(profile.lastPathComponent))", to: &items)
        }
        
        return items
    }
    
    // MARK: - 新扫描器实现
    
    private func scanRecentItems() async -> [PrivacyItem] {
        var items: [PrivacyItem] = []
        let home = FileManager.default.homeDirectoryForCurrentUser
        
        // Recent Items Plist (Legacy but still used)
        let recentURL = home.appendingPathComponent("Library/Preferences/com.apple.recentitems.plist")
        if let size = fileSize(at: recentURL) {
            items.append(PrivacyItem(browser: .system, type: .recentItems, path: recentURL, size: size, displayPath: "最近使用的项目列表"))
        }
        
        // Shared File List (Modern Recent Items)
        let sharedFileList = home.appendingPathComponent("Library/Application Support/com.apple.sharedfilelist")
        if let size = folderSize(at: sharedFileList) {
             items.append(PrivacyItem(browser: .system, type: .recentItems, path: sharedFileList, size: size, displayPath: "共享文件列表 (最近与收藏)"))
        }
        
        return items
    }
    
    private func scanPermissions() async -> [PrivacyItem] {
        var items: [PrivacyItem] = []
        // 模拟扫描权限 - 实际需要 Full Disk Access 读取 TCC.db
        // /Library/Application Support/com.apple.TCC/TCC.db
        
        let tccURL = URL(fileURLWithPath: "/Library/Application Support/com.apple.TCC/TCC.db")
        
        // 尝试读取大小（如果有权限）
        if let size = fileSize(at: tccURL) {
            items.append(PrivacyItem(
                browser: .system,
                type: .permissions,
                path: tccURL,
                size: size,
                displayPath: "系统应用权限数据库 (TCC)"
            ))
        } else {
            // 如果没有权限，添加一个占位符提示用户 (Size 0)
            items.append(PrivacyItem(
                browser: .system,
                type: .permissions,
                path: tccURL,
                size: 0,
                displayPath: "应用权限 (需完全磁盘访问权限)"
            ))
        }
        
        return items
    }
    
    private func scanWiFi() async -> [PrivacyItem] {
        var items: [PrivacyItem] = []
        // /Library/Preferences/SystemConfiguration/com.apple.airport.preferences.plist
        let wifiURL = URL(fileURLWithPath: "/Library/Preferences/SystemConfiguration/com.apple.airport.preferences.plist")
        
        if let size = fileSize(at: wifiURL) {
            items.append(PrivacyItem(
                browser: .system,
                type: .wifi,
                path: wifiURL,
                size: size,
                displayPath: "已知 Wi-Fi 网络配置"
            ))
        }
        
        return items
    }
    
    private func scanChatData() async -> [PrivacyItem] {
        var items: [PrivacyItem] = []
        let home = FileManager.default.homeDirectoryForCurrentUser
        
        // Messages (iMessage)
        let messagesURL = home.appendingPathComponent("Library/Messages/chat.db")
        addWithRelatedFiles(path: messagesURL, type: .chat, browser: .system, description: "iMessage 聊天记录", to: &items)
        
        // Attachments
        let attachmentsURL = home.appendingPathComponent("Library/Messages/Attachments")
        if let size = folderSize(at: attachmentsURL) {
            items.append(PrivacyItem(browser: .system, type: .chat, path: attachmentsURL, size: size, displayPath: "iMessage 附件"))
        }
        
        return items
    }
    
    private func fileSize(at url: URL) -> Int64? {
        // 如果没有权限读取，可能会失败
        guard let attrs = try? fileManager.attributesOfItem(atPath: url.path) else { return nil }
        return attrs[.size] as? Int64
    }
    
    private func folderSize(at url: URL) -> Int64? {
        guard let enumerator = fileManager.enumerator(at: url, includingPropertiesForKeys: [.fileSizeKey]) else { return nil }
        var size: Int64 = 0
        for case let fileURL as URL in enumerator {
            if let fileSize = try? fileURL.resourceValues(forKeys: [.fileSizeKey]).fileSize {
                size += Int64(fileSize)
            }
        }
        return size
    }
}
