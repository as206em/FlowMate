import Foundation
import SwiftUI

struct ProviderSetting: Codable {
    var url: String
    var model: String
    var apiKey: String?
    
    init(url: String, model: String, apiKey: String? = nil) {
        self.url = url
        self.model = model
        self.apiKey = apiKey
    }
}
