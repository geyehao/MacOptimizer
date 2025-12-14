import SwiftUI

// MARK: - Deep Clean States
enum DeepCleanState {
    case initial
    case scanning
    case results
    case cleaning
    case finished
}

struct DeepCleanView: View {
    @Binding var selectedModule: AppModule
    @ObservedObject private var scanner = ScanServiceManager.shared.deepCleanScanner
    @State private var viewState: DeepCleanState = .initial
    @State private var showingDetails = false
    @State private var selectedCategoryForDetails: DeepCleanCategory?
    @ObservedObject private var loc = LocalizationManager.shared
    
    // Alert States
    @State private var showCleanConfirmation = false
    @State private var cleanResult: (count: Int, size: Int64)?
    
    var body: some View {
        ZStack {
            // Background
            
            VStack {
                 switch viewState {
                 case .initial:
                     initialView
                 case .scanning:
                     scanningView
                 case .results:
                     resultsView
                 case .cleaning:
                     cleaningView
                 case .finished:
                     finishedView
                 }
            }
        }
        .onAppear {
            // Sync state if already scanning
            if scanner.isScanning {
                viewState = .scanning
            } else if scanner.isCleaning {
                viewState = .cleaning
            } else if scanner.totalSize > 0 && viewState == .initial {
                 viewState = .results // Resume results if available
            }
        }
        .onChange(of: scanner.isScanning) { isScanning in
             if isScanning { viewState = .scanning }
             else if scanner.totalSize > 0 { viewState = .results }
        }
        .onChange(of: scanner.isCleaning) { isCleaning in
             if isCleaning { viewState = .cleaning }
             else if cleanResult != nil { viewState = .finished }
        }
        .sheet(isPresented: $showingDetails) {
            DeepCleanDetailView(scanner: scanner, category: selectedCategoryForDetails, isPresented: $showingDetails)
        }
        .confirmationDialog(loc.L("confirm_clean"), isPresented: $showCleanConfirmation) {
            Button(loc.currentLanguage == .chinese ? "开始清理" : "Start Cleaning", role: .destructive) {
                Task {
                    let result = await scanner.cleanSelected()
                    cleanResult = result
                }
            }
            Button(loc.L("cancel"), role: .cancel) {}
        } message: {
            Text(loc.currentLanguage == .chinese ? 
                 "确定要清理选中的 \(scanner.selectedCount) 个项目吗？总大小 \(ByteCountFormatter.string(fromByteCount: scanner.selectedSize, countStyle: .file))" :
                 "Are you sure you want to clean \(scanner.selectedCount) selected items? Total size: \(ByteCountFormatter.string(fromByteCount: scanner.selectedSize, countStyle: .file))")
        }
    }
    
    // MARK: - 1. Initial View (初始化页面)
    var initialView: some View {
        VStack(spacing: 0) {
            Spacer()
            
            // Icon
            ZStack {
                Circle()
                    .fill(LinearGradient(colors: [Color.cyan.opacity(0.3), Color.blue.opacity(0.3)], startPoint: .topLeading, endPoint: .bottomTrailing))
                    .frame(width: 180, height: 180)
                
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 80))
                    .foregroundColor(.cyan)
            }
            .padding(.bottom, 40)
            
            // Title
            Text(loc.currentLanguage == .chinese ? "深度系统清理" : "Deep System Clean")
                .font(.system(size: 28, weight: .semibold))
                .foregroundColor(.white)
                .padding(.bottom, 12)
            
