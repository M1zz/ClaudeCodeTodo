import SwiftUI

struct FloatingTodoView: View {
    @EnvironmentObject var todoManager: TodoManager
    @State private var isCompact = false
    @State private var hoveredId: UUID?
    
    var body: some View {
        VStack(spacing: 0) {
            headerView
            Divider()
            
            if todoManager.todos.isEmpty {
                emptyStateView
            } else {
                todoListView
            }
            
            footerView
        }
        .frame(minWidth: 280, maxWidth: 500, minHeight: 200, maxHeight: 800)
        .background(Color(NSColor.windowBackgroundColor))
    }
    
    // MARK: - Header
    private var headerView: some View {
        HStack(spacing: 10) {
            Image(systemName: "checklist")
                .foregroundColor(.accentColor)
                .font(.title3)
            
            Text("Claude Tasks")
                .font(.headline)
            
            Spacer()
            
            if !todoManager.todos.isEmpty {
                progressView
            }
            
            Button(action: { withAnimation { isCompact.toggle() } }) {
                Image(systemName: isCompact ? "rectangle.expand.vertical" : "rectangle.compress.vertical")
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
            .help(isCompact ? "Expand view" : "Compact view")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }
    
    private var progressView: some View {
        let completed = todoManager.todos.filter { $0.status == .completed }.count
        let total = todoManager.todos.count
        let progress = total > 0 ? Double(completed) / Double(total) : 0
        
        return HStack(spacing: 6) {
            Text("\(completed)/\(total)")
                .font(.caption.monospacedDigit())
                .foregroundColor(.secondary)
            
            ZStack {
                Circle()
                    .stroke(Color.secondary.opacity(0.2), lineWidth: 2.5)
                Circle()
                    .trim(from: 0, to: progress)
                    .stroke(Color.green, style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                    .rotationEffect(.degrees(-90))
            }
            .frame(width: 16, height: 16)
        }
    }
    
    // MARK: - Todo List
    private var todoListView: some View {
        ScrollView {
            LazyVStack(spacing: 1) {
                ForEach(todoManager.todos) { todo in
                    TodoRowView(
                        todo: todo,
                        isCompact: isCompact,
                        isHovered: hoveredId == todo.id
                    )
                    .onHover { hovering in
                        withAnimation(.easeInOut(duration: 0.15)) {
                            hoveredId = hovering ? todo.id : nil
                        }
                    }
                }
            }
            .padding(.vertical, 6)
        }
    }
    
    // MARK: - Empty State
    private var emptyStateView: some View {
        VStack(spacing: 16) {
            Spacer()
            
            Image(systemName: "tray")
                .font(.system(size: 48))
                .foregroundColor(.secondary.opacity(0.4))
            
            VStack(spacing: 6) {
                Text("No tasks yet")
                    .font(.headline)
                    .foregroundColor(.secondary)
                
                if todoManager.watchedPath.isEmpty {
                    Text("Select a todo.md file to watch")
                        .font(.caption)
                        .foregroundColor(.secondary.opacity(0.8))
                    
                    Button("Select File...") {
                        selectFile()
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .padding(.top, 8)
                } else {
                    Text("Waiting for tasks...")
                        .font(.caption)
                        .foregroundColor(.secondary.opacity(0.8))
                }
            }
            
            Spacer()
        }
        .frame(maxWidth: .infinity)
        .padding()
    }
    
    // MARK: - Footer
    private var footerView: some View {
        HStack(spacing: 8) {
            // 감시 상태
            HStack(spacing: 4) {
                Circle()
                    .fill(todoManager.isWatching ? Color.green : Color.orange)
                    .frame(width: 6, height: 6)
                
                if !todoManager.watchedPath.isEmpty {
                    Text(shortenPath(todoManager.watchedPath))
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
            
            Spacer()
            
            // 마지막 업데이트
            if let updated = todoManager.lastUpdated {
                Text(timeAgo(updated))
                    .font(.caption2)
                    .foregroundColor(.secondary.opacity(0.7))
            }
            
            // 새로고침
            Button(action: { todoManager.refresh() }) {
                Image(systemName: "arrow.clockwise")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
            .help("Refresh")
            
            // 파일 선택
            Button(action: selectFile) {
                Image(systemName: "folder")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
            .help("Select file...")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color(NSColor.controlBackgroundColor).opacity(0.5))
    }
    
    // MARK: - Helpers
    private func selectFile() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.plainText]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.message = "Select your todo.md file"
        
        if panel.runModal() == .OK, let url = panel.url {
            todoManager.startWatching(path: url.path)
        }
    }
    
    private func shortenPath(_ path: String) -> String {
        let home = NSHomeDirectory()
        var shortened = path
        if shortened.hasPrefix(home) {
            shortened = "~" + shortened.dropFirst(home.count)
        }
        // 너무 길면 파일명만
        if shortened.count > 35 {
            return ".../" + (path as NSString).lastPathComponent
        }
        return shortened
    }
    
    private func timeAgo(_ date: Date) -> String {
        let seconds = Int(-date.timeIntervalSinceNow)
        if seconds < 5 { return "now" }
        if seconds < 60 { return "\(seconds)s" }
        if seconds < 3600 { return "\(seconds / 60)m" }
        return "\(seconds / 3600)h"
    }
}

// MARK: - Todo Row View
struct TodoRowView: View {
    let todo: TodoItem
    let isCompact: Bool
    let isHovered: Bool
    
    var body: some View {
        HStack(spacing: 10) {
            // Status icon
            statusIcon
            
            // Priority badge
            if todo.priority == .high && todo.status != .completed {
                priorityBadge
            }
            
            // Content
            Text(todo.content)
                .font(isCompact ? .callout : .body)
                .foregroundColor(contentColor)
                .strikethrough(todo.status == .completed, color: .secondary.opacity(0.5))
                .lineLimit(isCompact ? 1 : 3)
            
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, isCompact ? 6 : 10)
        .background(rowBackground)
        .contentShape(Rectangle())
    }
    
    private var statusIcon: some View {
        Image(systemName: todo.status.icon)
            .font(.system(size: isCompact ? 14 : 16, weight: .medium))
            .foregroundColor(statusColor)
    }
    
    private var priorityBadge: some View {
        Text("!")
            .font(.caption2.bold())
            .foregroundColor(.white)
            .frame(width: 14, height: 14)
            .background(Color.red)
            .clipShape(Circle())
    }
    
    private var rowBackground: some View {
        RoundedRectangle(cornerRadius: 6)
            .fill(isHovered ? Color.accentColor.opacity(0.08) : Color.clear)
    }
    
    private var statusColor: Color {
        switch todo.status {
        case .pending: return .secondary
        case .inProgress: return .blue
        case .completed: return .green
        }
    }
    
    private var contentColor: Color {
        switch todo.status {
        case .completed: return .secondary.opacity(0.7)
        case .inProgress: return .primary
        case .pending: return .primary.opacity(0.9)
        }
    }
}

#Preview {
    FloatingTodoView()
        .environmentObject(TodoManager.shared)
        .frame(width: 340, height: 420)
}
