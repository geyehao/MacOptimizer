import SwiftUI
import AppKit

// MARK: - Console Dashboard
struct MonitorView: View {
    @State private var viewState: DashboardState = .dashboard
    @ObservedObject var loc = LocalizationManager.shared
    
    enum DashboardState {
        case dashboard
        case appManager
        case portManager
        case processManager
    }
    
    var body: some View {
        ZStack {
            // 背景渐变在 ContentView 中处理，这里只处理内容切换
            switch viewState {
            case .dashboard:
                ConsoleDashboardView(viewState: $viewState)
                    .transition(.opacity.combined(with: .move(edge: .leading)))
            case .appManager:
                ConsoleAppManagerView(viewState: $viewState)
                    .transition(.move(edge: .trailing))
            case .portManager:
                ConsolePortManagerView(viewState: $viewState)
                    .transition(.move(edge: .trailing))
            case .processManager:
                ConsoleProcessManagerView(viewState: $viewState)
                    .transition(.move(edge: .trailing))
            }
        }
        .animation(.easeInOut(duration: 0.3), value: viewState)
    }
}

// MARK: - 1. Dashboard Home View
struct ConsoleDashboardView: View {
    @Binding var viewState: MonitorView.DashboardState
    @ObservedObject var loc = LocalizationManager.shared
    @ObservedObject var scanManager = ScanServiceManager.shared
    @StateObject private var systemService = SystemMonitorService()
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                VStack(alignment: .leading) {
                    Text(loc.currentLanguage == .chinese ? "控制台" : "Console")
                        .font(.largeTitle)
                        .bold()
                        .foregroundColor(.white)
                    Text(loc.currentLanguage == .chinese ? "系统概览与管理" : "System Overview & Management")
                        .foregroundColor(.white.opacity(0.7))
                }
                Spacer()
            }
            .padding(32)
            
            ScrollView {
                VStack(spacing: 24) {
                    // Top Stats: Junk Size & System Stats
                    HStack(spacing: 20) {
                        // Junk Size Card
                        MonitorCard(title: loc.currentLanguage == .chinese ? "待清理垃圾" : "Junk to Clean", icon: "trash.fill", color: .pink) {
                            VStack(alignment: .leading, spacing: 8) {
                                Spacer()
                                Text(ByteCountFormatter.string(fromByteCount: scanManager.totalCleanableSize, countStyle: .file))
                                    .font(.system(size: 36, weight: .bold, design: .rounded))
                                    .foregroundColor(.white)
                                Text(loc.currentLanguage == .chinese ? "可释放空间" : "Reclaimable Space")
                                    .font(.caption)
                                    .foregroundColor(.white.opacity(0.6))
                                Spacer()
                            }
                        }
                        
                        // CPU & Memory Circle
                        MonitorCard(title: loc.currentLanguage == .chinese ? "系统负载" : "System Load", icon: "cpu", color: .blue) {
                            HStack(spacing: 30) {
                                UsageRing(percentage: systemService.cpuUsage, label: "CPU", subLabel: String(format: "%.0f%%", systemService.cpuUsage * 100))
                                UsageRing(percentage: systemService.memoryUsage, label: "RAM", subLabel: String(format: "%.0f%%", systemService.memoryUsage * 100))
                            }
                        }
                    }
                    .frame(height: 180)
                    
                    Text(loc.currentLanguage == .chinese ? "管理工具" : "Management Tools")
                        .font(.headline)
                        .foregroundColor(.white.opacity(0.8))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.top, 8)
                    
                    // Function Cards Grid
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 20) {
                        // App Management
                        DashboardButton(
                            title: loc.currentLanguage == .chinese ? "应用管理" : "App Manager",
                            description: loc.currentLanguage == .chinese ? "管理应用、强制退出、重置" : "Manage apps, force quit, reset",
                            icon: "square.grid.2x2.fill",
                            color: .cyan
                        ) {
                            viewState = .appManager
                        }
                        
                        // Port Management
                        DashboardButton(
                            title: loc.currentLanguage == .chinese ? "端口管理" : "Port Manager",
                            description: loc.currentLanguage == .chinese ? "查看和关闭网络端口" : "View and close network ports",
                            icon: "network",
                            color: .purple
                        ) {
                            viewState = .portManager
                        }
                        
                        // Process Management
                        DashboardButton(
                            title: loc.currentLanguage == .chinese ? "进程管理" : "Process Manager",
                            description: loc.currentLanguage == .chinese ? "监控和结束后台进程" : "Monitor and kill background processes",
                            icon: "waveform.path.ecg",
                            color: .green
                        ) {
                            viewState = .processManager
                        }
                    }
                }
                .padding(.horizontal, 32)
                .padding(.bottom, 32)
            }
        }
        .onAppear {
            systemService.startMonitoring()
            // 确保 junk size 是最新的
            if !scanManager.isAnyScanning && scanManager.totalCleanableSize == 0 {
                Task {
                    // 可选：静默启动垃圾扫描
                     scanManager.startJunkScanIfNeeded()
                     scanManager.startSmartCleanScanIfNeeded()
                }
            }
        }
        .onDisappear {
            systemService.stopMonitoring()
        }
    }
}

