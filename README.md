# Claude Code Todo

Claude Code의 `todo.md` 태스크를 실시간으로 보여주는 macOS 플로팅 윈도우 앱

![macOS](https://img.shields.io/badge/macOS-13.0+-blue)
![Swift](https://img.shields.io/badge/Swift-5.9-orange)

## ✨ 주요 기능

| 기능 | 설명 |
|------|------|
| 🪟 **플로팅 윈도우** | 항상 최상위에 표시되어 코딩 중에도 태스크 확인 |
| 📍 **메뉴바 앱** | Dock에 안 뜨고 메뉴바에서 간편하게 제어 |
| 👁️ **실시간 모니터링** | `todo.md` 변경 즉시 자동 업데이트 |
| 🔍 **자동 탐지** | Claude Code가 만든 `todo.md` 자동 검색 |
| 📊 **진행률 표시** | 완료율 시각적 표시 |
| 🎯 **우선순위** | HIGH/MEDIUM/LOW 자동 파싱 및 정렬 |

---

## 📦 설치 방법

### 1. Xcode에서 열기

```bash
# 압축 해제 후
open ClaudeCodeTodo.xcodeproj
```

### 2. 빌드 & 실행

1. Xcode에서 프로젝트 열기
2. **⌘ + R** 눌러서 빌드 & 실행
3. 메뉴바에 ✓ 아이콘이 나타남!

### 3. (선택) 앱으로 내보내기

1. **Product → Archive**
2. **Distribute App → Copy App**
3. Applications 폴더로 복사

---

## 🎮 사용법

### 메뉴바 조작

| 동작 | 결과 |
|------|------|
| **좌클릭** | 윈도우 표시/숨기기 토글 |
| **우클릭** | 메뉴 열기 (상태 확인, 파일 선택, 설정, 종료) |

### 플로팅 윈도우

- 드래그해서 원하는 위치로 이동
- 모서리 드래그로 크기 조절
- 우측 상단 버튼으로 컴팩트/확장 모드 전환

### 파일 선택

1. 윈도우 하단의 📁 아이콘 클릭
2. 또는 메뉴바 우클릭 → "Select todo.md..."
3. Claude Code 작업 디렉토리의 `todo.md` 선택

---

## 📝 지원하는 Todo 포맷

Claude Code의 `TodoWrite` 도구가 만드는 모든 형식 지원:

```markdown
# 체크박스 형식
- [ ] 대기 중인 태스크
- [x] 완료된 태스크  
- [~] 진행 중인 태스크
- [/] 진행 중 (대체 표기)

# 상태 태그
- 태스크 설명 (pending)
- 태스크 설명 (in_progress)
- 태스크 설명 (completed)

# 우선순위
- [HIGH] 긴급한 태스크
- [LOW] 나중에 해도 되는 태스크
- 🔴 이모지로 높은 우선순위 표시
- 🟢 이모지로 낮은 우선순위 표시
```

---

## 🔧 Claude Code와 함께 사용

```bash
# 1. Claude Code 실행
claude

# 2. 복잡한 작업 요청
> "이 프로젝트를 리팩토링해줘"

# 3. Claude가 TodoWrite로 todo.md 생성
#    → 앱이 자동으로 감지하여 표시!
```

### 자동 탐지 경로
앱은 다음 위치에서 `todo.md`를 자동으로 찾습니다:
- 홈 디렉토리 (`~/`)
- Desktop, Documents, Developer 폴더
- 최근 수정된 파일 우선

---

## ⚙️ 설정

**메뉴바 우클릭 → Settings** 또는 **⌘ + ,**

- **Auto-detect**: `todo.md` 자동 탐지 on/off
- **File path**: 수동으로 파일 경로 지정
- **Show completed**: 완료된 태스크 표시 여부

---

## 🛠️ 개발 정보

### 요구사항
- macOS 13.0 (Ventura) 이상
- Xcode 15.0 이상

### 기술 스택
- SwiftUI
- AppKit (NSPanel, NSStatusItem)
- DispatchSource (파일 시스템 모니터링)

### 프로젝트 구조
```
ClaudeCodeTodo/
├── ClaudeCodeTodo.xcodeproj/
└── ClaudeCodeTodo/
    ├── ClaudeCodeTodoApp.swift   # 앱 진입점, 메뉴바, 윈도우
    ├── TodoManager.swift          # 파일 파싱 & 모니터링
    ├── FloatingTodoView.swift     # 메인 UI
    ├── SettingsView.swift         # 설정 화면
    ├── Assets.xcassets/           # 아이콘, 색상
    ├── Info.plist                 # 앱 설정
    └── ClaudeCodeTodo.entitlements
```

---

## 📄 라이선스

MIT License

---

## 💡 팁

- **빠른 토글**: 메뉴바 아이콘 좌클릭으로 윈도우 즉시 숨기기/보이기
- **작업 공간마다 표시**: 모든 데스크톱 스페이스에서 윈도우가 보임
- **전체화면 호환**: 전체화면 앱 위에서도 플로팅 윈도우 표시