            Text(loc.currentLanguage == .chinese ? 
                 "扫描整个 Mac 的大文件、垃圾文件、缓存、日志及应用残留。" :
                 "Scan your entire Mac for large files, junk, caches, logs, and leftovers.")
                .font(.body)
                .foregroundColor(.secondaryText)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 60)
                .padding(.bottom, 60)
            
            Spacer()
            
            // Start Button (using CircularActionButton)
            CircularActionButton(
                title: loc.currentLanguage == .chinese ? "扫描" : "Scan",
                gradient: CircularActionButton.blueGradient,
                action: {
                    Task { await scanner.startScan() }
                }
            )
            .padding(.bottom, 60)
        }
    }
    
    // MARK: - 2. Scanning View (扫描中页面)
    var scanningView: some View {
        VStack(spacing: 0) {
            // Title
            HStack {
                Text(loc.currentLanguage == .chinese ? "深度清理" : "Deep Clean")
                    .font(.title2)
                    .foregroundColor(.white)
            }
            .padding(.top, 20)
            
            Spacer()
            
            // Dashboard Grid
            HStack(spacing: 30) {
                ForEach(DeepCleanCategory.allCases, id: \.self) { category in
                    scanningCategoryCard(for: category)
                }
            }
            .padding(.horizontal, 40)
            
            Spacer()
            
            // Stop Button with Progress
            CircularActionButton(
                title: loc.currentLanguage == .chinese ? "停止" : "Stop",
                gradient: CircularActionButton.stopGradient,
                progress: scanner.scanProgress,
                showProgress: true,
                scanSize: ByteCountFormatter.string(fromByteCount: scanner.totalSize, countStyle: .file),
                action: {
                    scanner.stopScan()
                    viewState = .initial
                }
            )
            .padding(.bottom, 20)
            
            // Current scanning path (at bottom, like Smart Scan)
            Text(scanner.currentScanningUrl)
                .font(.caption)
                .foregroundColor(.secondaryText.opacity(0.6))
                .lineLimit(1)
                .truncationMode(.middle)
                .padding(.horizontal, 40)
                .padding(.bottom, 20)
        }
    }
    
    // MARK: - 4. Cleaning View (清理中页面 - Dashboard Style)
    var cleaningView: some View {
        VStack(spacing: 0) {
            Spacer()
            
            // Dashboard Grid for Cleaning
            HStack(spacing: 30) {
                ForEach(DeepCleanCategory.allCases, id: \.self) { category in
                    cleaningCategoryCard(for: category)
                }
            }
            .padding(.horizontal, 40)
            
            Spacer()
            
            VStack(spacing: 16) {
                // Display current item being cleaned
                Text(scanner.currentCleaningItem)
                    .font(.caption)
                    .foregroundColor(.secondaryText)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .frame(height: 20)
                
                Text(scanner.scanStatus)
                    .font(.headline)
                    .foregroundColor(.white)
                
                // Progress Ring
                ZStack {
                    Circle()
                        .stroke(Color.white.opacity(0.2), lineWidth: 4)
                        .frame(width: 60, height: 60)
                    
                    Circle()
                        .trim(from: 0, to: scanner.cleaningProgress)
                        .stroke(Color(hex: "00E8A8"), lineWidth: 4)
                        .frame(width: 60, height: 60)
                        .rotationEffect(.degrees(-90))
                    
                    Text(String(format: "%.0f%%", scanner.cleaningProgress * 100))
                        .font(.caption)
                        .foregroundColor(.white)
                }
            }
            .padding(.bottom, 80)
        }
    }
    
    func cleaningCategoryCard(for category: DeepCleanCategory) -> some View {
        // Simple logic: if we are cleaning this category, show spinner; if done, checkmark
        // Since granular cleaning progress isn't tracked in scanner yet, we'll confirm 'done' if not selected or if cleaned.
        // For now, simpler visual: Checkmark if NOT selected (skipped) or if cleaned.
        // Spinner if selected and cleaning.
        
        // Improve: Scanner needs 'currentlyCleaningCategory'
        let isSelected = scanner.items.contains { $0.category == category && $0.isSelected }
        
        return VStack(spacing: 16) {
            ZStack {
                Circle()
                    .fill(category.color.opacity(0.1))
                    .frame(width: 80, height: 80)
                
                if isSelected {
                    ProgressView() // Placeholder for actual granular progress
                         .progressViewStyle(CircularProgressViewStyle(tint: category.color))
                         .scaleEffect(1.5)
                } else {
                    Image(systemName: "checkmark")
                        .font(.system(size: 30, weight: .bold)) // Show 'done' or 'skipped'
                        .foregroundColor(.gray.opacity(0.5))
                }
            }
            
            Text(category.localizedName)
                .font(.headline)
                .foregroundColor(.white)
        }
        .frame(width: 140)
    }
    
    func scanningCategoryCard(for category: DeepCleanCategory) -> some View {
        let isCompleted = scanner.completedCategories.contains(category)
        let isScanningThis = !isCompleted && scanner.scanProgress < 1.0 // Simplified logic
        
        return VStack(spacing: 16) {
            ZStack {
                Circle()
                    .fill(category.color.opacity(0.1))
                    .frame(width: 80, height: 80)
                
                if isCompleted {
                    Image(systemName: "checkmark")
                        .font(.system(size: 30, weight: .bold))
                        .foregroundColor(.green)
                } else {
                    Image(systemName: category.icon)
                        .font(.system(size: 36))
                        .foregroundColor(category.color)
                        .scaleEffect(isScanningThis ? 1.1 : 1.0)
                        .animation(isScanningThis ? .easeInOut(duration: 0.8).repeatForever(autoreverses: true) : .default, value: isScanningThis)
                }
            }
            
            VStack(spacing: 4) {
                Text(category.localizedName)
                    .font(.headline)
                    .foregroundColor(.white)
                
                if isCompleted {
                    let size = scanner.items.filter { $0.category == category }.reduce(0) { $0 + $1.size }
                    Text(ByteCountFormatter.string(fromByteCount: size, countStyle: .file))
                        .font(.caption)
                        .foregroundColor(.secondaryText)
                } else {
                    Text(LocalizationManager.shared.currentLanguage == .chinese ? "扫描中..." : "Scanning...")
                        .font(.caption)
                        .foregroundColor(.secondaryText)
                }
            }
        }
        .frame(width: 140)
    }
    
    // MARK: - 3. Results View (扫描结果页面)
    var resultsView: some View {
        VStack(spacing: 0) {
            Spacer()
            
            // Dashboard Grid (Results Mode)
            HStack(spacing: 20) {
                ForEach(DeepCleanCategory.allCases, id: \.self) { category in
                    resultCategoryCard(for: category)
                }
            }
            .padding(.horizontal, 40)
            
            Spacer()
            
            // Bottom Action Bar
            VStack(spacing: 24) {
                VStack(spacing: 8) {
                    Text(LocalizationManager.shared.currentLanguage == .chinese ? "已选择" : "Selected")
                        .font(.caption)
                        .foregroundColor(.secondaryText)
                    Text(ByteCountFormatter.string(fromByteCount: scanner.selectedSize, countStyle: .file))
                        .font(.system(size: 32, weight: .bold))
                        .foregroundColor(.white)
                }
                
                Button(action: {
                    if scanner.selectedCount > 0 {
                        showCleanConfirmation = true
                    }
                }) {
                    Text(LocalizationManager.shared.currentLanguage == .chinese ? "立即清理" : "Clean Now")
                        .font(.headline)
                        .foregroundColor(.white)
                        .frame(width: 200, height: 50)
                        .background(scanner.selectedCount > 0 ? Color.blue : Color.gray.opacity(0.3))
                        .cornerRadius(25)
                        .shadow(color: scanner.selectedCount > 0 ? .blue.opacity(0.4) : .clear, radius: 10, x: 0, y: 5)
                        .scaleEffect(scanner.selectedCount > 0 ? 1.05 : 1.0)
                        .animation(.easeInOut(duration: 1).repeatForever(autoreverses: true), value: scanner.selectedCount > 0)
                }
                .buttonStyle(.plain)
                .disabled(scanner.selectedCount == 0)
                
                Button(action: {
                    viewState = .initial
                    scanner.reset()
                }) {
                    Text(LocalizationManager.shared.currentLanguage == .chinese ? "重新开始" : "Start Over")
                        .font(.subheadline)
                        .foregroundColor(.secondaryText)
                }
                .buttonStyle(.plain)
            }
            .padding(.bottom, 50)
        }
    }
    
    func resultCategoryCard(for category: DeepCleanCategory) -> some View {
        let items = scanner.items.filter { $0.category == category }
        let size = items.reduce(0) { $0 + $1.size }
        
        return VStack(spacing: 16) {
            ZStack {
                Circle()
                    .fill(category.color.opacity(0.1))
                    .frame(width: 80, height: 80)
                
                Image(systemName: category.icon)
                    .font(.system(size: 36))
                    .foregroundColor(category.color)
            }
            
            VStack(spacing: 4) {
                Text(category.localizedName)
                    .font(.headline)
                    .foregroundColor(.white)
                
                Text(ByteCountFormatter.string(fromByteCount: size, countStyle: .file))
                    .font(.subheadline)
                    .bold()
                    .foregroundColor(.white)
                
                Button(action: {
                    selectedCategoryForDetails = category
                    showingDetails = true
                }) {
                    Text(LocalizationManager.shared.currentLanguage == .chinese ? "查看详情" : "Details")
                        .font(.caption)
                        .foregroundColor(.blue)
                        .padding(.vertical, 4)
                        .padding(.horizontal, 12)
                        .background(Color.blue.opacity(0.1))
                        .cornerRadius(12)
                }
                .buttonStyle(.plain)
                .padding(.top, 4)
            }
        }
        .frame(width: 140)
        .padding(.vertical, 20)
        .background(Color.white.opacity(0.02))
        .cornerRadius(16)
    }
    

    
    // MARK: - 5. Finished View (清理完成页面)
    var finishedView: some View {
        VStack(spacing: 30) {
            Spacer()
            
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 100))
                .foregroundColor(.green)
                .shadow(color: .green.opacity(0.5), radius: 20, x: 0, y: 0)
            
            Text(loc.currentLanguage == .chinese ? "清理完成！" : "Cleanup Complete!")
                .font(.largeTitle)
                .fontWeight(.bold)
                .foregroundColor(.white)
            
            if let result = cleanResult {
                VStack(spacing: 12) {
                    Text(loc.currentLanguage == .chinese ? 
                         "成功释放空间：" : "Space Freed:")
                        .font(.headline)
                        .foregroundColor(.secondaryText)
                    
                    Text(ByteCountFormatter.string(fromByteCount: result.size, countStyle: .file))
                        .font(.system(size: 48, weight: .bold))
                        .foregroundStyle(
                            LinearGradient(colors: [.green, .blue], startPoint: .leading, endPoint: .trailing)
                        )
                    
                    Text(loc.currentLanguage == .chinese ? 
                         "删除了 \(result.count) 个不需要的文件" :
                         "Removed \(result.count) unwanted files")
                        .font(.subheadline)
                        .foregroundColor(.secondaryText)
                }
                .padding(.vertical, 20)
            }
            
            Spacer()
            
            Button(action: {
                viewState = .initial
                scanner.reset()
                cleanResult = nil
            }) {
                Text(loc.currentLanguage == .chinese ? "好的" : "Done")
                    .font(.headline)
                    .foregroundColor(.white)
                    .frame(width: 200, height: 50)
                    .background(Color.green)
                    .cornerRadius(25)
            }
            .buttonStyle(.plain)
            .padding(.bottom, 50)
        }
    }
}

