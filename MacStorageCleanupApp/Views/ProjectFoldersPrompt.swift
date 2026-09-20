import SwiftUI
import AppKit

/// Asks once where the user keeps their code, instead of guessing.
///
/// The app needs to know which toolchain versions a project pins — an NDK named in a
/// `build.gradle`, a Gradle version in a wrapper file — so those versions are never
/// offered for deletion while something still depends on them. Without an answer it falls
/// back to probing conventional folder names, which finds code in `~/Develop` and misses
/// it anywhere else.
///
/// Declining is a real answer: the fallback still works, it is just less reliable, and the
/// question is not asked again.
struct ProjectFoldersPrompt: View {
    @Environment(\.dismiss) private var dismiss
    /// Folders chosen so far.
    @State private var folders: [String]
    /// Called with the chosen folders, or `nil` when the user backs out.
    ///
    /// The distinction matters when editing an existing selection: "Cancel" has to leave
    /// the current folders alone, where an empty array would wipe them.
    let onFinish: ([String]?) -> Void

    init(initialFolders: [String] = [], onFinish: @escaping ([String]?) -> Void) {
        _folders = State(initialValue: initialFolders)
        self.onFinish = onFinish
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "folder.badge.questionmark")
                    .font(.largeTitle)
                    .foregroundColor(.blue)

                VStack(alignment: .leading, spacing: 4) {
                    Text("Where do you keep your projects?")
                        .font(.title3)
                        .fontWeight(.semibold)

                    Text("Optional, and the app only reads from them.")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
            }

            Text("""
                 Old toolchain versions are usually safe to delete — unless one of your \
                 projects still pins it. Pointing the app at your code lets it read those \
                 pins and keep the versions you depend on.

                 Skip this and it will guess at the usual folder names instead, which \
                 misses anything kept somewhere else.
                 """)
                .font(.callout)
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if !folders.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(folders, id: \.self) { folder in
                        HStack(spacing: 6) {
                            Image(systemName: "folder.fill")
                                .foregroundColor(.secondary)
                            Text((folder as NSString).abbreviatingWithTildeInPath)
                                .font(.callout)
                                .lineLimit(1)
                                .truncationMode(.middle)
                            Spacer()
                            Button {
                                folders.removeAll { $0 == folder }
                            } label: {
                                Image(systemName: "minus.circle")
                            }
                            .buttonStyle(.borderless)
                        }
                    }
                }
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(NSColor.controlBackgroundColor))
                .cornerRadius(8)
            }

            HStack {
                Button(folders.isEmpty ? "Choose Folders…" : "Add Another…") {
                    chooseFolders()
                }

                Spacer()

                // Declining is a first-class answer, not a dead end.
                Button(folders.isEmpty ? "Not Now" : "Cancel") {
                    onFinish(nil)
                    dismiss()
                }

                Button("Use These Folders") {
                    onFinish(folders)
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(folders.isEmpty)
            }
        }
        .padding(20)
        .frame(width: 480)
    }

    private func chooseFolders() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = false
        panel.allowsMultipleSelection = true
        panel.message = "Select the folders that hold your projects"
        panel.prompt = "Use Folder"

        guard panel.runModal() == .OK else { return }

        for url in panel.urls where !folders.contains(url.path) {
            folders.append(url.path)
        }
    }
}

#Preview {
    ProjectFoldersPrompt { _ in }
}

#Preview("Editing an existing selection") {
    ProjectFoldersPrompt(initialFolders: ["/Users/example/Develop"]) { _ in }
}
