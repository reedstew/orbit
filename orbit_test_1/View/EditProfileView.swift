import SwiftUI

struct EditProfileView: View {
    @Environment(\.dismiss) var dismiss
    
    // These keys match what your BLEManager and ContentView use
    @AppStorage("userName") private var name: String = ""
    @AppStorage("userBio") private var bio: String = ""
    
    // Strict limits based on your 31-byte packet architecture
    let nameLimit = 10
    let bioLimit = 11
    
    var body: some View {
        NavigationView {
            Form {
                Section(
                    header: Text("Public Profile"),
                    footer: Text("Orbit uses a high-efficiency 31-byte packet. Your name is limited to 10 chars and bio to 11 chars for over-the-air discovery.")
                ) {
                    
                    // Name Field & Counter
                    VStack(alignment: .trailing) {
                        TextField("Your Name", text: $name)
                            .onChange(of: name) { oldValue, newValue in
                                if newValue.count > nameLimit {
                                    name = String(newValue.prefix(nameLimit))
                                }
                            }
                        
                        Text("\(name.count)/\(nameLimit)")
                            .font(.caption2)
                            .foregroundColor(name.count == nameLimit ? .red : .secondary)
                    }
                    
                    // Bio Field & Counter
                    VStack(alignment: .trailing) {
                        TextField("Bio / Tech Stack", text: $bio)
                            .onChange(of: bio) { oldValue, newValue in
                                if newValue.count > bioLimit {
                                    bio = String(newValue.prefix(bioLimit))
                                }
                            }
                        
                        Text("\(bio.count)/\(bioLimit)")
                            .font(.caption2)
                            .foregroundColor(bio.count == bioLimit ? .red : .secondary)
                    }
                }
            }
            .navigationTitle("Edit Profile")
            .navigationBarItems(trailing: Button("Done") {
                dismiss()
            })
        }
    }
}

#Preview {
    EditProfileView()
}
