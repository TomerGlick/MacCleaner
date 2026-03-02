import SwiftUI

struct StatusMenuView: View {
    @StateObject private var statsService = SystemStatsService.shared
    @State private var machineName = Host.current().localizedName ?? "MacBook"
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            VStack(spacing: 12) {
                Text("Mac Storage Cleanup")
                    .font(.headline)
                    .foregroundColor(.white)
                
                Text(machineName)
                    .font(.subheadline)
                    .foregroundColor(.white.opacity(0.7))
                
                // Laptop Icon
                Image(systemName: "laptopcomputer")
                    .font(.system(size: 40))
                    .foregroundColor(.white.opacity(0.8))
            }
            .padding(.vertical, 20)
            .frame(maxWidth: .infinity)
            .background(
                LinearGradient(
                    colors: [Color.blue.opacity(0.8), Color.cyan.opacity(0.6)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            
            ScrollView {
                VStack(spacing: 16) {
                    // Storage
                    StatCard(
                        icon: "internaldrive",
                        title: "Macintosh HD",
                        subtitle: "Available: \(statsService.availableStorage)",
                        actionText: "Free Up",
                        action: openAppAndScan
                    )
                    
                    HStack(spacing: 12) {
                        // Uptime
                        MiniStatCard(
                            icon: "clock",
                            title: "Uptime",
                            value: statsService.uptime,
                            subtitle: "Running"
                        )
                        
                        // Memory
                        MiniStatCard(
                            icon: "memorychip",
                            title: "Memory",
                            value: statsService.memoryUsed,
                            subtitle: "Pressure: \(Int(statsService.memoryPressure))%"
                        )
                        
                        // CPU
                        MiniStatCard(
                            icon: "cpu",
                            title: "CPU",
                            value: "\(Int(statsService.cpuTemperature))°C",
                            subtitle: "Load: \(Int(statsService.cpuUsage))%"
                        )
                    }
                    
                    HStack(spacing: 12) {
                        // Wi-Fi
                        NetworkStatCard(
                            upload: statsService.networkUpload,
                            download: statsService.networkDownload
                        )
                        
                        // Battery Health
                        MiniStatCard(
                            icon: "heart.fill",
                            title: "Battery Health",
                            value: "\(statsService.batteryMaxCapacity)%",
                            subtitle: statsService.batteryHealth
                        )
                        
                        // Battery
                        MiniStatCard(
                            icon: "battery.100",
                            title: "Battery",
                            value: "\(statsService.batteryLevel)%",
                            subtitle: statsService.batteryState
                        )
                    }
                }
                .padding(16)
            }
            
            // Footer Button
            Button(action: openMainApp) {
                Text("Open Mac Storage Cleanup")
                    .font(.headline)
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.blue)
                    .cornerRadius(8)
            }
            .buttonStyle(.plain)
            .padding()
        }
        .frame(width: 400, height: 600)
        .background(Color(NSColor.windowBackgroundColor))
    }
    
    private func openAppAndScan() {
        // Post notification to trigger scan
        NotificationCenter.default.post(name: NSNotification.Name("StartStorageScan"), object: nil)
        
        // Open main app
        openMainApp()
    }
    
    private func openMainApp() {
        // Close the popover first
        MenuBarManager.shared.togglePopover()
        
        // Activate the app
        NSApp.activate(ignoringOtherApps: true)
        
        // Find or create main window
        let windows = NSApp.windows.filter { window in
            // Look for the main content window (not popover or other utility windows)
            return window.isVisible || window.canBecomeMain
        }
        
        if let mainWindow = windows.first {
            mainWindow.makeKeyAndOrderFront(nil)
        } else {
            // If no window exists, try to create one by sending a notification
            // This will be handled by the app delegate or main window
            NotificationCenter.default.post(name: NSNotification.Name("ShowMainWindow"), object: nil)
        }
    }
}

struct StatCard: View {
    let icon: String
    let title: String
    let subtitle: String
    let actionText: String
    let action: (() -> Void)?
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: icon)
                    .font(.title2)
                    .foregroundColor(.blue)
                
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.headline)
                    Text(subtitle)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                Button(action: {
                    action?()
                }) {
                    Text(actionText)
                        .font(.caption)
                        .foregroundColor(.blue)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Color.blue.opacity(0.1))
                        .cornerRadius(6)
                }
                .buttonStyle(.plain)
                .disabled(action == nil)
            }
        }
        .padding()
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(10)
    }
}

struct MiniStatCard: View {
    let icon: String
    let title: String
    let value: String
    let subtitle: String
    
    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundColor(.blue)
            
            Text(title)
                .font(.caption)
                .foregroundColor(.secondary)
            
            Text(value)
                .font(.title3)
                .fontWeight(.semibold)
            
            Text(subtitle)
                .font(.caption2)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(10)
    }
}

struct NetworkStatCard: View {
    let upload: String
    let download: String
    
    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "wifi")
                .font(.title2)
                .foregroundColor(.blue)
            
            Text("Wi-Fi")
                .font(.caption)
                .foregroundColor(.secondary)
            
            HStack(spacing: 4) {
                Image(systemName: "arrow.up")
                    .font(.caption2)
                Text(upload)
                    .font(.caption)
            }
            
            HStack(spacing: 4) {
                Image(systemName: "arrow.down")
                    .font(.caption2)
                Text(download)
                    .font(.caption)
            }
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(10)
    }
}

#Preview {
    StatusMenuView()
}
