import Foundation
import SwiftUI

// MARK: - Update Checker Service
class UpdateCheckerService: ObservableObject {
    static let shared = UpdateCheckerService()
    
    @Published var hasUpdate = false
    @Published var latestVersion = ""
    @Published var releaseNotes = ""
    @Published var downloadURL: URL?
    @Published var isChecking = false
    @Published var errorMessage: String?
    
    // GitHub Repo Info
    private let repoOwner = "ddlmanus"
    private let repoName = "MacOptimizer"
    
    var currentVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "3.0.3"
    }
    
    private init() {}
    
    func checkForUpdates() async {
        await MainActor.run {
            self.isChecking = true
            self.errorMessage = nil
        }
        
        let urlString = "https://api.github.com/repos/\(repoOwner)/\(repoName)/releases/latest"
        guard let url = URL(string: urlString) else {
            await MainActor.run {
                self.isChecking = false
                self.errorMessage = "Invalid URL"
            }
            return
        }
        
        do {
            var request = URLRequest(url: url)
            request.timeoutInterval = 10
            
            let (data, response) = try await URLSession.shared.data(for: request)
            
            guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
                throw URLError(.badServerResponse)
            }
            
            let release = try JSONDecoder().decode(GitHubRelease.self, from: data)
            
            await MainActor.run {
                self.isChecking = false
                // Remove 'v' prefix if present for comparison
                let serverVer = release.tag_name.replacingOccurrences(of: "v", with: "")
                let localVer = self.currentVersion.replacingOccurrences(of: "v", with: "")
                
                if serverVer.compare(localVer, options: .numeric) == .orderedDescending {
                    self.hasUpdate = true
                    self.latestVersion = release.tag_name
                    self.releaseNotes = release.body
                    self.downloadURL = URL(string: release.html_url)
                } else {
                    self.hasUpdate = false
                    self.latestVersion = release.tag_name
                }
            }
        } catch {
            await MainActor.run {
                self.isChecking = false
                self.errorMessage = error.localizedDescription
                // Fallback for demo/testing if network fails or repo private
                print("Update check failed: \(error.localizedDescription)")
            }
        }
    }
}

// MARK: - GitHub Release Model
struct GitHubRelease: Codable {
    let tag_name: String
    let html_url: String
    let body: String
}
