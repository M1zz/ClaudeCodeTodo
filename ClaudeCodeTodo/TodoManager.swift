import Foundation
import Combine
import SwiftUI

// MARK: - Todo Model
struct TodoItem: Identifiable, Equatable {
    let id = UUID()
    let content: String
    let status: TodoStatus
    let priority: Priority
    let originalLine: String

    enum TodoStatus: String {
        case pending = "pending"
        case inProgress = "in_progress"
        case completed = "completed"

        var icon: String {
            switch self {
            case .pending: return "circle"
            case .inProgress: return "circle.lefthalf.filled"
            case .completed: return "checkmark.circle.fill"
            }
        }
    }

    enum Priority: Int, Comparable {
        case high = 0
        case medium = 1
        case low = 2

        static func < (lhs: Priority, rhs: Priority) -> Bool {
            lhs.rawValue < rhs.rawValue
        }

        var label: String {
            switch self {
            case .high: return "HIGH"
            case .medium: return "MED"
            case .low: return "LOW"
            }
        }
    }
}

// MARK: - Project Model
struct ProjectTodos: Identifiable, Equatable {
    let id: String
    let name: String
    let path: String
    var todos: [TodoItem]
    var lastModified: Date?

    var completedCount: Int {
        todos.filter { $0.status == .completed }.count
    }

    var totalCount: Int {
        todos.count
    }

    var progress: Double {
        totalCount > 0 ? Double(completedCount) / Double(totalCount) : 0
    }
}

// MARK: - Todo Manager
class TodoManager: ObservableObject {
    static let shared = TodoManager()

    @Published var projects: [ProjectTodos] = []
    @Published var todos: [TodoItem] = [] // 단일 파일 모드용 (하위 호환)
    @Published var lastUpdated: Date?
    @Published var isWatching: Bool = false
    @Published var watchedPath: String = ""
    @Published var error: String?
    @Published var collapsedProjects: Set<String> = []

    private var fileMonitors: [String: DispatchSourceFileSystemObject] = [:]
    private var directoryMonitors: [String: DispatchSourceFileSystemObject] = [:]
    private var fileDescriptors: [String: Int32] = [:]
    private var dirDescriptors: [String: Int32] = [:]
    private var pollingTimer: Timer?
    private var baseDirectoryMonitor: DispatchSourceFileSystemObject?
    private var baseDirDescriptor: Int32 = -1

    @AppStorage("todoFilePath") var savedPath: String = ""
    @AppStorage("autoDetect") var autoDetect: Bool = true
    @AppStorage("scanBasePath") var scanBasePath: String = ""

    private init() {
        loadCollapsedState()
        if autoDetect {
            detectAllTodoFiles()
        } else if !savedPath.isEmpty {
            startWatching(path: savedPath)
        }

        // 폴링 타이머 시작 (백업용)
        startPolling()
    }

    // MARK: - Collapsed State
    private func loadCollapsedState() {
        // 이전 데이터 형식 문제 방지를 위해 새 키 사용
        guard let data = UserDefaults.standard.data(forKey: "collapsedProjectsV2") else {
            // 기존 키 삭제 (타입 불일치 방지)
            UserDefaults.standard.removeObject(forKey: "collapsedProjects")
            return
        }
        do {
            let decoded = try JSONDecoder().decode(Set<String>.self, from: data)
            collapsedProjects = decoded
        } catch {
            print("Failed to load collapsed state: \(error)")
            UserDefaults.standard.removeObject(forKey: "collapsedProjectsV2")
        }
    }

    private func saveCollapsedState() {
        do {
            let data = try JSONEncoder().encode(collapsedProjects)
            UserDefaults.standard.set(data, forKey: "collapsedProjectsV2")
        } catch {
            print("Failed to save collapsed state: \(error)")
        }
    }

    func toggleCollapsed(projectId: String) {
        if collapsedProjects.contains(projectId) {
            collapsedProjects.remove(projectId)
        } else {
            collapsedProjects.insert(projectId)
        }
        saveCollapsedState()
    }

    func isCollapsed(projectId: String) -> Bool {
        collapsedProjects.contains(projectId)
    }
    
