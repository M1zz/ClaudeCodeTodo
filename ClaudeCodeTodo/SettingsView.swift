import SwiftUI
import ServiceManagement

struct SettingsView: View {
    @ObservedObject var todoManager = TodoManager.shared
    @AppStorage("todoFilePath") var savedPath: String = ""
    @AppStorage("autoDetect") var autoDetect: Bool = true
    @AppStorage("showCompletedTasks") var showCompletedTasks: Bool = true
    
    var body: some View {
        TabView {
            generalTab
                .tabItem {
                    Label("General", systemImage: "gear")
                }
            
            aboutTab
                .tabItem {
                    Label("About", systemImage: "info.circle")
                }
        }
        .frame(width: 420, height: 280)
    }
    
    // MARK: - General Tab
    private var generalTab: some View {
        Form {
            Section("File Monitoring") {
                Toggle("Auto-detect todo.md", isOn: $autoDetect)
                    .onChange(of: autoDetect) { newValue in
                        if newValue {
                            todoManager.detectTodoFile()
                        }
                    }
                
                HStack {
                    TextField("File path", text: $savedPath)
                        .textFieldStyle(.roundedBorder)
                        .disabled(autoDetect)
                    
                    Button("Browse") {
                        selectFile()
                    }
                    .disabled(autoDetect)
                }
                
                if !todoManager.watchedPath.isEmpty {
                    HStack(spacing: 6) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.green)
                            .font(.caption)
                        Text(todoManager.watchedPath)
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                }
            }
            
            Section("Display") {
                Toggle("Show completed tasks", isOn: $showCompletedTasks)
            }
        }
        .formStyle(.grouped)
        .padding()
    }
    
    // MARK: - About Tab
    private var aboutTab: some View {
        VStack(spacing: 20) {
            Spacer()
            
            Image(systemName: "checklist")
                .font(.system(size: 56))
                .foregroundStyle(.linearGradient(
                    colors: [.blue, .purple],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ))
            
            VStack(spacing: 4) {
                Text("Claude Code Todo")
                    .font(.title2.bold())
                
                Text("Version 1.0.0")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Text("A floating window to display\nClaude Code's todo.md tasks")
                .font(.callout)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
            
            Spacer()
            
            Text("Made for Claude Code users 🤖")
                .font(.caption)
                .foregroundColor(.secondary.opacity(0.7))
                .padding(.bottom)
        }
        .frame(maxWidth: .infinity)
    }
    
    // MARK: - Helpers
    private func selectFile() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.plainText]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.message = "Select your todo.md file"
        
        if panel.runModal() == .OK, let url = panel.url {
            savedPath = url.path
            todoManager.startWatching(path: url.path)
        }
    }
}

#Preview {
    SettingsView()
}
