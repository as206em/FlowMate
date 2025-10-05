import Foundation
import SwiftUI

struct ProofreadingConfig: Codable {
    var selectedProvider: String
    var defaultPrompt: String
    var showDiffByDefault: Bool
    var keyboardShortcut: String
    var model: String
    
    init(selectedProvider: String, defaultPrompt: String, showDiffByDefault: Bool, keyboardShortcut: String, model: String = "") {
        self.selectedProvider = selectedProvider
        self.defaultPrompt = defaultPrompt
        self.showDiffByDefault = showDiffByDefault
        self.keyboardShortcut = keyboardShortcut
        self.model = model
    }
}
