import SwiftUI

struct HeaderView: View {
    // Saves the toggle state permanently on the device
    @AppStorage("isOpenToChat") private var isOpenToChat: Bool = true
    
    var body: some View {
        HStack {
            // Logo and Title
            HStack(spacing: 8) {
                Image(systemName: "globe")
                    .font(.title2)
                    .foregroundColor(.primary)
                Text("Orbit")
                    .font(.title2)
                    .bold()
            }
            
            Spacer()
            
            // Interactive Status Badge
            Button(action: {
                // Adds a smooth color-fade animation when tapped
                withAnimation(.easeInOut(duration: 0.2)) {
                    isOpenToChat.toggle()
                }
            }) {
                HStack(spacing: 6) {
                    Circle()
                        .fill(isOpenToChat ? Color.green : Color.gray)
                        .frame(width: 8, height: 8)
                    Text(isOpenToChat ? "Open to Chat" : "Heads Down")
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundColor(isOpenToChat ? .green : .gray)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Capsule().fill(isOpenToChat ? Color.green.opacity(0.1) : Color.gray.opacity(0.1)))
                .overlay(
                    Capsule().stroke(isOpenToChat ? Color.green.opacity(0.2) : Color.gray.opacity(0.2), lineWidth: 1)
                )
            }
            .buttonStyle(PlainButtonStyle()) // Prevents the whole button from turning gray when pressed
        }
        .padding(.horizontal)
        .padding(.top, 10)
    }
}

#Preview {
    HeaderView()
}