// MARK: - 2. App Management View
struct ConsoleAppManagerView: View {
    @Binding var viewState: MonitorView.DashboardState
    @StateObject private var appScanner = AppScanner()
    @StateObject private var processService = ProcessService()
    @ObservedObject var loc = LocalizationManager.shared
    @State private var searchText = ""
    @State private var isScanning = true
    
    var body: some View {
        VStack(spacing: 0) {
            // Header with Back Button
            ConsoleHeader(
                title: loc.currentLanguage == .chinese ? "应用管理" : "App Manager",
                backAction: { viewState = .dashboard }
            )
            
            // Search & Filter
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.secondaryText)
                TextField(loc.currentLanguage == .chinese ? "搜索应用..." : "Search apps...", text: $searchText)
                    .textFieldStyle(.plain)
                    .foregroundColor(.white)
                
                if !searchText.isEmpty {
                    Button(action: { searchText = "" }) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.secondaryText)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(10)
            .background(Color.white.opacity(0.1))
            .cornerRadius(8)
            .padding(.horizontal, 32)
            .padding(.top, 16)
            .padding(.bottom, 8)
            
            if isScanning {
                Spacer()
                ProgressView()
                Text(loc.currentLanguage == .chinese ? "正在加载应用..." : "Loading apps...")
                    .foregroundColor(.secondaryText)
                    .padding(.top)
                Spacer()
            } else {
                List {
                    // Header Row
                    HStack {
                        Text(loc.currentLanguage == .chinese ? "应用名称" : "App Name")
                            .frame(maxWidth: .infinity, alignment: .leading)
                        Text(loc.currentLanguage == .chinese ? "状态" : "Status")
                            .frame(width: 80, alignment: .leading)
                        Text(loc.currentLanguage == .chinese ? "操作" : "Actions")
                            .frame(width: 200, alignment: .trailing)
                    }
                    .font(.caption)
                    .foregroundColor(.secondaryText)
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                    
                    ForEach(filteredApps) { app in
                        AppManagerRow(app: app, processService: processService, loc: loc)
                            .listRowBackground(Color.white.opacity(0.02))
                            .listRowSeparator(.hidden)
                            .padding(.vertical, 4)
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
                .padding(.horizontal, 16)
            }
        }
        .onAppear {
            loadData()
        }
    }
    
    // Combine AppScanner data with Running status
    struct AppViewModel: Identifiable {
        let id: UUID
        let installedApp: InstalledApp
        var isRunning: Bool
        var processItem: ProcessItem?
    }
    
    @State private var appViewModels: [AppViewModel] = []
    
    var filteredApps: [AppViewModel] {
        if searchText.isEmpty {
            return appViewModels
        }
        return appViewModels.filter { $0.installedApp.name.localizedCaseInsensitiveContains(searchText) }
    }
    
    func loadData() {
        Task {
            isScanning = true
            if appScanner.apps.isEmpty {
                await appScanner.scanApplications()
            }
            
            await processService.scanProcesses(showApps: true)
            
            var viewModels: [AppViewModel] = []
            // Map validation path (bundle path) to running process items
            let runningMap = Dictionary(grouping: processService.processes, by: { $0.validationPath ?? "" })
            
            for app in appScanner.apps {
                var isRunning = false
                var pItem: ProcessItem? = nil
                
                if let processes = runningMap[app.path.path], let first = processes.first {
                    isRunning = true
                    pItem = first
                } else if let p = processService.processes.first(where: { $0.name == app.name }) {
                     isRunning = true
                     pItem = p
                }
                
                viewModels.append(AppViewModel(id: app.id, installedApp: app, isRunning: isRunning, processItem: pItem))
            }
            
            viewModels.sort {
                if $0.isRunning != $1.isRunning {
                    return $0.isRunning
                }
                return $0.installedApp.name < $1.installedApp.name
            }
            
            await MainActor.run {
                self.appViewModels = viewModels
                self.isScanning = false
            }
        }
    }
}

struct AppManagerRow: View {
    let app: ConsoleAppManagerView.AppViewModel
    @ObservedObject var processService: ProcessService
    var loc: LocalizationManager
    
