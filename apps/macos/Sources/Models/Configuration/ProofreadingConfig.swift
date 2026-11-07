import Foundation
import SwiftUI

struct ProofreadingConfig: Codable {
    var selectedProvider: String
    var selectedModel: String
    var defaultPrompt: String
    var showDiffByDefault: Bool
    var keyboardShortcut: String
    var showDialog: Bool
    
    init(selectedProvider: String, selectedModel: String, defaultPrompt: String, showDiffByDefault: Bool, keyboardShortcut: String, showDialog: Bool = true) {
        self.selectedProvider = selectedProvider
        self.selectedModel = selectedModel
        self.defaultPrompt = defaultPrompt
        self.showDiffByDefault = showDiffByDefault
        self.keyboardShortcut = keyboardShortcut
        self.showDialog = showDialog
    }
}
