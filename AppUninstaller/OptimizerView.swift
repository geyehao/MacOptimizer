
import SwiftUI
import AppKit
import UniformTypeIdentifiers

// MARK: - Optimization Task Enum
enum OptimizerTask: String, CaseIterable, Identifiable {
    case heavyConsumers
    case launchAgents
    case hungApps
    
    var id: String { rawValue }
    
    var icon: String {
        switch self {
        case .heavyConsumers: return "chart.xyaxis.line" // Graph icon
        case .launchAgents: return "rocket.fill"
        case .hungApps: return "hourglass"
        }
    }
    
    var iconColor: Color {
        switch self {
        case .heavyConsumers: return Color(red: 1.0, green: 0.6, blue: 0.2) // Orange
        case .launchAgents: return Color(red: 0.2, green: 0.8, blue: 0.4)   // Green/Cyan
        case .hungApps: return Color(red: 0.9, green: 0.3, blue: 0.3)       // Reddish
        }
    }
    
    var englishTitle: String {
        switch self {
        case .heavyConsumers: return "Heavy Consumers"
        case .launchAgents: return "Launch Agents"
        case .hungApps: return "Hung Applications"
        }
    }
    
    var englishDescription: String {
        switch self {
        case .heavyConsumers: return "Quit apps that are using too much processing power."
        case .launchAgents: return "Manage helper applications that launch automatically."
        case .hungApps: return "Force quit applications that are not responding."
        }
    }
    
    // Localized properties
    func title(for language: AppLanguage) -> String {
        switch language {
        case .chinese:
            switch self {
            case .heavyConsumers: return "占用较多资源的项目"
            case .launchAgents: return "启动代理"
            case .hungApps: return "挂起的应用程序"
            }
        case .english: return englishTitle
        }
    }
    
    func description(for language: AppLanguage) -> String {
        switch language {
        case .chinese:
            switch self {
            case .heavyConsumers: return "通常，很难发现一些运行的进程开始占用太多 Mac 资源。如果您不是真正需要这样的应用程序运行，则将其找出来并关闭。"
            case .launchAgents: return "通常，这些是其他软件产品的小辅助应用程序，可以扩展其主产品的功能。但是在一些情况下，您可以考虑移除或禁用它们。"
            case .hungApps: return "如果应用程序停止响应，您可以强制将其关闭以释放资源。"
            }
        case .english: return englishDescription
        }
    }
}

// MARK: - Data Models
struct OptimizerProcessItem: Identifiable, Equatable {
    let id: Int32 // PID
    let name: String
    let icon: NSImage
    let usageDescription: String // e.g. "15% CPU" or "500 MB"
    var isSelected: Bool = false
}

struct LaunchAgentItem: Identifiable, Equatable {
    let id = UUID()
    let path: String
    let name: String // Extracted from filename or Label
    let label: String
    let icon: NSImage
    var isEnabled: Bool // Status
    var isSelected: Bool = false // For toggle action (disable/enable)
}

// MARK: - Service
class OptimizerService: ObservableObject {
    @Published var selectedTask: OptimizerTask = .heavyConsumers
    @Published var heavyProcesses: [OptimizerProcessItem] = []
    @Published var launchAgents: [LaunchAgentItem] = []
    @Published var hungApps: [OptimizerProcessItem] = []
    @Published var isScanning = false
    @Published var isExecuting = false
    
    func scan() {
        isScanning = true
        Task {
            await fetchHeavyConsumers()
            await fetchLaunchAgents()
            await fetchHungApps()
            await MainActor.run { self.isScanning = false }
        }
    }
    