    @State private var isRunningLocal: Bool
    @State private var isSpinning = false
    @State private var showSuccess = false
    @State private var showCleanConfirmation = false
    
    init(app: ConsoleAppManagerView.AppViewModel, processService: ProcessService, loc: LocalizationManager) {
        self.app = app
        self.processService = processService
        self.loc = loc
        self._isRunningLocal = State(initialValue: app.isRunning)
    }
    
    var body: some View {
        HStack {
            Image(nsImage: app.installedApp.icon)
                .resizable()
                .frame(width: 32, height: 32)
            
            VStack(alignment: .leading) {
                Text(app.installedApp.name)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.white)
                Text((loc.currentLanguage == .chinese ? "应用大小: " : "App Size: ") + app.installedApp.formattedSize)
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.6))
            }
            
            Spacer()
            
            // Status
            HStack {
                if isRunningLocal {
                    Circle().fill(Color.green).frame(width: 8, height: 8)
                    Text(loc.currentLanguage == .chinese ? "运行中" : "Running")
                        .font(.caption)
                        .foregroundColor(.green)
                } else {
                    Text(loc.currentLanguage == .chinese ? "未运行" : "Stopped")
                        .font(.caption)
                        .foregroundColor(.secondaryText)
                }
            }
            .frame(width: 80, alignment: .leading)
            
