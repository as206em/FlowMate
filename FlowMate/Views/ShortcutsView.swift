import SwiftUI

struct ShortcutsView: View {
    @StateObject private var shortcutManager = ShortcutManager()
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Shortcuts")
                        .font(.largeTitle)
                        .fontWeight(.semibold)
                    
                    Text("Configure keyboard shortcuts and hotkeys for quick access.")
                        .foregroundColor(.secondary)
                }
                
                Spacer()
            }
            .padding(.bottom, 20)
            
            // Shortcuts list - always shows predefined shortcuts
            List {
                ForEach(shortcutManager.shortcuts) { shortcut in
                    ShortcutRowView(
                        shortcut: shortcut,
                        onUpdate: { updatedShortcut in
                            shortcutManager.updateShortcutKeyCombination(updatedShortcut)
                        }
                    )
                }
            }
            .listStyle(.inset)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

// MARK: - Shortcut Row View
struct ShortcutRowView: View {
    let shortcut: Shortcut
    let onUpdate: (Shortcut) -> Void
    
    var body: some View {
        HStack(spacing: 12) {
            // Icon
            Image(systemName: shortcut.icon)
                .foregroundColor(.blue)
                .frame(width: 24, height: 24)
            
            // Title (non-editable)
            Text(shortcut.title)
            
            Spacer()
            
            // Shortcut recorder
            ShortcutRecorder(keyCombination: Binding(
                get: { shortcut.keyCombination },
                set: { newValue in
                    var updated = shortcut
                    updated.keyCombination = newValue
                    onUpdate(updated)
                }
            ))
            .frame(width: 200)
            
            // Toggle (always enabled for now)
            Toggle("", isOn: Binding(
                get: { true },
                set: { _ in }
            ))
            .labelsHidden()
            .controlSize(.small)
        }
        .padding(.vertical, 8)
    }
}

struct ShortcutsView_Previews: PreviewProvider {
    static var previews: some View {
        ShortcutsView()
    }
}
