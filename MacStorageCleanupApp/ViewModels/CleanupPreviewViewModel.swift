import SwiftUI
import Foundation

/// View model for the cleanup preview dialog
/// Manages file selection state and category grouping
/// Validates Requirements 9.1, 9.2, 9.3
@MainActor
class CleanupPreviewViewModel: ObservableObject {
    @Published var categoryGroups: [CategoryGroup] = []
    @Published private var files: [CleanupCandidateData]
    
    /// Represents a group of files organized by category
    struct CategoryGroup: Identifiable {
        let id = UUID()
        let category: CleanupCandidateData.CleanupCategoryType
        var files: [CleanupCandidateData]
        
        var selectedCount: Int {
            files.filter { $0.isSelected }.count
        }
        
        var totalSize: Int64 {
            files.filter { $0.isSelected }.reduce(0) { $0 + $1.size }
        }
        
        var formattedSize: String {
            ByteCountFormatter.string(fromByteCount: totalSize, countStyle: .file)
        }
        
        var allSelected: Bool {
            !files.isEmpty && files.allSatisfy { $0.isSelected }
        }
        
        var someSelected: Bool {
            !allSelected && files.contains { $0.isSelected }
        }
    }
    
    init(selectedFiles: [CleanupCandidateData]) {
        self.files = selectedFiles
        self.categoryGroups = Self.groupFilesByCategory(selectedFiles)
    }
    
    // MARK: - Computed Properties
    
    /// Total number of selected files across all categories
    /// Validates Requirement 9.1: Display preview of all files that will be affected
    var selectedCount: Int {
        files.filter { $0.isSelected }.count
    }
    
    /// Total size of all selected files
    /// Validates Requirement 9.2: Show total space that will be freed
    var totalSize: Int64 {
        files.filter { $0.isSelected }.reduce(0) { $0 + $1.size }
    }
    
    /// Formatted total size string
    var formattedTotalSize: String {
        ByteCountFormatter.string(fromByteCount: totalSize, countStyle: .file)
    }
    
    /// Returns all currently selected files for cleanup operation
    var selectedFiles: [CleanupCandidateData] {
        files.filter { $0.isSelected }
    }
    
    // MARK: - Selection Management
    
    /// Toggles selection for an entire category
    /// Validates Requirement 9.3: Allow deselection of entire categories
    func toggleCategory(_ category: CleanupCandidateData.CleanupCategoryType) {
        guard let groupIndex = categoryGroups.firstIndex(where: { $0.category == category }) else {
            return
        }
        
        let group = categoryGroups[groupIndex]
        let newSelectionState = !group.allSelected
        
        // Update files in the group
        for i in categoryGroups[groupIndex].files.indices {
            categoryGroups[groupIndex].files[i].isSelected = newSelectionState
        }
        
        // Update files in the main array
        for i in files.indices {
            if files[i].category == category {
                files[i].isSelected = newSelectionState
            }
        }
        
        objectWillChange.send()
    }
    
    /// Toggles selection for an individual file
    /// Validates Requirement 9.3: Allow deselection of individual items
    func toggleFile(_ file: CleanupCandidateData) {
        // Update in main files array
        if let fileIndex = files.firstIndex(where: { $0.id == file.id }) {
            files[fileIndex].isSelected.toggle()
        }
        
        // Update in category groups
        for groupIndex in categoryGroups.indices {
            if let fileIndex = categoryGroups[groupIndex].files.firstIndex(where: { $0.id == file.id }) {
                categoryGroups[groupIndex].files[fileIndex].isSelected.toggle()
            }
        }
        
        objectWillChange.send()
    }
    
    // MARK: - Helper Methods
    
    /// Groups files by their category for organized display
    private static func groupFilesByCategory(_ files: [CleanupCandidateData]) -> [CategoryGroup] {
        let grouped = Dictionary(grouping: files) { $0.category }
        
        return grouped.map { category, files in
            CategoryGroup(category: category, files: files)
        }.sorted { $0.category.displayName < $1.category.displayName }
    }
}
