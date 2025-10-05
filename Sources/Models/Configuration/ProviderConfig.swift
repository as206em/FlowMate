import Foundation
import SwiftUI

struct ProviderConfig: Codable {
    var url: String
    var apiKey: String?
    
    init(url: String = "", apiKey: String? = nil) {
        self.url = url
        self.apiKey = apiKey
    }
}