// MARK: - 6. Detail View Setup (Split View)
struct DeepCleanDetailView: View {
    @ObservedObject var scanner: DeepCleanScanner
    @State var selectedCategory: DeepCleanCategory? // Local state for sidebar selection
    @Binding var isPresented: Bool
    
    // Binding passed from parent to initialize selection
    var initialCategory: DeepCleanCategory?
    
    init(scanner: DeepCleanScanner, category: DeepCleanCategory?, isPresented: Binding<Bool>) {
        self.scanner = scanner
        self._selectedCategory = State(initialValue: category ?? .junkFiles)
        self._isPresented = isPresented
        self.initialCategory = category
    }
    
    var body: some View {
        HStack(spacing: 0) {
            // Left Sidebar: Categories
            VStack(alignment: .leading, spacing: 0) {
                // Header Back Button
                Button(action: { isPresented = false }) {
                    HStack(spacing: 6) {
                        Image(systemName: "chevron.left")
                        Text(LocalizationManager.shared.currentLanguage == .chinese ? "返回摘要" : "Back")
                    }
                    .foregroundColor(.secondaryText)
                    .padding()
                }
                .buttonStyle(.plain)
                
                Divider().background(Color.white.opacity(0.1))
                
                ScrollView {
                    VStack(spacing: 8) {
                        ForEach(DeepCleanCategory.allCases, id: \.self) { category in
                            categorySidebarRow(category)
                        }
                    }
                    .padding(12)
                }
            }
            .frame(width: 250)
            .background(Color.black.opacity(0.3))
            
            Divider().background(Color.white.opacity(0.1))
            
            // Right Content: Items
            VStack(spacing: 0) {
                // Header
                HStack {
                    if let category = selectedCategory {
                        Text(category.localizedName)
                            .font(.title2)
                            .bold()
                            .foregroundColor(.white)
                        
                        Spacer()
                        
                        Text(LocalizationManager.shared.currentLanguage == .chinese ?
                             "排序方式: 大小" : "Sort by: Size")
                        .font(.caption)
                        .foregroundColor(.secondaryText)
                    }
                }
                .padding()
                .background(Color.white.opacity(0.05))
                
                // Item List
                if let category = selectedCategory {
                    let items = scanner.items.filter { $0.category == category }
                    
                    if items.isEmpty {
                        Spacer()
                        Text(LocalizationManager.shared.currentLanguage == .chinese ? "无项目" : "No items")
                            .foregroundColor(.secondaryText)
                        Spacer()
                    } else {
                        List {
                            ForEach(items) { item in
                                DeepCleanItemRow(item: item, scanner: scanner)
                            }
                        }
                        .listStyle(.plain)
                    }
                } else {
                    Spacer()
                }
                
                // Footer
                HStack {
                    Spacer()
                    if let category = selectedCategory {
                        let items = scanner.items.filter { $0.category == category }
                         Text("\(items.count) items")
                            .font(.caption)
                            .foregroundColor(.secondaryText)
                    }
                }
                .padding(8)
                .background(Color.white.opacity(0.05))
            }
            .background(Color.black.opacity(0.1))
        }
        .frame(width: 800, height: 600)
        .background(Color(nsColor: .windowBackgroundColor)) // Ensure opaque background
        .onAppear {
            if let initial = initialCategory {
                selectedCategory = initial
            } else if selectedCategory == nil {
                // Default to first category with items, or just first category
                selectedCategory = DeepCleanCategory.allCases.first
            }
        }
    }
    
