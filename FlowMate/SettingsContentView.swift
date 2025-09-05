import SwiftUI

struct SettingsContentView: View {
    @State private var selectedSection: SettingsSection? = .settings
    
    var body: some View {
        NavigationSplitView {
            List(SettingsSection.allCases, selection: $selectedSection) { section in
                NavigationLink(value: section) {
                    SidebarItemView(title: section.title, systemImage: section.systemImage)
                }
            }
            .navigationTitle("FlowMate")
            .navigationSplitViewColumnWidth(min: 180, ideal: 200, max: 250)
             //.toolbar(removing: .sidebarToggle)
        } detail: {
            if let selectedSection = selectedSection {
                sectionView(for: selectedSection)
            } else {
                Text("Select a section")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .navigationSplitViewStyle(.balanced)
        .frame(minWidth: 600, minHeight: 400)
    }
    
    @ViewBuilder
    private func sectionView(for section: SettingsSection) -> some View {
        switch section {
        case .settings:
            SettingsView()
        case .models:
            LLmView()
        case .shortcuts:
            ShortcutsView()
        }
    }
}

struct SettingsContentView_Previews: PreviewProvider {
    static var previews: some View {
        SettingsContentView()
    }
}
