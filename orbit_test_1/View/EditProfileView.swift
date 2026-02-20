import SwiftUI

// MARK: - Dev Profile Options
// Labels shown in the picker. IDs must match profiles.json keys exactly
// so ProfileAPIService enrichment lookups resolve correctly.
// Gate behind #if DEBUG or remove before shipping.

private struct DevProfile: Identifiable {
    let id: String      // 6-char ASCII — the only field written to AppStorage
    let label: String   // Human-readable picker label
}

private let devProfiles: [DevProfile] = [
    DevProfile(id: "ReedSt", label: "Profile 1 — ReedSt"),
    DevProfile(id: "AditiK", label: "Profile 2 — AditiK"),
    DevProfile(id: "MarcuL", label: "Profile 3 — MarcuL"),
    DevProfile(id: "SophiR", label: "Profile 4 — SophiR"),
]

// MARK: - View

struct EditProfileView: View {
    @Environment(\.dismiss) var dismiss

    @AppStorage("userName") private var name:   String = ""
    @AppStorage("userBio")  private var bio:    String = ""
    @AppStorage("userID")   private var userID: String = ""  // ← used by BLEManager as myUserID

    let nameLimit = 10
    let bioLimit  = 8

    var body: some View {
        NavigationView {
            Form {

                // MARK: - Dev Device Identity
                Section(
                    header: Text("Dev Device Identity"),
                    footer: Text("Sets this device's broadcast ID. Each test device should use a different profile so they can discover each other. Only the ID is loaded — name and bio are yours to set.")
                ) {
                    ForEach(devProfiles) { profile in
                        Button(action: {
                            // Only stamp the ID — leave name and bio untouched
                            userID = profile.id
                        }) {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(profile.label)
                                        .foregroundColor(.primary)
                                    Text("ID: \(profile.id)")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                                Spacer()
                                if userID == profile.id {
                                    Image(systemName: "checkmark")
                                        .foregroundColor(.green)
                                }
                            }
                        }
                    }
                }

                // MARK: - Broadcast Display Info
                Section(
                    header: Text("Public Profile"),
                    footer: Text("Name (max \(nameLimit)) and bio (max \(bioLimit)) are what others see in the nearby list. Your ID above is what the API uses to fetch your full profile.")
                ) {
                    // Name
                    VStack(alignment: .trailing, spacing: 4) {
                        TextField("Your Name", text: $name)
                            .onChange(of: name) { _, newValue in
                                if newValue.count > nameLimit {
                                    name = String(newValue.prefix(nameLimit))
                                }
                            }
                        Text("\(name.count)/\(nameLimit)")
                            .font(.caption2)
                            .foregroundColor(name.count == nameLimit ? .red : .secondary)
                    }

                    // Bio
                    VStack(alignment: .trailing, spacing: 4) {
                        TextField("Bio / Tech Stack", text: $bio)
                            .onChange(of: bio) { _, newValue in
                                if newValue.count > bioLimit {
                                    bio = String(newValue.prefix(bioLimit))
                                }
                            }
                        Text("\(bio.count)/\(bioLimit)")
                            .font(.caption2)
                            .foregroundColor(bio.count == bioLimit ? .red : .secondary)
                    }
                }

                // MARK: - Current State (debug glance)
                Section(header: Text("Active Config")) {
                    LabeledContent("Broadcasting as", value: userID.isEmpty ? "No ID set" : userID)
                        .foregroundColor(userID.isEmpty ? .red : .primary)
                }
            }
            .navigationTitle("Edit Profile")
            .navigationBarItems(trailing: Button("Done") { dismiss() })
        }
    }
}

#Preview {
    EditProfileView()
}
