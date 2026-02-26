# Mac Storage Cleanup

<p align="center">
  <img src="https://img.shields.io/badge/platform-macOS-blue.svg" alt="Platform">
  <img src="https://img.shields.io/badge/swift-5.9-orange.svg" alt="Swift">
  <img src="https://img.shields.io/badge/license-MIT-green.svg" alt="License">
</p>

A powerful, native macOS application to clean up your Mac and free up storage space. Built with SwiftUI and designed with safety and user control in mind.

## ✨ Features

### 🧹 Comprehensive Cleanup
- **System & Application Caches** - Remove cached data from system and applications
- **Browser Caches** - Clean Safari, Chrome, Firefox, Edge, and Brave caches
- **Developer Tool Caches** - Clear Xcode, CocoaPods, npm, Gradle, and more
- **AI Agent Caches** - Remove caches from ChatGPT, Claude, Cursor, and other AI tools
- **Temporary Files** - Delete temporary files and logs
- **Large Files** - Find and manage files over 100MB
- **Old Files** - Identify files not accessed in over a year

### 🛡️ Safety First
- **Safe List Protection** - Critical system files are automatically protected
- **Backup Support** - Optional backup before deletion
- **Move to Trash** - Files moved to Trash by default (recoverable)
- **Debug Mode** - Test cleanup operations without actually deleting files
- **Preview Before Cleanup** - Review exactly what will be deleted

### 📊 Storage Analysis
- **Visual Storage Breakdown** - See what's taking up space
- **Category Analysis** - Detailed breakdown by file type
- **Real-time Scanning** - Live progress during storage analysis
- **File Browser** - Explore your filesystem with size information

### ⚙️ Advanced Features
- **Scheduled Cleanup** - Automatic cleanup on daily, weekly, or monthly basis
- **Customizable Thresholds** - Set your own definitions for "large" and "old" files
- **Selective Cleanup** - Choose exactly what to clean
- **Application Management** - Uninstall apps with associated files
- **Backup Management** - Restore from previous cleanup backups

## 📸 Screenshots

*Coming soon*

## 🚀 Installation

### Requirements
- macOS 13.0 (Ventura) or later
- Xcode 15.0 or later (for building from source)

### Building from Source

1. Clone the repository:
```bash
git clone https://github.com/yourusername/MacCleaner.git
cd MacCleaner
```

2. Open the project in Xcode:
```bash
open MacStorageCleanupApp.xcodeproj
```

3. Build and run:
   - Select the `MacStorageCleanupApp` scheme
   - Press `Cmd + R` to build and run

### Download Pre-built Binary

*Coming soon - Check the [Releases](https://github.com/yourusername/MacCleaner/releases) page*

## 🔒 Permissions

The app requires the following permissions to function properly:

- **Full Disk Access** - Required to scan and clean cache directories
  - Go to System Settings > Privacy & Security > Full Disk Access
  - Add Mac Storage Cleanup to the list

## 💡 Usage

### Quick Start

1. **Launch the app** and grant necessary permissions
2. **Scan Your Mac** - Click the menu icon and select "Scan Storage"
3. **Review Results** - Browse the cleanup candidates by category
4. **Select Items** - Choose what you want to clean
5. **Clean Up** - Click "Clean Up Selected" and confirm

### Debug Mode

For testing without actually deleting files:

1. Open Preferences (gear icon)
2. Go to the "Cleanup" tab
3. Enable "Debug Mode (simulate deletions)"
4. All cleanup operations will be simulated

### Scheduled Cleanup

1. Open Preferences
2. Go to the "Scheduled" tab
3. Enable scheduled cleanup
4. Choose frequency and categories
5. The app will automatically clean safe categories

## 🏗️ Architecture

The project is organized into two main components:

### MacStorageCleanup (Core Library)
- **FileScanner** - Scans filesystem for cleanup candidates
- **CacheManager** - Manages cache discovery and cleanup
- **CleanupEngine** - Handles safe file deletion with rollback
- **SafeListManager** - Protects critical system files
- **BackupManager** - Creates and manages backups
- **ApplicationManager** - Discovers and uninstalls applications

### MacStorageCleanupApp (UI)
- **SwiftUI Views** - Modern, native macOS interface
- **ViewModels** - MVVM architecture for clean separation
- **Services** - Logging, notifications, and coordination

## 🧪 Testing

The project includes comprehensive unit tests:

```bash
# Run all tests
xcodebuild test -scheme MacStorageCleanupApp

# Run specific test suite
xcodebuild test -scheme MacStorageCleanup -only-testing:CacheManagerTests
```

## 🤝 Contributing

Contributions are welcome! Please feel free to submit a Pull Request.

1. Fork the repository
2. Create your feature branch (`git checkout -b feature/AmazingFeature`)
3. Commit your changes (`git commit -m 'Add some AmazingFeature'`)
4. Push to the branch (`git push origin feature/AmazingFeature`)
5. Open a Pull Request

### Development Guidelines

- Follow Swift style guidelines
- Add unit tests for new features
- Update documentation as needed
- Test on multiple macOS versions if possible

## 📝 License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## ⚠️ Disclaimer

This application deletes files from your system. While it includes safety features and protections:

- Always review what will be deleted before confirming
- Use the backup feature for important cleanups
- Test with Debug Mode first if unsure
- The developers are not responsible for data loss

## 🙏 Acknowledgments

- Built with SwiftUI and modern macOS APIs
- Inspired by the need for a safe, transparent Mac cleanup tool
- Thanks to the Swift community for excellent tools and libraries

## 📧 Contact

- GitHub Issues: [Report a bug or request a feature](https://github.com/yourusername/MacCleaner/issues)
- Email: your.email@example.com

## 🗺️ Roadmap

- [ ] Duplicate file finder
- [ ] Download folder cleanup
- [ ] Smart recommendations based on usage patterns
- [ ] Export cleanup reports
- [ ] Menu bar app mode
- [ ] Localization support

---

Made with ❤️ for the macOS community