            // Actions
            HStack(spacing: 12) {
                // Initialize / Reset -> Clean
                Button(action: {
                    showCleanConfirmation = true
                }) {
                    HStack(spacing: 4) {
                        if isSpinning {
                            ProgressView().scaleEffect(0.5).frame(width: 10, height: 10)
                            Text(loc.currentLanguage == .chinese ? "清理中..." : "Cleaning...")
                        } else if showSuccess {
                            Image(systemName: "checkmark")
                            Text(loc.currentLanguage == .chinese ? "完成" : "Done")
                        } else {
                            Image(systemName: "eraser")
                            Text(loc.currentLanguage == .chinese ? "清理" : "Clean")
                        }
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(showSuccess ? Color.green.opacity(0.2) : Color.white.opacity(0.1))
                    .foregroundColor(showSuccess ? .green : .white)
                    .cornerRadius(6)
                    .frame(width: 100)
                }
                .disabled(isSpinning)
                .buttonStyle(.plain)
                .help(loc.currentLanguage == .chinese ? "清理应用残留数据（不删除应用本身）" : "Clean app data (keeps app installed)")
                .alert(isPresented: $showCleanConfirmation) {
                    Alert(
                        title: Text(loc.currentLanguage == .chinese ? "确认清理" : "Confirm Clean"),
                        message: Text(loc.currentLanguage == .chinese ? "该操作将清理应用的所有缓存、日志和配置数据。\n应用本身（\(app.installedApp.formattedSize)）将被保留。" : "This will clean all cache, logs, and config data.\nThe app itself (\(app.installedApp.formattedSize)) will be kept."),
                        primaryButton: .destructive(Text(loc.currentLanguage == .chinese ? "确认清理" : "Clean Data")) {
                            Task {
                                isSpinning = true
                                showSuccess = false
                                
                                // Minimum 1s delay for visual feedback
                                let startTime = Date()
                                
                                if isRunningLocal, let item = app.processItem {
                                     await processService.cleanAppData(for: item)
                                     withAnimation { isRunningLocal = false }
                                } else {
                                    // If stopped, manually scan and remove residuals
                                    let scanner = ResidualFileScanner()
                                    let files = await scanner.scanResidualFiles(for: app.installedApp)
                                    
                                     if !files.isEmpty {
                                         for file in files { file.isSelected = true }
                                         let appWithFiles = app.installedApp
                                         appWithFiles.residualFiles = files
                                         let remover = FileRemover()
                                         _ = await remover.removeResidualFiles(of: appWithFiles, moveToTrash: true)
                                     }
                                }
                                
                                // Ensure spinner shows for at least a moment
                                let elapsed = Date().timeIntervalSince(startTime)
                                if elapsed < 0.8 {
                                    try? await Task.sleep(nanoseconds: UInt64((0.8 - elapsed) * 1_000_000_000))
                                }
                                
                                await MainActor.run {
                                    isSpinning = false
                                    showSuccess = true
                                    
                                    DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                                        showSuccess = false
                                    }
                                }
                            }
                        },
                        secondaryButton: .cancel(Text(loc.currentLanguage == .chinese ? "取消" : "Cancel"))
                    )
                }
                
                // Force Quit
                if isRunningLocal {
                    Button(action: {
                        if let item = app.processItem {
                            processService.forceTerminateProcess(item)
                            withAnimation { isRunningLocal = false }
                        }
                    }) {
                        HStack(spacing: 4) {
                            Image(systemName: "xmark.octagon.fill")
                            Text(loc.currentLanguage == .chinese ? "强制退出" : "Force Quit")
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(Color.red.opacity(0.2))
                        .foregroundColor(.red)
                        .cornerRadius(6)
                    }
                    .buttonStyle(.plain)
                } else {
                    // Placeholder
                    Color.clear.frame(width: 90, height: 26)
                }
            }
            .frame(width: 200, alignment: .trailing)
        }
        .padding(12)
        .background(Color.white.opacity(0.05))
        .cornerRadius(8)
    }
}

// MARK: - 3. Port Management View
struct ConsolePortManagerView: View {
    @Binding var viewState: MonitorView.DashboardState
    @StateObject private var portService = PortScannerService()
    @ObservedObject var loc = LocalizationManager.shared
    @State private var searchText = ""
    
    var body: some View {
        VStack(spacing: 0) {
            ConsoleHeader(
                title: loc.currentLanguage == .chinese ? "端口管理" : "Port Manager",
                backAction: { viewState = .dashboard },
                refreshAction: { Task { await portService.scanPorts() } }
            )
            
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.secondaryText)
                TextField(loc.currentLanguage == .chinese ? "搜索端口、PID..." : "Search ports, PID...", text: $searchText)
                    .textFieldStyle(.plain)
                    .foregroundColor(.white)
            }
            .padding(10)
            .background(Color.white.opacity(0.1))
            .cornerRadius(8)
            .padding(.horizontal, 32)
            .padding(.top, 16)
            .padding(.bottom, 8)
            
