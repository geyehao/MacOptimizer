import SwiftUI

// MARK: - Maintenance View
struct MaintenanceView: View {
    @StateObject private var optimizer = SystemOptimizer()
    @ObservedObject private var loc = LocalizationManager.shared
    
    // States: Initial, Selection, Running, Finished
    enum MaintenanceState {
        case initial
        case selection
        case running
        case finished
    }
    
    @State private var currentState: MaintenanceState = .initial
    @State private var completedTasks: [String] = []
    
    var body: some View {
        Group {
            switch currentState {
            case .initial:
                initialView
            case .selection:
                selectionView
            case .running:
                runningView
            case .finished:
                finishedView
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(BackgroundStyles.privacy) // Reusing Privacy background for consistency/purple theme
    }
    
    // MARK: - Initial View
    var initialView: some View {
        HStack(spacing: 40) {
            // Left Content
            VStack(alignment: .leading, spacing: 20) {
                Text(loc.currentLanguage == .chinese ? "维护" : "Maintenance")
                    .font(.system(size: 40, weight: .bold))
                    .foregroundColor(.white)
                
                Text(loc.currentLanguage == .chinese ? "运行一组可快速优化系统性能的脚本。" : "Run a set of scripts to quickly optimize system performance.")
                    .font(.title3)
                    .foregroundColor(.white.opacity(0.8))
                    .frame(maxWidth: 400, alignment: .leading)
                
                VStack(alignment: .leading, spacing: 24) {
                    MaintenanceFeatureRow(
                        icon: "gauge.with.needle",
                        title: loc.currentLanguage == .chinese ? "提高驱动器性能" : "Improve Drive Performance",
                        description: loc.currentLanguage == .chinese ? "保护磁盘，确保其文件系统和物理状态良好。" : "Protect disk and ensure filesystem health."
                    )
                    
                    MaintenanceFeatureRow(
                        icon: "exclamationmark.triangle",
                        title: loc.currentLanguage == .chinese ? "消除应用程序错误" : "Fix Application Errors",
                        description: loc.currentLanguage == .chinese ? "通过修改权限以及运行维护脚本解决不适当的应用程序行为。" : "Fix app issues by repairing permissions."
                    )
                    
                    MaintenanceFeatureRow(
                        icon: "magnifyingglass",
                        title: loc.currentLanguage == .chinese ? "提高搜索性能" : "Improve Search Performance",
                        description: loc.currentLanguage == .chinese ? "为您的“聚焦”数据库重新建立索引，提高搜索速度和质量。" : "Reindex Spotlight for faster search."
                    )
                }
                .padding(.top, 20)
                
                Spacer()
                
                Button(action: {
                    withAnimation { currentState = .selection }
                }) {
                    Text(loc.currentLanguage == .chinese ? "查看 7 个任务..." : "View 7 tasks...")
                        .font(.headline)
                        .foregroundColor(.black)
                        .padding(.horizontal, 24)
                        .padding(.vertical, 12)
                        .background(Color.cyan)
                        .cornerRadius(8)
                }
                .buttonStyle(.plain)
            }
            .padding(60)
            
            // Right Image
            Image(systemName: "list.clipboard.fill") // Placeholder for 3D Checklist Image
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 300)
                .foregroundColor(.white.opacity(0.2))
                .overlay(
                    Image(systemName: "wrench.adjustable.fill")
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 150)
                        .foregroundColor(.white)
                        .offset(x: 50, y: 50)
                )
        }
    }
    
