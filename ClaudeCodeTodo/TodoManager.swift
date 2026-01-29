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

// MARK: - Todo Manager
class TodoManager: ObservableObject {
    static let shared = TodoManager()
    
    @Published var todos: [TodoItem] = []
    @Published var lastUpdated: Date?
    @Published var isWatching: Bool = false
    @Published var watchedPath: String = ""
    @Published var error: String?
    
    private var fileMonitor: DispatchSourceFileSystemObject?
    private var directoryMonitor: DispatchSourceFileSystemObject?
    private var currentFileDescriptor: Int32 = -1
    private var currentDirDescriptor: Int32 = -1
    private var pollingTimer: Timer?
    
    @AppStorage("todoFilePath") var savedPath: String = ""
    @AppStorage("autoDetect") var autoDetect: Bool = true
    
    private init() {
        if autoDetect {
            detectTodoFile()
        } else if !savedPath.isEmpty {
            startWatching(path: savedPath)
        }
        
        // 폴링 타이머 시작 (백업용)
        startPolling()
    }
    
    // MARK: - Auto Detection
    func detectTodoFile() {
        let fileManager = FileManager.default
        var foundPath: String?
        var latestDate: Date?
        
        // 일반적인 경로들
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
        
        // 홈 디렉토리 하위 검색 (깊이 제한)
        let homeURL = URL(fileURLWithPath: NSHomeDirectory())
        if let enumerator = fileManager.enumerator(
            at: homeURL,
            includingPropertiesForKeys: [.contentModificationDateKey, .isDirectoryKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) {
            for case let fileURL as URL in enumerator {
                // 깊이 제한
                if fileURL.pathComponents.count > homeURL.pathComponents.count + 4 {
                    enumerator.skipDescendants()
                    continue
                }
                
                // node_modules, .git 등 제외
                let skipDirs = ["node_modules", ".git", "Library", "Applications", ".Trash"]
                if skipDirs.contains(fileURL.lastPathComponent) {
                    enumerator.skipDescendants()
                    continue
                }
                
                if fileURL.lastPathComponent == "todo.md" {
                    if let attrs = try? fileManager.attributesOfItem(atPath: fileURL.path),
                       let modDate = attrs[.modificationDate] as? Date {
                        if latestDate == nil || modDate > latestDate! {
                            latestDate = modDate
                            foundPath = fileURL.path
                        }
                    }
                }
            }
        }
        
        if let path = foundPath {
            startWatching(path: path)
        }
    }
    
    // MARK: - File Watching
    func startWatching(path: String) {
        stopWatching()
        
        let expandedPath = NSString(string: path).expandingTildeInPath
        watchedPath = expandedPath
        savedPath = expandedPath
        
        // 파일 존재 시 읽기
        if FileManager.default.fileExists(atPath: expandedPath) {
            parseFile(at: expandedPath)
            watchFile(at: expandedPath)
        }
        
        // 디렉토리 모니터링
        let directory = (expandedPath as NSString).deletingLastPathComponent
        let filename = (expandedPath as NSString).lastPathComponent
        watchDirectory(at: directory, forFile: filename)
        
        isWatching = true
        error = nil
    }
    
    private func watchFile(at path: String) {
        if currentFileDescriptor != -1 {
            close(currentFileDescriptor)
        }
        
        currentFileDescriptor = open(path, O_EVTONLY)
        guard currentFileDescriptor != -1 else { return }
        
        let queue = DispatchQueue.global(qos: .utility)
        fileMonitor = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: currentFileDescriptor,
            eventMask: [.write, .delete, .rename, .extend],
            queue: queue
        )
        
        fileMonitor?.setEventHandler { [weak self] in
            guard let self = self else { return }
            let events = self.fileMonitor?.data ?? []
            
            if events.contains(.delete) || events.contains(.rename) {
                DispatchQueue.main.async {
                    self.todos = []
                }
                // 파일 재생성 대기
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    if FileManager.default.fileExists(atPath: path) {
                        self.watchFile(at: path)
                        self.parseFile(at: path)
                    }
                }
            } else {
                self.parseFile(at: path)
            }
        }
        
        fileMonitor?.setCancelHandler { [weak self] in
            if let fd = self?.currentFileDescriptor, fd != -1 {
                close(fd)
                self?.currentFileDescriptor = -1
            }
        }
        
        fileMonitor?.resume()
    }
    
    private func watchDirectory(at path: String, forFile filename: String) {
        currentDirDescriptor = open(path, O_EVTONLY)
        guard currentDirDescriptor != -1 else { return }
        
        let queue = DispatchQueue.global(qos: .utility)
        directoryMonitor = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: currentDirDescriptor,
            eventMask: .write,
            queue: queue
        )
        
        let fullPath = (path as NSString).appendingPathComponent(filename)
        
        directoryMonitor?.setEventHandler { [weak self] in
            if FileManager.default.fileExists(atPath: fullPath) {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    self?.parseFile(at: fullPath)
                    self?.watchFile(at: fullPath)
                }
            }
        }
        
        directoryMonitor?.setCancelHandler { [weak self] in
            if let fd = self?.currentDirDescriptor, fd != -1 {
                close(fd)
                self?.currentDirDescriptor = -1
            }
        }
        
        directoryMonitor?.resume()
    }
    
    private func startPolling() {
        pollingTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            guard let self = self, !self.watchedPath.isEmpty else { return }
            self.parseFile(at: self.watchedPath)
        }
    }
    
    func stopWatching() {
        fileMonitor?.cancel()
        directoryMonitor?.cancel()
        fileMonitor = nil
        directoryMonitor = nil
        isWatching = false
    }
    
    func refresh() {
        if !watchedPath.isEmpty {
            parseFile(at: watchedPath)
        } else if autoDetect {
            detectTodoFile()
        }
    }
    
    // MARK: - Parsing
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
            
            // 체크박스 파싱: - [ ], - [x], - [~], - [/]
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
            } else if trimmed.hasPrefix("- ") {
                taskContent = String(trimmed.dropFirst(2))
            } else if trimmed.hasPrefix("* ") {
                taskContent = String(trimmed.dropFirst(2))
            } else if let match = trimmed.range(of: #"^\d+\.\s+"#, options: .regularExpression) {
                taskContent = String(trimmed[match.upperBound...])
            } else {
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
        
        // 정렬: 미완료 → 진행중 → 완료, 같은 상태면 우선순위순
        return items.sorted { item1, item2 in
            let statusOrder: [TodoItem.TodoStatus: Int] = [.inProgress: 0, .pending: 1, .completed: 2]
            let order1 = statusOrder[item1.status] ?? 1
            let order2 = statusOrder[item2.status] ?? 1
            
            if order1 != order2 {
                return order1 < order2
            }
            return item1.priority < item2.priority
        }
    }
}
