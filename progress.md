# App Lifecycle & Window Management

- [x] Create a new SwiftUI macOS app project (FlowMate)
- [x] Add a menu bar item (NSStatusBar/SwiftUI wrapper) with an icon
- [x] Implement logic so that clicking/double-clicking the menu bar icon toggles a main app window:
  - [x] If open → bring window to front
  - [x] If closed → hide window but keep app running in background
- [x] Ensure that closing the window does not quit the app, only hides it
- [x] Show main window on app startup for consistent dock icon behavior
- [ ] Add launch at startup support (using SMAppService)

# Keyboard Shortcuts (Global Hotkeys)

- [ ] Research & select the best framework for global hotkeys on macOS (MASShortcut, KeyboardShortcuts, or custom NSEvent monitor)
- [ ] Create a Shortcut Manager (centralized component to register/unregister shortcuts)
- [ ] Implement support for configurable shortcuts (map key combinations → actions)
- [ ] Define storage model for shortcuts (array of shortcut objects: {id, keyCombo, actionIdentifier})
- [ ] Add ability to persist shortcuts locally:
  - [ ] UserDefaults (simple)
  - [x] JSON file in Application Support folder (flexible & cloud-syncable later)
  - [ ] CoreData (overkill for now)
- [ ] Pick JSON file config for scalability
- [ ] Implement a default shortcut (⌘ + ⇧ + R) and action handler

# Settings & Configurations

- [x] Create a Settings screen (SwiftUI form-based view)
- [x] Add UI to configure & save shortcuts (list view with "add shortcut" option)
- [x] Add UI to configure LLM settings:
  - [x] API Host
  - [x] API Key
  - [x] Model Name
- [ ] Persist settings in the same JSON config file
- [ ] Add a Config Manager (singleton or environment object) to read/write settings

# Architecture & Scalability

- [ ] Set up MVVM pattern:
  - [ ] ShortcutViewModel → manages shortcut state
  - [ ] SettingsViewModel → manages app config
- [ ] Make shortcut actions modular:
  - [ ] Store them in a dictionary ([ActionIdentifier: () -> Void])
  - [ ] This makes it easy to add/remove shortcuts in the future

# Testing & Maintainability

- [ ] Add unit tests for:
  - [ ] Config persistence (read/write JSON)
  - [ ] Shortcut registration logic
- [ ] Ensure global shortcuts are mockable for testing
- [ ] Document code & keep components small/reusable (MenuBarManager, WindowManager, ShortcutManager, ConfigManager)