    // MARK: - Selection View
    var selectionView: some View {
        HStack {
            // Left: List
            VStack(alignment: .leading) {
                Button(action: {
                    withAnimation { currentState = .initial }
                }) {
                    HStack {
                        Image(systemName: "chevron.left")
                        Text(loc.L("back")) // Ensure "back" key exists or use literal
                    }
                    .foregroundColor(.white.opacity(0.7))
                }
                .buttonStyle(.plain)
                .padding(.bottom, 20)
                
                ScrollView {
                    VStack(spacing: 16) {
                        ForEach(MaintenanceTask.allCases) { task in
                            MaintenanceTaskRow(task: task, isSelected: true) // Logic to toggle selection needed later
                        }
                    }
                }
            }
            .padding(40)
            .frame(width: 400)
            
            // Right: Description
            VStack(alignment: .leading, spacing: 20) {
                Text(loc.currentLanguage == .chinese ? "维护" : "Maintenance")
                    .font(.headline)
                    .foregroundColor(.white.opacity(0.7))
                
                Text(loc.currentLanguage == .chinese ? "释放 RAM" : "Free RAM") // Dynamic based on selection
                    .font(.largeTitle)
                    .fontWeight(.bold)
                    .foregroundColor(.white)
                
                Text(loc.currentLanguage == .chinese ? "您的 Mac 的内存经常被占满..." : "Your Mac's memory is often full...")
                    .foregroundColor(.white.opacity(0.8))
                    .lineLimit(nil)
                
                Spacer()
                
                Text(loc.currentLanguage == .chinese ? "上次运行日期: 从未" : "Last ran: Never")
                    .foregroundColor(.white.opacity(0.5))
                    .padding(.bottom, 20)
                
                Button(action: {
                    withAnimation { currentState = .running }
                    performMaintenance()
                }) {
                    Text(loc.currentLanguage == .chinese ? "运行" : "Run")
                        .font(.title3)
                        .fontWeight(.semibold)
                        .frame(width: 120, height: 120)
                        .background(Circle().fill(Color.white.opacity(0.1)))
                        .overlay(
                            Circle().stroke(Color.white.opacity(0.3), lineWidth: 1)
                        )
                        .foregroundColor(.white)
                }
                .buttonStyle(.plain)
                .frame(maxWidth: .infinity)
            }
            .padding(40)
            .background(Color.black.opacity(0.2))
        }
    }
    
    // MARK: - Running View
    var runningView: some View {
        VStack {
            Spacer()
            
            ZStack {
                // Checklist Icon Animation
                Image(systemName: "list.clipboard.fill")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 200, height: 250)
                    .foregroundColor(.pink)
                    .opacity(0.8)
                
                Image(systemName: "wrench.adjustable.fill")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 100)
                    .foregroundColor(.white)
                    .offset(x: 40, y: 40)
            }
            .padding(.bottom, 60)
            
            Text(loc.currentLanguage == .chinese ? "正在执行维护任务..." : "Running maintenance tasks...")
                .font(.title)
                .fontWeight(.bold)
                .foregroundColor(.white)
            
            HStack {
                Image(systemName: "memorychip")
                    .foregroundColor(.cyan)
                    .font(.title2)
                Text(loc.currentLanguage == .chinese ? "释放 RAM" : "Freeing RAM") // Dynamic
                    .font(.title3)
                    .foregroundColor(.white)
                Spacer().frame(width: 20)
                Text(loc.currentLanguage == .chinese ? "正在运行..." : "Running...")
                    .foregroundColor(.white.opacity(0.7))
                ProgressView()
                    .progressViewStyle(CircularProgressViewStyle(tint: .white))
                    .scaleEffect(0.6)
            }
            .padding(.top, 20)
            .padding(.horizontal, 30)
            .padding(.vertical, 16)
            .background(Color.black.opacity(0.2))
            .cornerRadius(12)
            
            Spacer()
            
