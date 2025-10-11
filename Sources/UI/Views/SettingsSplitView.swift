import SwiftUI
import AppKit
import Foundation

// MARK: - Split View with Sidebar
struct SettingsSplitView<Content: View>: NSViewRepresentable {
    @Binding var selectedTab: SettingsTab
    let sidebarItems: [SettingsSidebarItem]
    let contentView: (SettingsTab) -> Content
    let onDismiss: () -> Void
    
    func makeNSView(context: Context) -> NSSplitView {
        let splitView = NSSplitView()
        splitView.isVertical = true
        splitView.dividerStyle = .thin
        
        // Create sidebar
        let sidebarView = createSidebar(context: context)
        sidebarView.translatesAutoresizingMaskIntoConstraints = false
        splitView.addArrangedSubview(sidebarView)
        
        // Create content view
        let contentHostingView = NSHostingView(rootView: createContentView())
        contentHostingView.translatesAutoresizingMaskIntoConstraints = false
        splitView.addArrangedSubview(contentHostingView)
        
        // Set proper constraints - let NSSplitView handle positioning
        NSLayoutConstraint.activate([
            sidebarView.widthAnchor.constraint(equalToConstant: 200),
            splitView.widthAnchor.constraint(equalToConstant: 600),
        ])
        
        splitView.setHoldingPriority(.defaultLow, forSubviewAt: 0)
        splitView.setHoldingPriority(.defaultHigh, forSubviewAt: 1)
        
        return splitView
    }
    
    func updateNSView(_ splitView: NSSplitView, context: Context) {
        // Update content view
        if splitView.arrangedSubviews.count > 1,
           let hostingView = splitView.arrangedSubviews[1] as? NSHostingView<AnyView> {
            hostingView.rootView = AnyView(createContentView())
        }
    }
    
    private func createSidebar(context: Context) -> NSView {
        let containerView = NSView()
        
        let scrollView = NSScrollView()
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder
        
        let outlineView = NSOutlineView()
        outlineView.dataSource = context.coordinator
        outlineView.delegate = context.coordinator
        outlineView.headerView = nil
        outlineView.style = .sourceList
        outlineView.focusRingType = .none
        outlineView.rowSizeStyle = .default
        outlineView.backgroundColor = .clear
        
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("SidebarColumn"))
        column.width = 150
        outlineView.addTableColumn(column)
        outlineView.outlineTableColumn = column
        
        scrollView.documentView = outlineView
        
        containerView.addSubview(scrollView)
        
        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: containerView.topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: containerView.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: containerView.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: containerView.bottomAnchor)
        ])
        
        context.coordinator.outlineView = outlineView
        outlineView.reloadData()
        outlineView.expandItem(nil, expandChildren: true)
        outlineView.selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false)
        
        return containerView
    }
    
    private func createContentView() -> AnyView {
        AnyView(contentView(selectedTab))
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    class Coordinator: NSObject, NSOutlineViewDataSource, NSOutlineViewDelegate {
        var parent: SettingsSplitView
        weak var outlineView: NSOutlineView?
        
        init(_ parent: SettingsSplitView) {
            self.parent = parent
        }
        
        // MARK: - NSOutlineViewDataSource
        
        func outlineView(_ outlineView: NSOutlineView, numberOfChildrenOfItem item: Any?) -> Int {
            if item == nil {
                return parent.sidebarItems.count
            }
            return 0
        }
        
        func outlineView(_ outlineView: NSOutlineView, child index: Int, ofItem item: Any?) -> Any {
            return parent.sidebarItems[index]
        }
        
        func outlineView(_ outlineView: NSOutlineView, isItemExpandable item: Any) -> Bool {
            return false
        }
        
        // MARK: - NSOutlineViewDelegate
        
        func outlineView(_ outlineView: NSOutlineView, viewFor tableColumn: NSTableColumn?, item: Any) -> NSView? {
            guard let sidebarItem = item as? SettingsSidebarItem else { return nil }
            
            let identifier = NSUserInterfaceItemIdentifier("SidebarCell")
            var cellView = outlineView.makeView(withIdentifier: identifier, owner: self) as? NSTableCellView
            
            if cellView == nil {
                cellView = NSTableCellView()
                cellView?.identifier = identifier
                
                // Create image view
                let imageView = NSImageView()
                imageView.translatesAutoresizingMaskIntoConstraints = false
                imageView.imageScaling = .scaleProportionallyDown
                cellView?.addSubview(imageView)
                cellView?.imageView = imageView
                
                // Create text field
                let textField = NSTextField()
                textField.translatesAutoresizingMaskIntoConstraints = false
                textField.isBordered = false
                textField.isEditable = false
                textField.backgroundColor = .clear
                textField.font = .systemFont(ofSize: 13)
                cellView?.addSubview(textField)
                cellView?.textField = textField
                
                // Layout constraints
                NSLayoutConstraint.activate([
                    imageView.leadingAnchor.constraint(equalTo: cellView!.leadingAnchor, constant: 8),
                    imageView.centerYAnchor.constraint(equalTo: cellView!.centerYAnchor),
                    imageView.widthAnchor.constraint(equalToConstant: 16),
                    imageView.heightAnchor.constraint(equalToConstant: 16),
                    
                    textField.leadingAnchor.constraint(equalTo: imageView.trailingAnchor, constant: 6),
                    textField.trailingAnchor.constraint(equalTo: cellView!.trailingAnchor, constant: -8),
                    textField.centerYAnchor.constraint(equalTo: cellView!.centerYAnchor)
                ])
            }
            
            // Configure cell
            cellView?.textField?.stringValue = sidebarItem.title
            
            if let image = NSImage(systemSymbolName: sidebarItem.icon, accessibilityDescription: sidebarItem.title) {
                cellView?.imageView?.image = image
                cellView?.imageView?.contentTintColor = .secondaryLabelColor
            }
            
            return cellView
        }
        
        func outlineView(_ outlineView: NSOutlineView, heightOfRowByItem item: Any) -> CGFloat {
            return 28
        }
        
        func outlineView(_ outlineView: NSOutlineView, shouldSelectItem item: Any) -> Bool {
            return true
        }
        
        func outlineViewSelectionDidChange(_ notification: Notification) {
            guard let outlineView = notification.object as? NSOutlineView else { return }
            let selectedRow = outlineView.selectedRow
            
            if selectedRow >= 0, selectedRow < parent.sidebarItems.count {
                let item = parent.sidebarItems[selectedRow]
                parent.selectedTab = item.tag
            }
        }
    }
}
