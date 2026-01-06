import Cocoa
import SwiftUI

class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // App started
        // Reset the force quit flag so the app defaults to background mode on this launch
        UserDefaults.standard.set(false, forKey: "ForceQuitApp")
    }
    
    // 拦截退出事件
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        if UserDefaults.standard.bool(forKey: "ForceQuitApp") {
            return .terminateNow
        }
        
        // 隐藏主窗口
        NSApp.windows.forEach { window in
            // 不要隐藏 Menu Bar 的窗口 (通常 MenuBarWindow 是自定义的，如果不确定，只隐藏标准的 Window)
            if let windowClass = NSClassFromString("MenuBarWindow"), window.isKind(of: windowClass) {
                // Keep MenuBar Window
            } else if window.isVisible {
                window.orderOut(nil)
            }
        }
        
        // 切换到后台模式 (隐藏 Dock 图标)
        NSApp.setActivationPolicy(.accessory)
        
        return .terminateCancel
    }
    
    // 防止关闭最后一个窗口时退出
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return false
    }
    
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        // 点击 Dock 图标时的行为 (如果 Dock 图标还在的话)
        // 或者通过 Spotlight / Finder 再次打开应用
        
        NSApp.setActivationPolicy(.regular)
        
        // 找到主窗口并显示
        MenuBarManager.shared.openMainApp()
        
        return true
    }
}