    // MARK: - Auto Detection (Multiple Projects)
    func detectAllTodoFiles() {
        let fileManager = FileManager.default
        var foundPaths: [(path: String, projectName: String, modDate: Date)] = []

        // 기본 검색 경로: ~/Documents/code 또는 사용자 지정 경로
        let basePath: String
        if !scanBasePath.isEmpty {
            basePath = NSString(string: scanBasePath).expandingTildeInPath
        } else {
            basePath = NSHomeDirectory() + "/Documents/code"
        }

        let baseURL = URL(fileURLWithPath: basePath)

        guard fileManager.fileExists(atPath: basePath) else {
            // 폴백: 기존 단일 파일 모드
            detectTodoFile()
            return
        }

        // 프로젝트 폴더들 스캔 (1단계 깊이만)
        if let contents = try? fileManager.contentsOfDirectory(
            at: baseURL,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) {
            for folderURL in contents {
                var isDir: ObjCBool = false
                guard fileManager.fileExists(atPath: folderURL.path, isDirectory: &isDir),
                      isDir.boolValue else { continue }

                let todoPath = folderURL.appendingPathComponent("todo.md").path
                if fileManager.fileExists(atPath: todoPath) {
                    let projectName = folderURL.lastPathComponent
                    let modDate = (try? fileManager.attributesOfItem(atPath: todoPath)[.modificationDate] as? Date) ?? Date.distantPast
                    foundPaths.append((todoPath, projectName, modDate))
                }
            }
        }

        if foundPaths.isEmpty {
            // 폴백: 기존 단일 파일 모드
            detectTodoFile()
            return
        }

        // 수정일 기준 정렬 (최신순)
        foundPaths.sort { $0.modDate > $1.modDate }

        // 모든 프로젝트 감시 시작
        startWatchingMultiple(paths: foundPaths)
    }

    // 기존 단일 파일 감지 (폴백용)
    func detectTodoFile() {
        let fileManager = FileManager.default
        var foundPath: String?
        var latestDate: Date?

        let searchPaths = [
            NSHomeDirectory(),
            NSHomeDirectory() + "/Desktop",
            NSHomeDirectory() + "/Documents",
            NSHomeDirectory() + "/Developer",
            FileManager.default.currentDirectoryPath
        ]

        for basePath in searchPaths {
            let todoPath = basePath + "/todo.md"
            if fileManager.fileExists(atPath: todoPath) {
                if let attrs = try? fileManager.attributesOfItem(atPath: todoPath),
                   let modDate = attrs[.modificationDate] as? Date {
                    if latestDate == nil || modDate > latestDate! {
                        latestDate = modDate
                        foundPath = todoPath
                    }
                }
            }
        }

        if let path = foundPath {
            startWatching(path: path)
        }
    }
    
    // MARK: - File Watching (Multiple Projects)
    func startWatchingMultiple(paths: [(path: String, projectName: String, modDate: Date)]) {
        stopWatching()

        var newProjects: [ProjectTodos] = []

        for item in paths {
            let projectId = item.projectName
            let project = ProjectTodos(
                id: projectId,
                name: item.projectName,
                path: item.path,
                todos: [],
                lastModified: item.modDate
            )
            newProjects.append(project)

            // 파일 감시 시작
            watchFileForProject(at: item.path, projectId: projectId)

            // 디렉토리 감시
            let directory = (item.path as NSString).deletingLastPathComponent
            watchDirectoryForProject(at: directory, projectId: projectId, filePath: item.path)
        }

        // 베이스 폴더 감시 (새 프로젝트 감지)
        let basePath: String
        if !scanBasePath.isEmpty {
            basePath = NSString(string: scanBasePath).expandingTildeInPath
        } else {
            basePath = NSHomeDirectory() + "/Documents/code"
        }
        watchBaseDirectory(at: basePath)

        DispatchQueue.main.async {
            self.projects = newProjects
            self.isWatching = true
            self.error = nil

            // 모든 파일 파싱
            for project in newProjects {
                self.parseFileForProject(at: project.path, projectId: project.id)
            }
        }
    }

    // 베이스 폴더 감시 (새 프로젝트/todo.md 감지)
    private func watchBaseDirectory(at path: String) {
        let work = { [weak self] in
            guard let self = self else { return }

            if self.baseDirDescriptor != -1 {
                close(self.baseDirDescriptor)
                self.baseDirDescriptor = -1
            }
            self.baseDirectoryMonitor?.cancel()
            self.baseDirectoryMonitor = nil

            let fd = open(path, O_EVTONLY)
            guard fd != -1 else {
                print("Failed to open base directory: \(path)")
                return
            }
            self.baseDirDescriptor = fd

            let queue = DispatchQueue.global(qos: .utility)
            let monitor = DispatchSource.makeFileSystemObjectSource(
                fileDescriptor: fd,
                eventMask: [.write, .link],
                queue: queue
            )

            monitor.setEventHandler { [weak self] in
                // 새 폴더나 파일이 생기면 재스캔
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    self?.checkForNewProjects()
                }
            }

            monitor.setCancelHandler {
                close(fd)
            }

            monitor.resume()
            self.baseDirectoryMonitor = monitor
        }