            if portService.isScanning {
                Spacer()
                ProgressView()
                Spacer()
            } else {
                ScrollView {
                    VStack(spacing: 1) {
                        HStack {
                            Text(loc.currentLanguage == .chinese ? "程序" : "Process")
                                .frame(width: 150, alignment: .leading)
                            Text("PID")
                                .frame(width: 60, alignment: .leading)
                            Text(loc.currentLanguage == .chinese ? "端口" : "Port")
                                .frame(width: 80, alignment: .leading)
                            Text(loc.currentLanguage == .chinese ? "协议" : "Proto")
                                .frame(width: 60, alignment: .leading)
                            Spacer()
                            Text(loc.currentLanguage == .chinese ? "操作" : "Action")
                                .frame(width: 60)
                        }
                        .font(.caption)
                        .foregroundColor(.secondaryText)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 8)
                        
                        ForEach(portService.ports.filter {
                            searchText.isEmpty || $0.displayName.localizedCaseInsensitiveContains(searchText) || String($0.pid).contains(searchText) || $0.portString.contains(searchText)
                        }) { port in
                            HStack {
                                HStack(spacing: 8) {
                                    if let icon = port.icon {
                                        Image(nsImage: icon)
                                            .resizable()
                                            .frame(width: 20, height: 20)
                                    } else {
                                        Image(systemName: "network")
                                            .foregroundColor(.cyan)
                                    }
                                    Text(port.displayName).lineLimit(1)
                                }
                                .frame(width: 150, alignment: .leading)
                                
                                Text(String(port.pid))
                                    .frame(width: 60, alignment: .leading)
                                    .foregroundColor(.white.opacity(0.7))
                                
                                Text(port.portString)
                                    .frame(width: 80, alignment: .leading)
                                    .foregroundColor(.cyan)
                                    .fontWeight(.medium)
                                
                                Text(port.protocol)
                                    .frame(width: 60, alignment: .leading)
                                    .foregroundColor(.white.opacity(0.5))
                                
                                Spacer()
                                
                                Button(action: { portService.terminateProcess(port) }) {
                                    Text(loc.currentLanguage == .chinese ? "结束" : "Kill")
                                        .font(.caption)
                                        .foregroundColor(.white)
                                        .padding(.horizontal, 10)
                                        .padding(.vertical, 4)
                                        .background(Color.red.opacity(0.6))
                                        .cornerRadius(4)
                                }
                                .buttonStyle(.plain)
                                .frame(width: 60)
                            }
                            .padding(.horizontal, 20)
                            .padding(.vertical, 12)
                            .background(Color.white.opacity(0.02))
                            Divider().background(Color.white.opacity(0.05))
                        }
                    }
                }
            }
        }
        .onAppear {
            Task { await portService.scanPorts() }
        }
    }
}

// MARK: - 4. Process Management View
struct ConsoleProcessManagerView: View {
    @Binding var viewState: MonitorView.DashboardState
    @StateObject private var processService = ProcessService()
    @ObservedObject var loc = LocalizationManager.shared
    @State private var searchText = ""
    
    var body: some View {
        VStack(spacing: 0) {
            ConsoleHeader(
                title: loc.currentLanguage == .chinese ? "后台进程管理" : "Background Processes",
                backAction: { viewState = .dashboard },
                refreshAction: { Task { await processService.scanProcesses(showApps: false) } }
            )
            
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.secondaryText)
                TextField(loc.currentLanguage == .chinese ? "搜索进程..." : "Search processes...", text: $searchText)
                    .textFieldStyle(.plain)
                    .foregroundColor(.white)
            }
            .padding(10)
            .background(Color.white.opacity(0.1))
            .cornerRadius(8)
            .padding(.horizontal, 32)
            .padding(.top, 16)
            .padding(.bottom, 8)
            
