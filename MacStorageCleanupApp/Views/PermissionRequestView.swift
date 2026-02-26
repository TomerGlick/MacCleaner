import SwiftUI
import AppKit

struct PermissionRequestView: View {
    @Binding var hasPermission: Bool
    @State private var isChecking = false
    
    var body: some View {
        VStack(spacing: 24) {
            // Icon
            Image(systemName: "lock.shield.fill")
                .font(.system(size: 64))
                .foregroundColor(.blue)
            
            // Title
            Text("Full Disk Access Required")
                .font(.title)
                .fontWeight(.bold)
            
            // Description
            VStack(spacing: 12) {
                Text("Mac Storage Cleanup needs Full Disk Access to scan and clean your storage.")
                    .multilineTextAlignment(.center)
                    .foregroundColor(.secondary)
                
                Text("This permission allows the app to:")
                    .font(.headline)
                    .padding(.top, 8)
                
                VStack(alignment: .leading, spacing: 8) {
                    PermissionItem(text: "Scan cache directories")
                    PermissionItem(text: "Calculate storage usage")
                    PermissionItem(text: "Clean temporary files safely")
                }
                .padding(.horizontal, 40)
            }
            .frame(maxWidth: 500)
            
            // Instructions
            VStack(spacing: 16) {
                Text("To grant permission:")
                    .font(.headline)
                
                VStack(alignment: .leading, spacing: 8) {
                    InstructionStep(number: 1, text: "Click 'Open System Settings' below")
                    InstructionStep(number: 2, text: "Find 'Mac Storage Cleanup' in the list")
                    InstructionStep(number: 3, text: "Toggle the switch to enable access")
                    InstructionStep(number: 4, text: "Return here and click 'Check Permission'")
                }
                .padding(.horizontal, 40)
            }
            
            // Buttons
            VStack(spacing: 12) {
                Button(action: openSystemSettings) {
                    HStack {
                        Image(systemName: "gear")
                        Text("Open System Settings")
                    }
                    .frame(maxWidth: 300)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                
                Button(action: checkPermission) {
                    HStack {
                        if isChecking {
                            ProgressView()
                                .scaleEffect(0.8)
                                .frame(width: 16, height: 16)
                        } else {
                            Image(systemName: "checkmark.circle")
                        }
                        Text("Check Permission")
                    }
                    .frame(maxWidth: 300)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
            }
            .padding(.top, 8)
        }
        .padding(40)
        .frame(width: 600, height: 700)
    }
    
    private func openSystemSettings() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles")!
        NSWorkspace.shared.open(url)
    }
    
    private func checkPermission() {
        isChecking = true
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            hasPermission = checkFullDiskAccess()
            isChecking = false
        }
    }
    
    private func checkFullDiskAccess() -> Bool {
        // Try to access a protected directory
        let testPath = NSHomeDirectory() + "/Library/Safari"
        let fileManager = FileManager.default
        
        // Try to list contents of Safari directory
        do {
            _ = try fileManager.contentsOfDirectory(atPath: testPath)
            return true
        } catch {
            return false
        }
    }
}

struct PermissionItem: View {
    let text: String
    
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundColor(.green)
            Text(text)
                .font(.subheadline)
        }
    }
}

struct InstructionStep: View {
    let number: Int
    let text: String
    
    var body: some View {
        HStack(spacing: 12) {
            Text("\(number)")
                .font(.caption)
                .fontWeight(.bold)
                .foregroundColor(.white)
                .frame(width: 24, height: 24)
                .background(Circle().fill(Color.blue))
            
            Text(text)
                .font(.subheadline)
        }
    }
}