    @MainActor
    private func fetchHeavyConsumers() {
        // Run ps command to get top CPU consumers
        // ps -Aceo pid,%cpu,comm -r | head -n 10
        let task = Process()
        task.launchPath = "/bin/bash"
        task.arguments = ["-c", "ps -Aceo pid,%cpu,comm -r | head -n 15"]
        
        let pipe = Pipe()
        task.standardOutput = pipe
        task.launch()
        
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        if let output = String(data: data, encoding: .utf8) {
            var items: [OptimizerProcessItem] = []
            let lines = output.components(separatedBy: .newlines).dropFirst() // Skip header
            
            for line in lines {
                let parts = line.trimmingCharacters(in: .whitespaces).components(separatedBy: .whitespaces).filter { !$0.isEmpty }
                if parts.count >= 3, let pid = Int32(parts[0]), let cpu = Double(parts[1]) {
                    if cpu > 1.0 { // Filter apps using > 1% CPU (simulated threshold for "Heavy")
                         // Get app name and icon
                        if let app = NSRunningApplication(processIdentifier: pid) {
                            // Only show apps with icons (user visible)
                            if let icon = app.icon, let name = app.localizedName {
                                items.append(OptimizerProcessItem(id: pid, name: name, icon: icon, usageDescription: String(format: "%.1f%% CPU", cpu)))
                            }
                        }
                    }
                }
            }
            self.heavyProcesses = items
        }
    }
    
    @MainActor
    private func fetchLaunchAgents() {
        var items: [LaunchAgentItem] = []
        let paths = [
            FileManager.default.homeDirectoryForCurrentUser.path + "/Library/LaunchAgents",
            "/Library/LaunchAgents"
        ]
        
        for path in paths {
            if let files = try? FileManager.default.contentsOfDirectory(atPath: path) {
                for file in files where file.hasSuffix(".plist") {
                    let fullPath = path + "/" + file
                    // Simplified: Use filename as name, generic icon
                    let name = file.replacingOccurrences(of: ".plist", with: "")
                    // Check if loaded? roughly assume enabled if file exists for now, 
                    // real check involves `launchctl list`
                    
                    // Simple logic: existing plist = enabled (unless disabled in override database, which is complex)
                    // We will just list them.
                    items.append(LaunchAgentItem(
                        path: fullPath,
                        name: name,
                        label: name,
                        icon: NSWorkspace.shared.icon(for: UTType(filenameExtension: "plist") ?? .propertyList),
                        isEnabled: true
                    ))
                }
            }
        }
        self.launchAgents = items
    }
    
    @MainActor
    private func fetchHungApps() {
        // Detect apps in Uninterruptible sleep (U) or Zombie (Z) state
        let task = Process()
        task.launchPath = "/bin/bash"
        task.arguments = ["-c", "ps -Aceo pid,state,comm | grep -e 'U' -e 'Z'"]
        
        let pipe = Pipe()
        task.standardOutput = pipe
        task.launch()
        
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        if let output = String(data: data, encoding: .utf8) {
             var items: [OptimizerProcessItem] = []
             let lines = output.components(separatedBy: .newlines)
             for line in lines {
                 let parts = line.trimmingCharacters(in: .whitespaces).components(separatedBy: .whitespaces).filter { !$0.isEmpty }
                 if parts.count >= 3, let pid = Int32(parts[0]) {
                     // Check if it's a gui app
                     if let app = NSRunningApplication(processIdentifier: pid), let icon = app.icon, let name = app.localizedName {
                         let state = parts[1]
                         let desc = state.contains("Z") ? "Zombie" : "Unresponsive"
                         items.append(OptimizerProcessItem(id: pid, name: name, icon: icon, usageDescription: desc))
                     }
                 }
             }
             self.hungApps = items
        }
    }
    
    func executeSelectedTasks() {
        Task {
            await MainActor.run { isExecuting = true }
            
            // 1. Kill Heavy Consumers
            for item in heavyProcesses where item.isSelected {
                kill(item.id, SIGKILL)
            }
            
            // 2. Disable Launch Agents
            for item in launchAgents where item.isSelected {
                 // unload
                 let task = Process()
                 task.launchPath = "/bin/launchctl"
                 task.arguments = ["bootout", "gui/\(getuid())", item.path] // Modern syntax
                 // fallback to unload if bootout fails?
                 try? task.run()
                 
                 // Move to disabled folder? Or just rename to .disabled
                 // We will simply unload for now.
            }
            
            // Refresh
            await fetchHeavyConsumers()
            await fetchLaunchAgents()
            await MainActor.run { isExecuting = false }
        }
    }
    
    func toggleSelection(for id: Any) {
        // Helper to toggle
    }
}

// MARK: - Views
struct OptimizerView: View {
    @StateObject private var service = OptimizerService()
    @ObservedObject private var loc = LocalizationManager.shared
    