        if Thread.isMainThread {
            work()
        } else {
            DispatchQueue.main.async(execute: work)
        }
    }

    // 새 프로젝트 확인
    private func checkForNewProjects() {
        let fileManager = FileManager.default
        let basePath: String
        if !scanBasePath.isEmpty {
            basePath = NSString(string: scanBasePath).expandingTildeInPath
        } else {
            basePath = NSHomeDirectory() + "/Documents/code"
        }

        let baseURL = URL(fileURLWithPath: basePath)
        guard let contents = try? fileManager.contentsOfDirectory(
            at: baseURL,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else { return }

        var hasNewProject = false

        for folderURL in contents {
            var isDir: ObjCBool = false
            guard fileManager.fileExists(atPath: folderURL.path, isDirectory: &isDir),
                  isDir.boolValue else { continue }

            let todoPath = folderURL.appendingPathComponent("todo.md").path
            let projectName = folderURL.lastPathComponent

            // 이미 감시 중인 프로젝트인지 확인
            let isExisting = projects.contains { $0.id == projectName }

            if fileManager.fileExists(atPath: todoPath) && !isExisting {
                // 새 프로젝트 발견
                hasNewProject = true
                let modDate = (try? fileManager.attributesOfItem(atPath: todoPath)[.modificationDate] as? Date) ?? Date()

                let newProject = ProjectTodos(
                    id: projectName,
                    name: projectName,
                    path: todoPath,
                    todos: [],
                    lastModified: modDate
                )

                DispatchQueue.main.async {
                    self.projects.append(newProject)
                    self.projects.sort { ($0.lastModified ?? .distantPast) > ($1.lastModified ?? .distantPast) }
                }

                // 파일 감시 시작
                watchFileForProject(at: todoPath, projectId: projectName)
                watchDirectoryForProject(at: folderURL.path, projectId: projectName, filePath: todoPath)
                parseFileForProject(at: todoPath, projectId: projectName)
            }
        }

        if hasNewProject {
            DispatchQueue.main.async {
                self.lastUpdated = Date()
            }
        }
    }

    // 단일 파일 모드 (하위 호환)
    func startWatching(path: String) {
        stopWatching()

        let expandedPath = NSString(string: path).expandingTildeInPath
        watchedPath = expandedPath
        savedPath = expandedPath

        if FileManager.default.fileExists(atPath: expandedPath) {
            parseFile(at: expandedPath)
            watchFileForProject(at: expandedPath, projectId: "_single")
        }

        let directory = (expandedPath as NSString).deletingLastPathComponent
        watchDirectoryForProject(at: directory, projectId: "_single", filePath: expandedPath)

        isWatching = true
        error = nil
    }

    private func watchFileForProject(at path: String, projectId: String) {
        // 메인 스레드에서 안전하게 실행
        let work = { [weak self] in
            guard let self = self else { return }

            // 기존 모니터 정리
            if let existingFd = self.fileDescriptors[projectId], existingFd != -1 {
                close(existingFd)
                self.fileDescriptors[projectId] = nil
            }
            self.fileMonitors[projectId]?.cancel()
            self.fileMonitors[projectId] = nil

            // 파일 열기
            let fd = open(path, O_EVTONLY)
            guard fd != -1 else {
                print("Failed to open file: \(path)")
                return
            }
            self.fileDescriptors[projectId] = fd

            let queue = DispatchQueue.global(qos: .utility)
            let monitor = DispatchSource.makeFileSystemObjectSource(
                fileDescriptor: fd,
                eventMask: [.write, .delete, .rename, .extend],
                queue: queue
            )

            monitor.setEventHandler { [weak self] in
                guard let self = self else { return }
                let events = monitor.data

                if events.contains(.delete) || events.contains(.rename) {
                    DispatchQueue.main.async {
                        if let index = self.projects.firstIndex(where: { $0.id == projectId }) {
                            self.projects[index].todos = []
                        }
                    }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                        if FileManager.default.fileExists(atPath: path) {
                            self.watchFileForProject(at: path, projectId: projectId)
                            self.parseFileForProject(at: path, projectId: projectId)
                        }
                    }
                } else {
                    self.parseFileForProject(at: path, projectId: projectId)
                }
            }

            monitor.setCancelHandler {
                close(fd)
            }

            monitor.resume()
            self.fileMonitors[projectId] = monitor
        }

        if Thread.isMainThread {
            work()
        } else {
            DispatchQueue.main.async(execute: work)
        }
    }

    private func watchDirectoryForProject(at path: String, projectId: String, filePath: String) {
        let work = { [weak self] in
            guard let self = self else { return }

            // 기존 모니터 정리
            if let existingFd = self.dirDescriptors[projectId], existingFd != -1 {
                close(existingFd)
                self.dirDescriptors[projectId] = nil
            }
            self.directoryMonitors[projectId]?.cancel()
            self.directoryMonitors[projectId] = nil

            let fd = open(path, O_EVTONLY)
            guard fd != -1 else {
                print("Failed to open directory: \(path)")
                return
            }
            self.dirDescriptors[projectId] = fd

            let queue = DispatchQueue.global(qos: .utility)
            let monitor = DispatchSource.makeFileSystemObjectSource(
                fileDescriptor: fd,
                eventMask: .write,
                queue: queue
            )

            monitor.setEventHandler { [weak self] in
                if FileManager.default.fileExists(atPath: filePath) {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        self?.parseFileForProject(at: filePath, projectId: projectId)
                        self?.watchFileForProject(at: filePath, projectId: projectId)
                    }
                }
            }

            monitor.setCancelHandler {
                close(fd)
            }

            monitor.resume()
            self.directoryMonitors[projectId] = monitor
        }

        if Thread.isMainThread {
            work()
        } else {
            DispatchQueue.main.async(execute: work)
        }
    }

    private func startPolling() {
        pollingTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            guard let self = self else { return }

            // 멀티 프로젝트 모드
            if !self.projects.isEmpty {
                for project in self.projects {
                    self.parseFileForProject(at: project.path, projectId: project.id)
                }
            }
            // 단일 파일 모드
            else if !self.watchedPath.isEmpty {
                self.parseFile(at: self.watchedPath)
            }
        }
    }

    func stopWatching() {
        for (_, monitor) in fileMonitors {
            monitor.cancel()
        }
        for (_, monitor) in directoryMonitors {
            monitor.cancel()
        }
        baseDirectoryMonitor?.cancel()
        baseDirectoryMonitor = nil
        if baseDirDescriptor != -1 {
            close(baseDirDescriptor)
            baseDirDescriptor = -1
        }
        fileMonitors.removeAll()
        directoryMonitors.removeAll()
        fileDescriptors.removeAll()
        dirDescriptors.removeAll()
        isWatching = false
    }

    func refresh() {
        if !projects.isEmpty {
            for project in projects {
                parseFileForProject(at: project.path, projectId: project.id)
            }
        } else if !watchedPath.isEmpty {
            parseFile(at: watchedPath)
        } else if autoDetect {
            detectAllTodoFiles()
        }
    }

    func rescan() {
        stopWatching()
        projects = []
        todos = []
        detectAllTodoFiles()
    }

    // MARK: - Toggle Todo Status
    func toggleTodoStatus(todo: TodoItem, inFile path: String) {
        guard FileManager.default.fileExists(atPath: path) else { return }

        do {
            let content = try String(contentsOfFile: path, encoding: .utf8)
            var lines = content.components(separatedBy: "\n")

            // 원본 라인 찾기
            if let index = lines.firstIndex(where: { $0 == todo.originalLine }) {
                var line = lines[index]

                // 체크박스 토글
                if line.contains("- [ ]") {
                    line = line.replacingOccurrences(of: "- [ ]", with: "- [x]")
                } else if line.contains("- [x]") || line.contains("- [X]") {
                    line = line.replacingOccurrences(of: "- [x]", with: "- [ ]")
                    line = line.replacingOccurrences(of: "- [X]", with: "- [ ]")
                } else if line.contains("* [ ]") {
                    line = line.replacingOccurrences(of: "* [ ]", with: "* [x]")
                } else if line.contains("* [x]") || line.contains("* [X]") {
                    line = line.replacingOccurrences(of: "* [x]", with: "* [ ]")
                    line = line.replacingOccurrences(of: "* [X]", with: "* [ ]")
                }

                lines[index] = line

                // 파일에 저장
                let newContent = lines.joined(separator: "\n")
                try newContent.write(toFile: path, atomically: true, encoding: .utf8)
            }
        } catch {
            DispatchQueue.main.async {
                self.error = "Failed to toggle: \(error.localizedDescription)"
            }
        }
    }
    
    // MARK: - Parsing
    private func parseFileForProject(at path: String, projectId: String) {
        guard FileManager.default.fileExists(atPath: path) else { return }

        do {
            let content = try String(contentsOfFile: path, encoding: .utf8)
            let parsed = parseTodoContent(content)

            DispatchQueue.main.async {
                if let index = self.projects.firstIndex(where: { $0.id == projectId }) {
                    if self.projects[index].todos != parsed {
                        self.projects[index].todos = parsed
                        self.projects[index].lastModified = Date()
                        self.lastUpdated = Date()
                    }
                }
            }
        } catch {
            DispatchQueue.main.async {
                self.error = "Failed to read \(projectId): \(error.localizedDescription)"
            }
        }
    }

    // 단일 파일 모드용 (하위 호환)
    private func parseFile(at path: String) {
        guard FileManager.default.fileExists(atPath: path) else { return }

        do {
            let content = try String(contentsOfFile: path, encoding: .utf8)
            let parsed = parseTodoContent(content)

            DispatchQueue.main.async {
                if self.todos != parsed {
                    self.todos = parsed
                    self.lastUpdated = Date()
                }
            }
        } catch {
            DispatchQueue.main.async {
                self.error = "Failed to read: \(error.localizedDescription)"
            }
        }
    }
    
    private func parseTodoContent(_ content: String) -> [TodoItem] {
        var items: [TodoItem] = []
        let lines = content.components(separatedBy: .newlines)
        
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else { continue }
            
            var status: TodoItem.TodoStatus = .pending
            var priority: TodoItem.Priority = .medium
            var taskContent = trimmed
            
            // 체크박스 파싱: - [ ], - [x], - [~], - [/] (체크박스 있는 항목만)
            if trimmed.hasPrefix("- [ ]") || trimmed.hasPrefix("* [ ]") {
                status = .pending
                taskContent = String(trimmed.dropFirst(5)).trimmingCharacters(in: .whitespaces)
            } else if trimmed.hasPrefix("- [x]") || trimmed.hasPrefix("- [X]") ||
                      trimmed.hasPrefix("* [x]") || trimmed.hasPrefix("* [X]") {
                status = .completed
                taskContent = String(trimmed.dropFirst(5)).trimmingCharacters(in: .whitespaces)
            } else if trimmed.hasPrefix("- [~]") || trimmed.hasPrefix("- [/]") ||
                      trimmed.hasPrefix("* [~]") || trimmed.hasPrefix("* [/]") {
                status = .inProgress
                taskContent = String(trimmed.dropFirst(5)).trimmingCharacters(in: .whitespaces)
            } else {
                // 체크박스 없는 항목은 무시 (하위 설명, 일반 리스트 등)
                continue
            }

            // 우선순위 파싱
            let priorityPatterns: [(pattern: String, priority: TodoItem.Priority)] = [
                ("[HIGH]", .high), ("[high]", .high), ("🔴", .high), ("!!!", .high), ("❗️", .high),
                ("[LOW]", .low), ("[low]", .low), ("🟢", .low),
                ("[MED]", .medium), ("[med]", .medium), ("🟡", .medium)
            ]
            
            for (pattern, prio) in priorityPatterns {
                if taskContent.contains(pattern) {
                    priority = prio
                    taskContent = taskContent.replacingOccurrences(of: pattern, with: "")
                    break
                }
            }
            
            // 상태 태그 파싱
            let statusPatterns: [(pattern: String, status: TodoItem.TodoStatus)] = [
                ("(in_progress)", .inProgress), ("(in progress)", .inProgress), ("(active)", .inProgress),
                ("(completed)", .completed), ("(done)", .completed), ("(finished)", .completed),
                ("(pending)", .pending), ("(todo)", .pending)
            ]
            
            for (pattern, stat) in statusPatterns {
                if taskContent.lowercased().contains(pattern) {
                    status = stat
                    taskContent = taskContent.replacingOccurrences(of: pattern, with: "", options: .caseInsensitive)
                    break
                }
            }
            
            taskContent = taskContent.trimmingCharacters(in: .whitespaces)

            if !taskContent.isEmpty {
                items.append(TodoItem(
                    content: taskContent,
                    status: status,
                    priority: priority,
                    originalLine: line
                ))
            }
        }

        // 파일에 적힌 순서대로 반환 (정렬 없음)
        return items
    }
}
