import SwiftUI

enum AppMode: String {
    case peer  = "Peer"
    case event = "Event"
}

struct HeaderView: View {
    @AppStorage("appMode") private var appMode: String = AppMode.peer.rawValue

    private var currentMode: AppMode { AppMode(rawValue: appMode) ?? .peer }

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

            // Peer / Event mode toggle
            HStack(spacing: 0) {
                ForEach([AppMode.peer, AppMode.event], id: \.rawValue) { mode in
                    Button(action: {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            appMode = mode.rawValue
                        }
                    }) {
                        HStack(spacing: 5) {
                            Image(systemName: mode.iconName)
                                .font(.caption)
                            Text(mode.rawValue)
                                .font(.subheadline)
                                .fontWeight(.medium)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(
                            Capsule().fill(currentMode == mode
                                ? mode.accentColor.opacity(0.15)
                                : Color.clear)
                        )
                        .foregroundColor(currentMode == mode ? mode.accentColor : .secondary)
                    }
                    .buttonStyle(PlainButtonStyle())
                }
            }
            .background(
                Capsule()
                    .fill(Color(UIColor.secondarySystemBackground))
            )
            .overlay(
                Capsule()
                    .stroke(Color(UIColor.separator).opacity(0.4), lineWidth: 1)
            )
        }
        .padding(.horizontal)
        .padding(.top, 10)
    }
}

// MARK: - AppMode UI helpers

extension AppMode {
    var iconName: String {
        switch self {
        case .peer:  return "person.2.fill"
        case .event: return "party.popper.fill"
        }
    }

    var accentColor: Color {
        switch self {
        case .peer:  return .blue
        case .event: return .purple
        }
    }
}

#Preview {
    HeaderView()
}