    @State private var viewState = 0 // 0: Landing, 1: List
    
    var body: some View {
        ZStack {
             // Shared Background
            BackgroundStyles.privacy.ignoresSafeArea()
            
            if viewState == 0 {
                OptimizerLandingView(viewState: $viewState, loc: loc)
            } else {
                optimizerListView
            }
        }
        .onAppear {
            service.scan()
            // Always start at landing page
            viewState = 0
        }
    }
    
    // Existing list logic moved here
    var optimizerListView: some View {
        GeometryReader { geometry in
            HStack(spacing: 0) {
                // LEFT PANEL (Task Selection)
                ZStack {
                    Color.black.opacity(0.1).ignoresSafeArea()
                    VStack(alignment: .leading, spacing: 0) {
                         // Back button (Functional)
                        Button(action: { viewState = 0 }) {
                            HStack(spacing: 4) {
                                Image(systemName: "chevron.left")
                                Text(loc.currentLanguage == .chinese ? "简介" : "Intro")
                            }
                            .foregroundColor(.white.opacity(0.7))
                            .font(.system(size: 13))
                        }
                        .buttonStyle(.plain)
                        .padding(.leading, 16)
                        .padding(.top, 16)
                        .padding(.bottom, 20)
                        
                        // Tasks List
                        ScrollView {
                            VStack(spacing: 4) {
                                ForEach(OptimizerTask.allCases) { task in
                                    OptimizerTaskRow(
                                        task: task,
                                        isSelected: service.selectedTask == task,
                                        loc: loc
                                    )
                                    .onTapGesture {
                                        service.selectedTask = task
                                    }
                                }
                            }
                            .padding(.horizontal, 10)
                        }
                    }
                }
                .frame(width: geometry.size.width * 0.4)
                
                // RIGHT PANEL (Details)
                ZStack {
                    // Background handled in parent ZStack
                    
                    VStack(alignment: .leading, spacing: 0) {
                        // Header
                        HStack {
                            Text(loc.currentLanguage == .chinese ? "优化" : "Optimization")
                                .font(.system(size: 13))
                                .foregroundColor(.white.opacity(0.6))
                            Spacer()
                            
                            // Search Bar
                            HStack {
                                Image(systemName: "magnifyingglass")
                                    .foregroundColor(.white.opacity(0.5))
                                Text(loc.currentLanguage == .chinese ? "搜索" : "Search")
                                    .foregroundColor(.white.opacity(0.3))
                                Spacer()
                            }
                            .frame(width: 160, height: 28)
                            .background(Color.black.opacity(0.2))
                            .cornerRadius(6)
                            
                            // Assistant Button
                            HStack(spacing: 4) {
                                Circle().fill(Color.green).frame(width: 6, height: 6)
                                Text(loc.currentLanguage == .chinese ? "助手" : "Assistant")
                            }
                            .font(.system(size: 12))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 4)
                            .background(Color.white.opacity(0.15))
                            .cornerRadius(12)
                        }
                        .padding(.horizontal, 24)
                        .padding(.top, 16)
                        .padding(.bottom, 20)
                        
                        // Title & Desc
                        VStack(alignment: .leading, spacing: 8) {
                            Text(service.selectedTask.title(for: loc.currentLanguage))
                                .font(.system(size: 28, weight: .bold))
                                .foregroundColor(.white)
                            
                            Text(service.selectedTask.description(for: loc.currentLanguage))
                                .font(.system(size: 13))
                                .lineSpacing(4)
                                .foregroundColor(.white.opacity(0.8))
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .padding(.horizontal, 24)
                        .padding(.bottom, 30)
                        
                        // Content List
                        ScrollView {
                            VStack(spacing: 0) {
                                if service.selectedTask == .heavyConsumers {
                                    ForEach($service.heavyProcesses) { $proc in
                                        HeavyProcessRow(item: proc, isSelected: $proc.isSelected)
                                    }
                                } else if service.selectedTask == .launchAgents {
                                    ForEach($service.launchAgents) { $agent in
                                        LaunchAgentRow(item: agent, isSelected: $agent.isSelected, loc: loc)
                                    }
                                } else {
                                    if service.hungApps.isEmpty {
                                        Text(loc.currentLanguage == .chinese ? "未发现挂起的应用程序" : "No hung applications found")
                                            .foregroundColor(.white.opacity(0.5))
                                            .padding(.top, 40)
                                            .frame(maxWidth: .infinity, alignment: .center)
                                    } else {
                                        ForEach($service.hungApps) { $proc in
                                            HeavyProcessRow(item: proc, isSelected: $proc.isSelected)
                                        }
                                    }
                                }
                            }
                            .padding(.horizontal, 24)
                        }
                        
                        Spacer()
                        
                        // Execute Button (Only clear if items selected?)
                        HStack {
                            Spacer()
                            Button(action: { service.executeSelectedTasks() }) {
                                ZStack {
                                    Circle()
                                        .fill(Color.white.opacity(0.15))
                                        .frame(width: 110, height: 110)
                                    
                                    Circle()
                                        .strokeBorder(
                                            LinearGradient(colors: [.white.opacity(0.5), .white.opacity(0.1)], startPoint: .top, endPoint: .bottom),
                                            lineWidth: 1
                                        )
                                        .frame(width: 110, height: 110)
                                    
                                    Text(loc.currentLanguage == .chinese ? "执行" : "Run")
                                        .font(.system(size: 18, weight: .medium))
                                        .foregroundColor(.white)
                                }
                                .shadow(color: .black.opacity(0.2), radius: 10, y: 5)
                            }
                            .buttonStyle(.plain)
                            .padding(.bottom, 30)
                            Spacer()
                        }
                    }
                    .frame(width: geometry.size.width * 0.6)
                }
            }
        }
    }
}