    func categorySidebarRow(_ category: DeepCleanCategory) -> some View {
        let items = scanner.items.filter { $0.category == category }
        let size = items.reduce(0) { $0 + $1.size }
        let isSelected = selectedCategory == category
        
        return Button(action: {
            selectedCategory = category
        }) {
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(category.color.opacity(0.2))
                        .frame(width: 32, height: 32)
                    Image(systemName: category.icon)
                        .foregroundColor(category.color)
                        .font(.system(size: 14))
                }
                
                Text(category.localizedName)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.white)
                
                Spacer()
                
                Text(ByteCountFormatter.string(fromByteCount: size, countStyle: .file))
                    .font(.system(size: 12))
                    .foregroundColor(.secondaryText)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(isSelected ? Color.white.opacity(0.1) : Color.clear)
            .cornerRadius(8)
        }
        .buttonStyle(.plain)
    }
}

struct DeepCleanItemRow: View {
    let item: DeepCleanItem
    @ObservedObject var scanner: DeepCleanScanner
    
    var body: some View {
        HStack {
            Toggle("", isOn: Binding(
                get: { item.isSelected },
                set: { _ in scanner.toggleSelection(for: item) }
            ))
            .toggleStyle(CheckboxStyle())
            .labelsHidden()
            
            if item.category == .appResiduals {
                Image(systemName: "app.fill")
                    .foregroundColor(.blue)
                    .frame(width: 20)
            } else {
                 Image(systemName: "doc.fill")
                    .foregroundColor(.secondary)
                    .frame(width: 20)
            }
            
            VStack(alignment: .leading, spacing: 2) {
                Text(item.name)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.primary)
                Text(item.url.path)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            
            Spacer()
            
            Text(item.formattedSize)
                .font(.system(size: 12))
                .foregroundColor(.secondary)
            
            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundColor(.secondary.opacity(0.5))
        }
        .padding(.vertical, 4)
    }
}
