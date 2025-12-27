import Foundation
import Combine

class SystemMonitorService: ObservableObject {
    @Published var cpuUsage: Double = 0.0
    @Published var memoryUsage: Double = 0.0 // Percentage
    @Published var memoryUsedString: String = "0 GB"
    @Published var memoryTotalString: String = "0 GB"
    
    // Network Speed Monitoring
    @Published var downloadSpeed: Double = 0.0 // bytes per second
    @Published var uploadSpeed: Double = 0.0   // bytes per second
    @Published var downloadSpeedHistory: [Double] = Array(repeating: 0, count: 20)
    @Published var uploadSpeedHistory: [Double] = Array(repeating: 0, count: 20)
    
    private var lastBytesReceived: UInt64 = 0
    private var lastBytesSent: UInt64 = 0
    private var lastNetworkCheck: Date = Date()
    
    private var timer: Timer?
    
    init() {
        startMonitoring()
    }
    
    func startMonitoring() {
        updateStats()
        timer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { [weak self] _ in
            self?.updateStats()
        }
    }
    
    func stopMonitoring() {
        timer?.invalidate()
        timer = nil
    }
    
    // 格式化网络速度
    func formatSpeed(_ bytesPerSecond: Double) -> String {
        if bytesPerSecond >= 1_000_000_000 {
            return String(format: "%.1f GB/s", bytesPerSecond / 1_000_000_000)
        } else if bytesPerSecond >= 1_000_000 {
            return String(format: "%.1f MB/s", bytesPerSecond / 1_000_000)
        } else if bytesPerSecond >= 1_000 {
            return String(format: "%.1f KB/s", bytesPerSecond / 1_000)
        } else {
            return String(format: "%.0f B/s", bytesPerSecond)
        }
    }
    
    private func updateStats() {
        // CPU Usage (Simplified using top for now to avoid complex Mach calls issues in pure Swift script context initially, 
        // but robust implementation would use host_processor_info. Let's try to parse top -l 1 output specifically designed for machine reading if possible, 
        // or just standard parsing.)
        // Actually, let's use a simpler bash command approach which is safer/easier to debug in this agent environment.
        // `ps -A -o %cpu | awk '{s+=$1} END {print s}'` gives total CPU usage sum (can be > 100% on multi-core).
        
        let cpuTask = Process()
        cpuTask.launchPath = "/bin/bash"
        cpuTask.arguments = ["-c", "ps -A -o %cpu | awk '{s+=$1} END {print s}'"]
        
        let pipe = Pipe()
        cpuTask.standardOutput = pipe
        
        do {
            try cpuTask.run()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            if let output = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
               let totalCPU = Double(output) {
                // Normalize by core count approximately? Or just show raw. 
                // Let's normalize by active core count to get 0-100% range typically expected by users.
                let coreCount = Double(ProcessInfo.processInfo.activeProcessorCount)
                DispatchQueue.main.async {
                    self.cpuUsage = min((totalCPU / coreCount) / 100.0, 1.0)
                }
            }
        } catch {
            print("CPU Scan Error: \(error)")
        }
        
        // Memory Usage
        // Uses `vm_stat`
        let memTask = Process()
        memTask.launchPath = "/usr/bin/vm_stat"
        
        let memPipe = Pipe()
        memTask.standardOutput = memPipe
        
        do {
            try memTask.run()
            let data = memPipe.fileHandleForReading.readDataToEndOfFile()
            if let output = String(data: data, encoding: .utf8) {
                let lines = output.components(separatedBy: "\n")
                var pageSize: UInt64 = 4096 // Default
                var pagesActive: UInt64 = 0
                var pagesWired: UInt64 = 0
                var pagesCompressed: UInt64 = 0
                
                for line in lines {
                    if line.contains("page size of") {
                        if let last = line.split(separator: " ").last, let size = UInt64(last) {
                            pageSize = size
                        }
                    } else if line.contains("Pages active") {
                        pagesActive = extractPageCount(line)
                    } else if line.contains("Pages wired down") {
                        pagesWired = extractPageCount(line)
                    } else if line.contains("Pages occupied by compressor") {
                        pagesCompressed = extractPageCount(line)
                    }
                }
                
                let totalRAM = ProcessInfo.processInfo.physicalMemory
                let usedRAM = (pagesActive + pagesWired + pagesCompressed) * pageSize
                
                DispatchQueue.main.async {
                    self.memoryUsage = Double(usedRAM) / Double(totalRAM)
                    self.memoryUsedString = ByteCountFormatter.string(fromByteCount: Int64(usedRAM), countStyle: .memory)
                    self.memoryTotalString = ByteCountFormatter.string(fromByteCount: Int64(totalRAM), countStyle: .memory)
                }
            }
        } catch {
            print("Memory Scan Error: \(error)")
        }
        
        // Network Speed - 使用 netstat 获取网络流量
        // 找到 en0 接口中有实际流量的行（第7列 Ibytes > 0）
        let netTask = Process()
        netTask.launchPath = "/bin/bash"
        netTask.arguments = ["-c", "netstat -ib | awk '/en0/ && $7 > 0 {print $7, $10; exit}'"]
        
        let netPipe = Pipe()
        netTask.standardOutput = netPipe
        
        do {
            try netTask.run()
            let data = netPipe.fileHandleForReading.readDataToEndOfFile()
            if let output = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
               !output.isEmpty {
                let parts = output.components(separatedBy: " ").filter { !$0.isEmpty }
                if parts.count >= 2,
                   let bytesIn = UInt64(parts[0]),
                   let bytesOut = UInt64(parts[1]) {
                    
                    let now = Date()
                    let timeDiff = now.timeIntervalSince(lastNetworkCheck)
                    
                    if timeDiff > 0 && lastBytesReceived > 0 {
                        let downloadDelta = bytesIn > lastBytesReceived ? Double(bytesIn - lastBytesReceived) : 0
                        let uploadDelta = bytesOut > lastBytesSent ? Double(bytesOut - lastBytesSent) : 0
                        
                        let downloadRate = downloadDelta / timeDiff
                        let uploadRate = uploadDelta / timeDiff
                        
                        DispatchQueue.main.async {
                            self.downloadSpeed = downloadRate
                            self.uploadSpeed = uploadRate
                            
                            // 更新历史记录 (用于波形图)
                            self.downloadSpeedHistory.removeFirst()
                            self.downloadSpeedHistory.append(downloadRate)
                            self.uploadSpeedHistory.removeFirst()
                            self.uploadSpeedHistory.append(uploadRate)
                        }
                    }
                    
                    lastBytesReceived = bytesIn
                    lastBytesSent = bytesOut
                    lastNetworkCheck = now
                }
            }
        } catch {
            print("Network Scan Error: \(error)")
        }
    }
    
    private func extractPageCount(_ line: String) -> UInt64 {
        let parts = line.components(separatedBy: ":")
        if parts.count == 2 {
            let numberPart = parts[1].replacingOccurrences(of: ".", with: "").trimmingCharacters(in: .whitespaces)
            return UInt64(numberPart) ?? 0
        }
        return 0
    }
}