            if processService.isScanning {
                Spacer()
                ProgressView()
                Spacer()
            } else {
                ScrollView {
                    VStack(spacing: 1) {
                        ForEach(processService.processes.filter { 
                            searchText.isEmpty || $0.name.localizedCaseInsensitiveContains(searchText) 
                        }) { item in
                            HStack {
                                Image(systemName: "gearshape.fill")
                                    .foregroundColor(.white.opacity(0.3))
                                    .font(.system(size: 14))
                                
                                VStack(alignment: .leading) {
                                    Text(item.name)
                                        .font(.system(size: 13, weight: .medium))
                                        .foregroundColor(.white)
                                    Text("PID: \(item.pid)")
                                        .font(.caption)
                                        .foregroundColor(.white.opacity(0.5))
                                }
                                
                                Spacer()
                                
                                Text(item.formattedMemory)
                                    .font(.system(size: 12, design: .monospaced))
                                    .foregroundColor(.white.opacity(0.7))
                                    .padding(.trailing, 10)
                                
                                Button(action: { processService.forceTerminateProcess(item) }) {
                                    Image(systemName: "xmark.octagon.fill")
                                        .foregroundColor(.red)
                                        .font(.system(size: 16))
                                }
                                .buttonStyle(.plain)
                                .help(loc.currentLanguage == .chinese ? "强制结束" : "Force Quit")
                            }
                            .padding(12)
                            .background(Color.white.opacity(0.02))
                            .cornerRadius(6)
                            .padding(.horizontal, 32)
                            .padding(.vertical, 2)
                        }
                    }
                    .padding(.vertical, 10)
                }
            }
        }
        .onAppear {
            Task { await processService.scanProcesses(showApps: false) }
        }
    }
}

// MARK: - Components

struct ConsoleHeader: View {
    let title: String
    let backAction: () -> Void
    var refreshAction: (() -> Void)? = nil
    
    var body: some View {
        HStack {
            Button(action: backAction) {
                HStack(spacing: 4) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 16, weight: .bold))
                    Text(title)
                        .font(.title2)
                        .bold()
                }
                .foregroundColor(.white)
            }
            .buttonStyle(.plain)
            
            Spacer()
            
            if let refresh = refreshAction {
                Button(action: refresh) {
                    Image(systemName: "arrow.clockwise")
                        .foregroundColor(.white.opacity(0.7))
                        .padding(8)
                        .background(Color.white.opacity(0.1))
                        .cornerRadius(8)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(32)
    }
}

struct DashboardButton: View {
    let title: String
    let description: String
    let icon: String
    let color: Color
    let action: () -> Void
    
    @State private var isHovering = false
    
    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 32))
                    .foregroundColor(color)
                    .padding(12)
                    .background(color.opacity(0.1))
                    .clipShape(Circle())
                
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.headline)
                        .foregroundColor(.white)
                    
                    Text(description)
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.6))
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(20)
            .background(Color.white.opacity(isHovering ? 0.1 : 0.05))
            .cornerRadius(16)
            .scaleEffect(isHovering ? 1.02 : 1.0)
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .animation(.spring(response: 0.3), value: isHovering)
    }
}

struct MonitorCard<Content: View>: View {
    let title: String
    let icon: String
    let color: Color
    let content: () -> Content
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Image(systemName: icon)
                    .foregroundColor(color)
                    .font(.title3)
                Text(title)
                    .font(.headline)
                    .foregroundColor(.white)
            }
            
            content()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .padding(20)
        .background(Color.white.opacity(0.05))
        .cornerRadius(16)
    }
}

struct UsageRing: View {
    let percentage: Double
    let label: String
    let subLabel: String
    
    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.white.opacity(0.1), lineWidth: 8)
            
            Circle()
                .trim(from: 0, to: percentage)
                .stroke(
                    AngularGradient(
                        colors: [.blue, .cyan],
                        center: .center,
                        startAngle: .degrees(0),
                        endAngle: .degrees(360)
                    ),
                    style: StrokeStyle(lineWidth: 8, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .animation(.easeOut(duration: 0.5), value: percentage)
            
            VStack {
                Text(label)
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.6))
                Text(subLabel)
                    .font(.title3)
                    .bold()
                    .foregroundColor(.white)
            }
        }
        .frame(width: 80, height: 80)
    }
}
