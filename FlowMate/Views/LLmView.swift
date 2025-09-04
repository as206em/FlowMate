import SwiftUI

struct LLmView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Models")
                .font(.largeTitle)
                .fontWeight(.semibold)
                .padding(.bottom, 20)
            
            Text("Manage and configure AI models used by the application.")
                .foregroundColor(.secondary)
            
            Spacer()
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

struct LLmView_Previews: PreviewProvider {
    static var previews: some View {
        LLmView()
    }
}