// MARK: - Row Components
struct OptimizerTaskRow: View {
    let task: OptimizerTask
    let isSelected: Bool
    @ObservedObject var loc: LocalizationManager
    
    var body: some View {
        HStack(spacing: 12) {
            // Radio Button
            ZStack {
                Circle()
                    .strokeBorder(isSelected ? Color.white : Color.white.opacity(0.3), lineWidth: 1.5)
                    .frame(width: 18, height: 18)
                
                if isSelected {
                    Circle()
                        .fill(Color.white)
                        .frame(width: 10, height: 10)
                }
            }
            
            // Icon
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(task.iconColor)
                    .frame(width: 32, height: 32)
                
                Image(systemName: task.icon)
                    .font(.system(size: 16))
                    .foregroundColor(.white)
            }
            .shadow(color: task.iconColor.opacity(0.4), radius: 4, y: 2)
            
            // Title
            Text(task.title(for: loc.currentLanguage))
                .font(.system(size: 14, weight: isSelected ? .medium : .regular))
                .foregroundColor(.white)
            
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(isSelected ? Color.white.opacity(0.1) : Color.clear)
        .cornerRadius(8)
    }
}

struct HeavyProcessRow: View {
    let item: OptimizerProcessItem
    @Binding var isSelected: Bool
    
    var body: some View {
        HStack(spacing: 12) {
            // Checkbox
            Button(action: { isSelected.toggle() }) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 20))
                    .foregroundColor(isSelected ? .white : .white.opacity(0.3))
            }
            .buttonStyle(.plain)
            
            Image(nsImage: item.icon)
                .resizable()
                .frame(width: 32, height: 32)
            
            Text(item.name)
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(.white)
            
            Spacer()
            
            Text(item.usageDescription)
                .font(.system(size: 12))
                .foregroundColor(.white.opacity(0.6))
                .padding(.horizontal, 8)
                .padding(.vertical, 2)
                .background(Color.white.opacity(0.1))
                .cornerRadius(4)
        }
        .padding(.vertical, 10)
        .contentShape(Rectangle())
        .onTapGesture { isSelected.toggle() }
    }
}

struct LaunchAgentRow: View {
    let item: LaunchAgentItem
    @Binding var isSelected: Bool
    @ObservedObject var loc: LocalizationManager
    
