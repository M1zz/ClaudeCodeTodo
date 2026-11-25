import SwiftUI

@main
struct ClaudeCodeTodoApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    
    var body: some Scene {
        Settings {
            SettingsView()
        }
    }
}

class AppDelegate: NSObject, NSApplicationDelegate {
    var floatingWindow: NSWindow?
    var statusItem: NSStatusItem?
    let todoManager = TodoManager.shared
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        setupMenuBar()
        setupFloatingWindow()
        
        // Dock 아이콘 숨기기 (메뉴바 앱)
        NSApp.setActivationPolicy(.accessory)
    }
    
    // MARK: - Menu Bar Setup
    func setupMenuBar() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        
        if let button = statusItem?.button {
            button.image = NSImage(systemSymbolName: "checklist", accessibilityDescription: "Claude Todo")
            button.action = #selector(menuBarClicked)
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }
    }
    
    @objc func menuBarClicked(_ sender: NSStatusBarButton) {
        let event = NSApp.currentEvent!
        
        if event.type == .rightMouseUp {
            // 우클릭: 메뉴 표시
            showMenu()
        } else {
            // 좌클릭: 윈도우 토글
            toggleWindow()
        }
    }
    
    func showMenu() {
        let menu = NSMenu()

        // 태스크 요약 (멀티 프로젝트 모드)
        if !todoManager.projects.isEmpty {
            let allTodos = todoManager.projects.flatMap { $0.todos }
            let pendingCount = allTodos.filter { $0.status == .pending }.count
            let inProgressCount = allTodos.filter { $0.status == .inProgress }.count
            let completedCount = allTodos.filter { $0.status == .completed }.count

            let summaryItem = NSMenuItem(title: "📋 \(pendingCount) pending · \(inProgressCount) active · \(completedCount) done", action: nil, keyEquivalent: "")
            summaryItem.isEnabled = false
            menu.addItem(summaryItem)

            let projectsItem = NSMenuItem(title: "📁 \(todoManager.projects.count) projects", action: nil, keyEquivalent: "")
            projectsItem.isEnabled = false
            menu.addItem(projectsItem)
        } else {
            let pendingCount = todoManager.todos.filter { $0.status == .pending }.count
            let inProgressCount = todoManager.todos.filter { $0.status == .inProgress }.count
            let completedCount = todoManager.todos.filter { $0.status == .completed }.count

            let summaryItem = NSMenuItem(title: "📋 \(pendingCount) pending · \(inProgressCount) active · \(completedCount) done", action: nil, keyEquivalent: "")
            summaryItem.isEnabled = false
            menu.addItem(summaryItem)
        }

        menu.addItem(NSMenuItem.separator())

        // 윈도우 토글
        let windowItem = NSMenuItem(
            title: floatingWindow?.isVisible == true ? "Hide Window" : "Show Window",
            action: #selector(toggleWindow),
            keyEquivalent: "t"
        )
        menu.addItem(windowItem)

        // 새로고침
        menu.addItem(NSMenuItem(title: "Refresh", action: #selector(refreshTodos), keyEquivalent: "r"))

        // 재스캔
        menu.addItem(NSMenuItem(title: "Rescan Projects", action: #selector(rescanProjects), keyEquivalent: ""))

        menu.addItem(NSMenuItem.separator())

        // 파일 선택
        menu.addItem(NSMenuItem(title: "Select todo.md...", action: #selector(selectFile), keyEquivalent: "o"))

        // 현재 감시 중인 파일/폴더
        if !todoManager.projects.isEmpty {
            let pathItem = NSMenuItem(title: "📁 ~/Documents/code", action: nil, keyEquivalent: "")
            pathItem.isEnabled = false
            menu.addItem(pathItem)
        } else if !todoManager.watchedPath.isEmpty {
            let pathItem = NSMenuItem(title: "📁 \(shortenPath(todoManager.watchedPath))", action: nil, keyEquivalent: "")
            pathItem.isEnabled = false
            menu.addItem(pathItem)
        }

        menu.addItem(NSMenuItem.separator())

        // 설정
        menu.addItem(NSMenuItem(title: "Settings...", action: #selector(openSettings), keyEquivalent: ","))

        menu.addItem(NSMenuItem.separator())

        // 종료
        menu.addItem(NSMenuItem(title: "Quit", action: #selector(quitApp), keyEquivalent: "q"))

        statusItem?.menu = menu
        statusItem?.button?.performClick(nil)
        statusItem?.menu = nil
    }
    
    // MARK: - Floating Window Setup
    func setupFloatingWindow() {
        let contentView = FloatingTodoView()
            .environmentObject(todoManager)
        
        let hostingView = NSHostingView(rootView: contentView)
        
        floatingWindow = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 340, height: 420),
            styleMask: [.titled, .closable, .resizable, .nonactivatingPanel, .utilityWindow],
            backing: .buffered,
            defer: false
        )
        
        floatingWindow?.contentView = hostingView
        floatingWindow?.title = "Claude Code Tasks"
        floatingWindow?.level = .floating
        floatingWindow?.isMovableByWindowBackground = true
        floatingWindow?.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        floatingWindow?.titlebarAppearsTransparent = true
        floatingWindow?.backgroundColor = NSColor.windowBackgroundColor.withAlphaComponent(0.95)
        floatingWindow?.minSize = NSSize(width: 280, height: 200)
        floatingWindow?.maxSize = NSSize(width: 500, height: 800)
        
        // 화면 우측 상단에 위치
        positionWindowTopRight()
        
        floatingWindow?.orderFront(nil)
    }
    
    func positionWindowTopRight() {
        guard let window = floatingWindow, let screen = NSScreen.main else { return }
        let screenRect = screen.visibleFrame
        let windowRect = window.frame
        let x = screenRect.maxX - windowRect.width - 20
        let y = screenRect.maxY - windowRect.height - 20
        window.setFrameOrigin(NSPoint(x: x, y: y))
    }
    
    // MARK: - Actions
    @objc func toggleWindow() {
        if floatingWindow?.isVisible == true {
            floatingWindow?.orderOut(nil)
        } else {
            floatingWindow?.orderFront(nil)
            floatingWindow?.makeKeyAndOrderFront(nil)
        }
    }
    
    @objc func refreshTodos() {
        todoManager.refresh()
    }

    @objc func rescanProjects() {
        todoManager.rescan()
    }
    
    @objc func selectFile() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.plainText]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.message = "Select your todo.md file"
        panel.nameFieldStringValue = "todo.md"
        
        if panel.runModal() == .OK, let url = panel.url {
            todoManager.startWatching(path: url.path)
            todoManager.savedPath = url.path
        }
    }
    
    @objc func openSettings() {
        NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
        NSApp.activate(ignoringOtherApps: true)
    }
    
    @objc func quitApp() {
        NSApp.terminate(nil)
    }
    
    // MARK: - Helpers
    func shortenPath(_ path: String) -> String {
        let home = NSHomeDirectory()
        if path.hasPrefix(home) {
            return "~" + path.dropFirst(home.count)
        }
        return (path as NSString).lastPathComponent
    }
}
