import Foundation
import SwiftUI

struct ProvidersConfig: Codable {
    var ollama: ProviderConfig
    var openai: ProviderConfig
}
