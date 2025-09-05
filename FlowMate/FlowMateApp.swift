//
//  FlowMateApp.swift
//  FlowMate
//
//  Created by Asem MKL on 2025/08/27.
//

import SwiftUI

@main
struct FlowMateApp: App {
    @StateObject private var menuBarViewModel = MenuBarViewModel()
    
    var body: some Scene {
        WindowGroup {
            SettingsContentView()
        }
    }
}
