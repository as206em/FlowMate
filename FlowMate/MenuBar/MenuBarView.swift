//
//  MenuBarView.swift
//  FlowMate
//
//  Created by Asem MKL on 2025/09/05.
//

import SwiftUI

struct MenuBarView: View {
    @StateObject private var viewModel = MenuBarViewModel()
    
    var body: some View {
        EmptyView()
            .onAppear {
                // Menu bar is handled by the view model
            }
    }
}

struct MenuBarView_Previews: PreviewProvider {
    static var previews: some View {
        MenuBarView()
    }
}