    var body: some View {
        HStack(spacing: 12) {
            // Checkbox
            Button(action: { isSelected.toggle() }) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 20))
                    .foregroundColor(isSelected ? .white : .white.opacity(0.3))
            }
            .buttonStyle(.plain)
            
            Image(nsImage: item.icon)
                .resizable()
                .frame(width: 32, height: 32)
            
            Text(item.name)
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(.white)
            
            Spacer()
            
            // Status Indicator
            HStack(spacing: 6) {
                Circle()
                    .fill(item.isEnabled ? Color.green : Color.gray)
                    .frame(width: 8, height: 8)
                Text(item.isEnabled ? (loc.currentLanguage == .chinese ? "已启用" : "Enabled") : (loc.currentLanguage == .chinese ? "已禁用" : "Disabled"))
                    .font(.system(size: 12))
                    .foregroundColor(.white.opacity(0.8))
            }
        }
        .padding(.vertical, 10)
    }
}
// MARK: - Landing Components
struct OptimizerLandingView: View {
    @Binding var viewState: Int // 0=Landing, 1=List
    @ObservedObject var loc: LocalizationManager
    
    var body: some View {
        GeometryReader { geometry in
            HStack(spacing: 0) {
                // Left: Content
                VStack(alignment: .leading, spacing: 32) {
                    VStack(alignment: .leading, spacing: 12) {
                        Text(loc.currentLanguage == .chinese ? "优化" : "Optimization")
                            .font(.system(size: 32, weight: .bold))
                            .foregroundColor(.white)
                        
                        Text(loc.currentLanguage == .chinese ? "通过控制 Mac 上运行的应用，提高它的输出。" : "Improve output by controlling apps running on your Mac.")
                            .font(.system(size: 14))
                            .foregroundColor(.white.opacity(0.8))
                            .lineLimit(2)
                    }
                    
                    VStack(alignment: .leading, spacing: 24) {
                        ShredderFeatureRow(icon: "light.beacon.max.fill", title: loc.currentLanguage == .chinese ? "管理应用的启动代理" : "Manage Launch Agents", description: loc.currentLanguage == .chinese ? "控制您的 Mac 支持的应用。" : "Control applications supported by your Mac.")
                        ShredderFeatureRow(icon: "waveform.path.ecg", title: loc.currentLanguage == .chinese ? "控制正在运行的应用" : "Control Running Apps", description: loc.currentLanguage == .chinese ? "管理所有登录项，仅运行真正需要的项目。" : "Manage login items, running only what you truly need.")
                    }
                    
                    Button(action: { viewState = 1 }) {
                        Text(loc.currentLanguage == .chinese ? "查看项目" : "View Items")
                            .font(.system(size: 14, weight: .semibold))
                            .padding(.horizontal, 24)
                            .padding(.vertical, 10)
                            .background(Color(red: 0.2, green: 0.7, blue: 0.9)) // Cyan/Blue
                            .foregroundColor(.white)
                            .cornerRadius(6)
                    }
                    .buttonStyle(.plain)
                    .shadow(radius: 5)
                }
                .frame(maxWidth: 400)
                .padding(.leading, 60)
                
                Spacer()
                
                // Right: Icon (Purple Circle with Sliders)
                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [Color(red: 0.8, green: 0.4, blue: 0.7), Color(red: 0.5, green: 0.2, blue: 0.7)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 320, height: 320)
                        
                        .shadow(radius: 20)
                    
                    // Sliders (Visual)
                    HStack(spacing: 30) {
                        // Slider 1
                        VStack(spacing: 0) {
                            Capsule().fill(Color.white.opacity(0.3)).frame(width: 8, height: 60)
                            Circle().fill(Color.white).frame(width: 24, height: 24)
                            Capsule().fill(Color.white.opacity(0.3)).frame(width: 8, height: 100)
                        }
                        // Slider 2
                        VStack(spacing: 0) {
                            Capsule().fill(Color.white.opacity(0.3)).frame(width: 8, height: 100)
                            Circle().fill(Color.white).frame(width: 24, height: 24)
                            Capsule().fill(Color.white.opacity(0.3)).frame(width: 8, height: 60)
                        }
                        // Slider 3 (Lower)
                        VStack(spacing: 0) {
                            Capsule().fill(Color.white.opacity(0.3)).frame(width: 8, height: 40)
                            Circle().fill(Color.white).frame(width: 24, height: 24)
                            Capsule().fill(Color.white.opacity(0.3)).frame(width: 8, height: 120)
                        }
                    }
                }
                .padding(.trailing, 60)
            }
        }
    }
}
