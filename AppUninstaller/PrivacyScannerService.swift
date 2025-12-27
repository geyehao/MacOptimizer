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
        
        // 4. LocalStorage
        let localStorageURL = home.appendingPathComponent("Library/Safari/LocalStorage")
        if let size = folderSize(at: localStorageURL), size > 0 {
            items.append(PrivacyItem(browser: .safari, type: .history, path: localStorageURL, size: size, displayPath: "Safari 本地存储"))
        }
        
        // 5. WebsiteData (Databases, IndexedDB, etc.)
        let websiteDataURL = home.appendingPathComponent("Library/Safari/Databases")
        if let size = folderSize(at: websiteDataURL), size > 0 {
            items.append(PrivacyItem(browser: .safari, type: .history, path: websiteDataURL, size: size, displayPath: "Safari 网站数据库"))
        }
        
        // 6. Touch Icons / Favicon Cache
        let touchIconsURL = home.appendingPathComponent("Library/Safari/Touch Icons Cache")
        if let size = folderSize(at: touchIconsURL), size > 0 {
            items.append(PrivacyItem(browser: .safari, type: .history, path: touchIconsURL, size: size, displayPath: "Safari 图标缓存"))
        }
        
        // 7. Form Values
        let formValuesURL = home.appendingPathComponent("Library/Safari/Form Values")
        if let size = fileSize(at: formValuesURL) {
            items.append(PrivacyItem(browser: .safari, type: .history, path: formValuesURL, size: size, displayPath: "Safari 表单数据"))
        }
        
        // 8. Safari Caches
        let safariCacheURL = home.appendingPathComponent("Library/Caches/com.apple.Safari")
        if let size = folderSize(at: safariCacheURL), size > 0 {
            items.append(PrivacyItem(browser: .safari, type: .history, path: safariCacheURL, size: size, displayPath: "Safari 缓存"))
        }
        
        // 9. Last Session
        let lastSessionURL = home.appendingPathComponent("Library/Safari/LastSession.plist")
        if let size = fileSize(at: lastSessionURL) {
            items.append(PrivacyItem(browser: .safari, type: .history, path: lastSessionURL, size: size, displayPath: "Safari 上次会话"))
        }
        
        // 10. Top Sites
        let topSitesURL = home.appendingPathComponent("Library/Safari/TopSites.plist")
        if let size = fileSize(at: topSitesURL) {
            items.append(PrivacyItem(browser: .safari, type: .history, path: topSitesURL, size: size, displayPath: "Safari 热门网站"))
        }
        
        return items
    }
    
    private func scanChrome() -> [PrivacyItem] {
        var items: [PrivacyItem] = []
        let home = FileManager.default.homeDirectoryForCurrentUser
        let chromeDir = home.appendingPathComponent("Library/Application Support/Google/Chrome")
        
        guard fileManager.fileExists(atPath: chromeDir.path) else { return [] }
        
        // 扫描所有 Profile (Default, Profile 1, Profile 2, etc.)
        var profiles: [URL] = []
        let defaultPath = chromeDir.appendingPathComponent("Default")
        if fileManager.fileExists(atPath: defaultPath.path) {
            profiles.append(defaultPath)
        }
        
        // 查找其他 Profile
        if let contents = try? fileManager.contentsOfDirectory(at: chromeDir, includingPropertiesForKeys: nil) {
            for item in contents where item.lastPathComponent.hasPrefix("Profile ") {
                profiles.append(item)
            }
        }
        
        for profile in profiles {
            let profileName = profile.lastPathComponent
            
            // 1. History
            let historyURL = profile.appendingPathComponent("History")
            addWithRelatedFiles(path: historyURL, type: .history, browser: .chrome, description: "Chrome 浏览记录 (\(profileName))", to: &items)
            
            // 2. Cookies
            let cookiesURL = profile.appendingPathComponent("Cookies")
            addWithRelatedFiles(path: cookiesURL, type: .cookies, browser: .chrome, description: "Chrome Cookies (\(profileName))", to: &items)
            
            // 3. Local Storage
            let localStorageURL = profile.appendingPathComponent("Local Storage/leveldb")
            if let size = folderSize(at: localStorageURL), size > 0 {
                items.append(PrivacyItem(browser: .chrome, type: .history, path: localStorageURL, size: size, displayPath: "Chrome 本地存储 (\(profileName))"))
            }
            
            // 4. Session Storage
            let sessionStorageURL = profile.appendingPathComponent("Session Storage")
            if let size = folderSize(at: sessionStorageURL), size > 0 {
                items.append(PrivacyItem(browser: .chrome, type: .history, path: sessionStorageURL, size: size, displayPath: "Chrome 会话存储 (\(profileName))"))
            }
            
            // 5. IndexedDB
            let indexedDBURL = profile.appendingPathComponent("IndexedDB")
            if let size = folderSize(at: indexedDBURL), size > 0 {
                items.append(PrivacyItem(browser: .chrome, type: .history, path: indexedDBURL, size: size, displayPath: "Chrome IndexedDB (\(profileName))"))
            }
            
            // 6. Cache
            let cacheURL = profile.appendingPathComponent("Cache")
            if let size = folderSize(at: cacheURL), size > 0 {
                items.append(PrivacyItem(browser: .chrome, type: .history, path: cacheURL, size: size, displayPath: "Chrome 缓存 (\(profileName))"))
            }
            
            // 7. Web Data (表单自动填充)
            let webDataURL = profile.appendingPathComponent("Web Data")
            addWithRelatedFiles(path: webDataURL, type: .history, browser: .chrome, description: "Chrome 表单数据 (\(profileName))", to: &items)
            
            // 8. Visited Links
            let visitedLinksURL = profile.appendingPathComponent("Visited Links")
            if let size = fileSize(at: visitedLinksURL) {
                items.append(PrivacyItem(browser: .chrome, type: .history, path: visitedLinksURL, size: size, displayPath: "Chrome 访问链接 (\(profileName))"))
            }
            
            // 9. Top Sites
            let topSitesURL = profile.appendingPathComponent("Top Sites")
            addWithRelatedFiles(path: topSitesURL, type: .history, browser: .chrome, description: "Chrome 热门网站 (\(profileName))", to: &items)
        }
        
        return items
    }
    
    private func scanFirefox() -> [PrivacyItem] {
        var items: [PrivacyItem] = []
        let home = FileManager.default.homeDirectoryForCurrentUser
        let profilesPath = home.appendingPathComponent("Library/Application Support/Firefox/Profiles")
        
        guard let profiles = try? fileManager.contentsOfDirectory(at: profilesPath, includingPropertiesForKeys: nil), !profiles.isEmpty else { return [] }
        
        for profile in profiles {
            let profileName = profile.lastPathComponent
            
            // 1. History (places.sqlite)
            let historyURL = profile.appendingPathComponent("places.sqlite")
            addWithRelatedFiles(path: historyURL, type: .history, browser: .firefox, description: "Firefox 历史记录 (\(profileName))", to: &items)
            
            // 2. Cookies
            let cookiesURL = profile.appendingPathComponent("cookies.sqlite")
            addWithRelatedFiles(path: cookiesURL, type: .cookies, browser: .firefox, description: "Firefox Cookies (\(profileName))", to: &items)
            
            // 3. Form History (表单自动填充)
            let formHistoryURL = profile.appendingPathComponent("formhistory.sqlite")
            addWithRelatedFiles(path: formHistoryURL, type: .history, browser: .firefox, description: "Firefox 表单记录 (\(profileName))", to: &items)
            
            // 4. Downloads
            let downloadsURL = profile.appendingPathComponent("downloads.sqlite")
            addWithRelatedFiles(path: downloadsURL, type: .downloads, browser: .firefox, description: "Firefox 下载记录 (\(profileName))", to: &items)
            
            // 5. Session Store
            let sessionURL = profile.appendingPathComponent("sessionstore.jsonlz4")
            if let size = fileSize(at: sessionURL) {
                items.append(PrivacyItem(browser: .firefox, type: .history, path: sessionURL, size: size, displayPath: "Firefox 会话数据 (\(profileName))"))
            }
            
            // 6. Content Prefs (网站偏好)
            let contentPrefsURL = profile.appendingPathComponent("content-prefs.sqlite")
            addWithRelatedFiles(path: contentPrefsURL, type: .history, browser: .firefox, description: "Firefox 内容偏好 (\(profileName))", to: &items)
            
            // 7. IndexedDB
            let indexedDBURL = profile.appendingPathComponent("storage/default")
            if let size = folderSize(at: indexedDBURL), size > 0 {
                items.append(PrivacyItem(browser: .firefox, type: .history, path: indexedDBURL, size: size, displayPath: "Firefox IndexedDB (\(profileName))"))
            }
            
            // 8. Cache
            let cacheURL = profile.appendingPathComponent("cache2")
            if let size = folderSize(at: cacheURL), size > 0 {
                items.append(PrivacyItem(browser: .firefox, type: .history, path: cacheURL, size: size, displayPath: "Firefox 缓存 (\(profileName))"))
            }
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
        
        // 1. iMessage
        let messagesURL = home.appendingPathComponent("Library/Messages/chat.db")
        addWithRelatedFiles(path: messagesURL, type: .chat, browser: .system, description: "iMessage 聊天记录", to: &items)
        
        let attachmentsURL = home.appendingPathComponent("Library/Messages/Attachments")
        if let size = folderSize(at: attachmentsURL), size > 0 {
            items.append(PrivacyItem(browser: .system, type: .chat, path: attachmentsURL, size: size, displayPath: "iMessage 附件"))
        }
        
        // 2. 微信 (WeChat)
        let wechatContainerURL = home.appendingPathComponent("Library/Containers/com.tencent.xinWeChat")
        if fileManager.fileExists(atPath: wechatContainerURL.path) {
            // 聊天数据库
            let wechatDataURL = wechatContainerURL.appendingPathComponent("Data/Library/Application Support/com.tencent.xinWeChat")
            if let size = folderSize(at: wechatDataURL), size > 0 {
                items.append(PrivacyItem(browser: .system, type: .chat, path: wechatDataURL, size: size, displayPath: "微信聊天数据"))
            }
            
            // 缓存
            let wechatCacheURL = wechatContainerURL.appendingPathComponent("Data/Library/Caches")
            if let size = folderSize(at: wechatCacheURL), size > 0 {
                items.append(PrivacyItem(browser: .system, type: .chat, path: wechatCacheURL, size: size, displayPath: "微信缓存"))
            }
        }
        
        // 3. QQ
        let qqContainerURL = home.appendingPathComponent("Library/Containers/com.tencent.qq")
        if fileManager.fileExists(atPath: qqContainerURL.path) {
            let qqDataURL = qqContainerURL.appendingPathComponent("Data/Library/Application Support/QQ")
            if let size = folderSize(at: qqDataURL), size > 0 {
                items.append(PrivacyItem(browser: .system, type: .chat, path: qqDataURL, size: size, displayPath: "QQ 聊天数据"))
            }
            
            let qqCacheURL = qqContainerURL.appendingPathComponent("Data/Library/Caches")
            if let size = folderSize(at: qqCacheURL), size > 0 {
                items.append(PrivacyItem(browser: .system, type: .chat, path: qqCacheURL, size: size, displayPath: "QQ 缓存"))
            }
        }
        
        // 4. Telegram
        let telegramGroupURL = home.appendingPathComponent("Library/Group Containers/6N38VWS5BX.ru.keepcoder.Telegram")
        if fileManager.fileExists(atPath: telegramGroupURL.path) {
            let telegramDataURL = telegramGroupURL.appendingPathComponent("stable")
            if let size = folderSize(at: telegramDataURL), size > 0 {
                items.append(PrivacyItem(browser: .system, type: .chat, path: telegramDataURL, size: size, displayPath: "Telegram 聊天数据"))
            }
        }
        
        // Telegram 缓存
        let telegramCacheURL = home.appendingPathComponent("Library/Caches/ru.keepcoder.Telegram")
        if let size = folderSize(at: telegramCacheURL), size > 0 {
            items.append(PrivacyItem(browser: .system, type: .chat, path: telegramCacheURL, size: size, displayPath: "Telegram 缓存"))
        }
        
        // 5. 企业微信
        let weworkContainerURL = home.appendingPathComponent("Library/Containers/com.tencent.WeWorkMac")
        if fileManager.fileExists(atPath: weworkContainerURL.path) {
            let weworkDataURL = weworkContainerURL.appendingPathComponent("Data/Library/Application Support")
            if let size = folderSize(at: weworkDataURL), size > 0 {
                items.append(PrivacyItem(browser: .system, type: .chat, path: weworkDataURL, size: size, displayPath: "企业微信聊天数据"))
            }
            
            let weworkCacheURL = weworkContainerURL.appendingPathComponent("Data/Library/Caches")
            if let size = folderSize(at: weworkCacheURL), size > 0 {
                items.append(PrivacyItem(browser: .system, type: .chat, path: weworkCacheURL, size: size, displayPath: "企业微信缓存"))
            }
        }
        
        // 6. 钉钉
        let dingtalkContainerURL = home.appendingPathComponent("Library/Containers/com.alibaba.DingTalkMac")
        if fileManager.fileExists(atPath: dingtalkContainerURL.path) {
            let dingtalkDataURL = dingtalkContainerURL.appendingPathComponent("Data/Library/Application Support")
            if let size = folderSize(at: dingtalkDataURL), size > 0 {
                items.append(PrivacyItem(browser: .system, type: .chat, path: dingtalkDataURL, size: size, displayPath: "钉钉聊天数据"))
            }
        }
        
        // 7. Slack
        let slackCacheURL = home.appendingPathComponent("Library/Caches/com.tinyspeck.slackmacgap")
        if let size = folderSize(at: slackCacheURL), size > 0 {
            items.append(PrivacyItem(browser: .system, type: .chat, path: slackCacheURL, size: size, displayPath: "Slack 缓存"))
        }
        
        let slackDataURL = home.appendingPathComponent("Library/Application Support/Slack")
        if let size = folderSize(at: slackDataURL), size > 0 {
            items.append(PrivacyItem(browser: .system, type: .chat, path: slackDataURL, size: size, displayPath: "Slack 数据"))
        }
        
        // 8. Discord
        let discordCacheURL = home.appendingPathComponent("Library/Application Support/discord")
        if let size = folderSize(at: discordCacheURL), size > 0 {
            items.append(PrivacyItem(browser: .system, type: .chat, path: discordCacheURL, size: size, displayPath: "Discord 数据"))
        }
        
        // 9. WhatsApp
        let whatsappCacheURL = home.appendingPathComponent("Library/Caches/net.whatsapp.WhatsApp")
        if let size = folderSize(at: whatsappCacheURL), size > 0 {
            items.append(PrivacyItem(browser: .system, type: .chat, path: whatsappCacheURL, size: size, displayPath: "WhatsApp 缓存"))
        }
        
        let whatsappDataURL = home.appendingPathComponent("Library/Application Support/WhatsApp")
        if let size = folderSize(at: whatsappDataURL), size > 0 {
            items.append(PrivacyItem(browser: .system, type: .chat, path: whatsappDataURL, size: size, displayPath: "WhatsApp 数据"))
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
