import SwiftUI

struct SidebarItemView: View {
    let title: String
    let systemImage: String
    
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: systemImage)
                .foregroundColor(.secondary)
                .frame(width: 16, alignment: .center)
            
            Text(title)
                .lineLimit(1)
            
            Spacer()
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 4)
    }
}

struct SidebarItemView_Previews: PreviewProvider {
    static var previews: some View {
        SidebarItemView(title: "Settings", systemImage: "gear")
            .previewLayout(.sizeThatFits)
    }
}
