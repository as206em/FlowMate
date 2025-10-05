import Foundation
import SwiftUI

struct AppConfig: Codable {
    var providers: ProvidersConfig
    var proofreading: ProofreadingConfig
    var app: AppSettings
}
