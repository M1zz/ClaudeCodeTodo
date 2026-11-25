import SwiftUI

struct FloatingTodoView: View {
    @EnvironmentObject var todoManager: TodoManager
    @State private var isCompact = false
    @State private var hoveredId: UUID?
    @State private var hoveredProjectId: String?

    private var hasProjects: Bool {
        !todoManager.projects.isEmpty
    }

    private var totalTodos: Int {
        todoManager.projects.reduce(0) { $0 + $1.totalCount }
    }

    private var completedTodos: Int {
        todoManager.projects.reduce(0) { $0 + $1.completedCount }
    }

    var body: some View {
        VStack(spacing: 0) {
            headerView
            Divider()

            if hasProjects {
                projectListView
            } else if !todoManager.todos.isEmpty {
                todoListView
            } else {
                emptyStateView
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

            if hasProjects {
                Text("\(todoManager.projects.count) projects")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.secondary.opacity(0.1))
                    .cornerRadius(4)
            }

            Spacer()

            if hasProjects && totalTodos > 0 {
                progressViewMultiple
            } else if !todoManager.todos.isEmpty {
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

    private var progressViewMultiple: some View {
        let progress = totalTodos > 0 ? Double(completedTodos) / Double(totalTodos) : 0

        return HStack(spacing: 6) {
            Text("\(completedTodos)/\(totalTodos)")
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
    
    // MARK: - Project List View (Multiple Projects)
    private var projectListView: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(todoManager.projects) { project in
                    ProjectSectionView(
                        project: project,
                        isCollapsed: todoManager.isCollapsed(projectId: project.id),
                        isCompact: isCompact,
                        hoveredId: $hoveredId,
                        isHovered: hoveredProjectId == project.id,
                        onToggle: {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                todoManager.toggleCollapsed(projectId: project.id)
                            }
                        }
                    )
                    .onHover { hovering in
                        hoveredProjectId = hovering ? project.id : nil
                    }

                    if project.id != todoManager.projects.last?.id {
                        Divider()
                            .padding(.horizontal, 12)
                    }
                }
            }
            .padding(.vertical, 6)
        }
    }

    // MARK: - Todo List (Single File Mode)
    private var todoListView: some View {
        ScrollView {
            LazyVStack(spacing: 1) {
                ForEach(todoManager.todos) { todo in
                    TodoRowView(
                        todo: todo,
                        projectPath: todoManager.watchedPath,
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

                if hasProjects {
                    Text("~/Documents/code")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                } else if !todoManager.watchedPath.isEmpty {
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

            // 재스캔
            Button(action: { todoManager.rescan() }) {
                Image(systemName: "arrow.triangle.2.circlepath")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
            .help("Rescan all projects")

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
        if seconds < 5 { return "방금" }
        if seconds < 60 { return "\(seconds)초 전" }
        if seconds < 3600 { return "\(seconds / 60)분 전" }
        return "\(seconds / 3600)시간 전"
    }
}

// MARK: - Todo Row View
struct TodoRowView: View {
    let todo: TodoItem
    let projectPath: String
    let isCompact: Bool
    let isHovered: Bool
    @State private var showCopied = false

    var body: some View {
        HStack(spacing: 10) {
            // Status icon (클릭하면 토글)
            Button {
                toggleTodoStatus()
            } label: {
                statusIcon
            }
            .buttonStyle(.plain)
            .help("클릭하여 완료/미완료 토글")

            // Priority badge
            if todo.priority == .high && todo.status != .completed {
                priorityBadge
            }

            // Content (클릭하면 복사)
            Text(todo.content)
                .font(isCompact ? .callout : .body)
                .foregroundColor(contentColor)
                .strikethrough(todo.status == .completed, color: .secondary.opacity(0.5))
                .lineLimit(isCompact ? 1 : 3)
                .onTapGesture {
                    copyToClipboard(todo.content)
                    withAnimation(.easeInOut(duration: 0.2)) {
                        showCopied = true
                    }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            showCopied = false
                        }
                    }
                }

            Spacer(minLength: 0)

            // 복사 피드백
            if showCopied {
                HStack(spacing: 2) {
                    Image(systemName: "checkmark")
                        .font(.caption2)
                    Text("복사됨")
                        .font(.caption2)
                }
                .foregroundColor(.green)
                .transition(.opacity.combined(with: .scale))
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, isCompact ? 6 : 10)
        .background(rowBackground)
        .contentShape(Rectangle())
    }

    private func copyToClipboard(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    private func toggleTodoStatus() {
        TodoManager.shared.toggleTodoStatus(todo: todo, inFile: projectPath)
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

// MARK: - Project Section View
struct ProjectSectionView: View {
    let project: ProjectTodos
    let isCollapsed: Bool
    let isCompact: Bool
    @Binding var hoveredId: UUID?
    let isHovered: Bool
    let onToggle: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            // Section Header
            Button(action: onToggle) {
                HStack(spacing: 8) {
                    Image(systemName: isCollapsed ? "chevron.right" : "chevron.down")
                        .font(.caption.bold())
                        .foregroundColor(.secondary)
                        .frame(width: 12)

                    Image(systemName: "folder.fill")
                        .font(.caption)
                        .foregroundColor(.accentColor)

                    Text(project.name)
                        .font(.subheadline.bold())
                        .foregroundColor(.primary)

                    // 진행 중 표시 (최근 5분 이내 수정 + 미완료 항목 있음)
                    if isProjectActive {
                        HStack(spacing: 3) {
                            Circle()
                                .fill(Color.blue)
                                .frame(width: 6, height: 6)
                            Text("진행 중")
                                .font(.caption2)
                        }
                        .foregroundColor(.blue)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.blue.opacity(0.1))
                        .cornerRadius(4)
                    }

                    // 마지막 수정 시간
                    if let lastMod = project.lastModified {
                        Text(timeAgo(lastMod))
                            .font(.caption2)
                            .foregroundColor(.secondary.opacity(0.7))
                    }

                    Spacer()

                    // Progress
                    HStack(spacing: 4) {
                        Text("\(project.completedCount)/\(project.totalCount)")
                            .font(.caption2.monospacedDigit())
                            .foregroundColor(.secondary)

                        ZStack {
                            Circle()
                                .stroke(Color.secondary.opacity(0.2), lineWidth: 2)
                            Circle()
                                .trim(from: 0, to: project.progress)
                                .stroke(progressColor, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                                .rotationEffect(.degrees(-90))
                        }
                        .frame(width: 12, height: 12)
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(isHovered ? Color.secondary.opacity(0.08) : Color.clear)
                )
            }
            .buttonStyle(.plain)

            // Todos (when expanded) - 최대 7개만 표시
            if !isCollapsed {
                VStack(spacing: 1) {
                    ForEach(Array(project.todos.prefix(7))) { todo in
                        TodoRowView(
                            todo: todo,
                            projectPath: project.path,
                            isCompact: isCompact,
                            isHovered: hoveredId == todo.id
                        )
                        .padding(.leading, 16)
                        .onHover { hovering in
                            withAnimation(.easeInOut(duration: 0.15)) {
                                hoveredId = hovering ? todo.id : nil
                            }
                        }
                    }

                    // 7개 초과 시 "더 보기" 버튼
                    if project.todos.count > 7 {
                        Button {
                            openTodoFile()
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "ellipsis")
                                Text("\(project.todos.count - 7)개 더 보기")
                                    .font(.caption)
                                Image(systemName: "arrow.up.right.square")
                                    .font(.caption2)
                            }
                            .foregroundColor(.secondary)
                            .padding(.vertical, 6)
                            .padding(.horizontal, 14)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.leading, 16)
                        }
                        .buttonStyle(.plain)
                        .onHover { hovering in
                            if hovering {
                                NSCursor.pointingHand.push()
                            } else {
                                NSCursor.pop()
                            }
                        }
                    }
                }
                .padding(.bottom, 6)
            }
        }
    }

    private func openTodoFile() {
        NSWorkspace.shared.open(URL(fileURLWithPath: project.path))
    }

    // 진행 중 여부: 최근 5분 이내 수정 + 미완료 항목 있음
    private var isProjectActive: Bool {
        guard let lastMod = project.lastModified else { return false }
        let recentlyModified = -lastMod.timeIntervalSinceNow < 300 // 5분
        let hasPendingTodos = project.todos.contains { $0.status != .completed }
        return recentlyModified && hasPendingTodos
    }

    private var progressColor: Color {
        if project.progress >= 1.0 {
            return .green
        } else if project.progress >= 0.5 {
            return .blue
        } else {
            return .orange
        }
    }

    private func timeAgo(_ date: Date) -> String {
        let seconds = Int(-date.timeIntervalSinceNow)
        if seconds < 5 { return "방금" }
        if seconds < 60 { return "\(seconds)초 전" }
        if seconds < 3600 { return "\(seconds / 60)분 전" }
        return "\(seconds / 3600)시간 전"
    }
}

#Preview {
    FloatingTodoView()
        .environmentObject(TodoManager.shared)
        .frame(width: 340, height: 420)
}