            Button(action: {
                // Stop logic
            }) {
                Text(loc.currentLanguage == .chinese ? "停止" : "Stop")
                    .foregroundColor(.white)
                    .frame(width: 80, height: 80)
                    .background(Circle().fill(Color.white.opacity(0.1)))
            }
            .buttonStyle(.plain)
            .padding(.bottom, 40)
        }
    }
    
    // MARK: - Finished View
    var finishedView: some View {
        VStack(spacing: 30) {
            Spacer()
            
            Text(loc.currentLanguage == .chinese ? "完成" : "Done")
                .font(.system(size: 48, weight: .bold))
                .foregroundColor(.white)
            
            HStack {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.green)
                    .font(.title)
                
                Text(loc.currentLanguage == .chinese ? "7 个任务" : "7 tasks")
                    .font(.title2)
                    .fontWeight(.bold)
                    .foregroundColor(.white)
                
                Text(loc.currentLanguage == .chinese ? "已完成" : "completed")
                    .font(.title2)
                    .foregroundColor(.white.opacity(0.8))
            }
            
            Text(loc.currentLanguage == .chinese ? "您的 Mac 现在运行起来应该更加顺畅。" : "Your Mac should run smoother now.")
                .foregroundColor(.white.opacity(0.7))
            
            Button(action: {
                // Share logic or Restart
                currentState = .initial
            }) {
                HStack {
                    Image(systemName: "square.and.arrow.up")
                    Text(loc.currentLanguage == .chinese ? "分享成果" : "Share Result")
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 12)
                .background(Color.white.opacity(0.1))
                .cornerRadius(8)
                .foregroundColor(.white)
            }
            .buttonStyle(.plain)
            
            Spacer()
            
            Button(loc.currentLanguage == .chinese ? "查看日志" : "View Log") {
                // View Log
            }
            .buttonStyle(.plain)
            .foregroundColor(.white)
            .padding(.bottom, 40)
        }
        .frame(width: 600)
    }
    
    // Logic Placeholder
    func performMaintenance() {
        Task {
            // Simulation
            try? await Task.sleep(nanoseconds: 3 * 1_000_000_000)
            await MainActor.run {
                currentState = .finished
            }
        }
    }
}

// MARK: - Subviews

struct MaintenanceFeatureRow: View {
    let icon: String
    let title: String
    let description: String
    
    var body: some View {
        HStack(spacing: 20) {
            Image(systemName: icon)
                .font(.largeTitle)
                .foregroundColor(.white.opacity(0.6))
                .frame(width: 40)
            
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)
                    .foregroundColor(.white)
                Text(description)
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.6))
                    .lineLimit(2)
            }
        }
    }
}

struct MaintenanceTaskRow: View {
    let task: MaintenanceTask
    @State var isSelected: Bool
    
    var body: some View {
        HStack(spacing: 16) {
            Button(action: { isSelected.toggle() }) {
                Image(systemName: isSelected ? "checkmark.circle" : "circle")
                    .font(.title2)
                    .foregroundColor(.white.opacity(0.8))
            }
            .buttonStyle(.plain)
            
            Image(systemName: task.icon)
                .frame(width: 32, height: 32)
                .padding(8)
                .background(Color.blue)
                .cornerRadius(8)
                .foregroundColor(.white)
            
            Text(task.title)
                .font(.body)
                .foregroundColor(.white)
            
            Spacer()
        }
        .padding(10)
        .background(Color.white.opacity(0.05))
        .cornerRadius(8)
    }
}

enum MaintenanceTask: String, CaseIterable, Identifiable {
    case freeRam
    case purgeableSpace
    case flushDns
    case speedUpMail
    case rebuildSpotlight
    case repairPermissions
    case timeMachine
    
    var id: String { rawValue }
    
    var title: String {
        switch self {
        case .freeRam: return "释放 RAM"
        case .purgeableSpace: return "释放可清除空间"
        case .flushDns: return "刷新 DNS 缓存"
        case .speedUpMail: return "加速邮件"
        case .rebuildSpotlight: return "为“聚焦”重建索引"
        case .repairPermissions: return "修复磁盘权限"
        case .timeMachine: return "时间机器快照瘦身"
        }
    }
    
    var icon: String {
        switch self {
        case .freeRam: return "memorychip"
        case .purgeableSpace: return "server.rack"
        case .flushDns: return "network"
        case .speedUpMail: return "envelope"
        case .rebuildSpotlight: return "magnifyingglass"
        case .repairPermissions: return "lock.shield"
        case .timeMachine: return "clock.arrow.circlepath"
        }
    }
}
