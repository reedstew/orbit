//
//  ContentView.swift
//  orbit_test_1
//

import SwiftUI

struct ContentView: View {
    @StateObject private var bleManager = BLEManager()
    @State private var showingEditProfile = false
    @State private var showingOrbitMap = false
    @AppStorage("userName") private var myName: String = "Reed"
    @AppStorage("userBio")  private var myBio:  String = "Policy"
    @AppStorage("appMode")  private var appMode: String = AppMode.peer.rawValue

    private var currentMode: AppMode { AppMode(rawValue: appMode) ?? .peer }

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 20) {
                    HeaderView()

                    if currentMode == .peer {
                        PeerModeView(
                            bleManager: bleManager,
                            myName: myName,
                            myBio: myBio,
                            showingEditProfile: $showingEditProfile,
                            showingOrbitMap: $showingOrbitMap
                        )
                    } else {
                        EventView(bleManager: bleManager)
                            .padding(.horizontal)
                    }
                }
                .padding(.bottom)
            }
            .sheet(isPresented: $showingEditProfile) { EditProfileView() }
            .sheet(isPresented: $showingOrbitMap) { OrbitMapView(bleManager: bleManager) }
            .sheet(item: $bleManager.pendingConnectionRequest) { packet in
                ConnectionRequestSheet(packet: packet, myName: myName, bleManager: bleManager)
            }
            .navigationBarHidden(true)
        }
    }
}

// MARK: - PeerModeView

struct PeerModeView: View {
    @ObservedObject var bleManager: BLEManager
    let myName: String
    let myBio: String
    @Binding var showingEditProfile: Bool
    @Binding var showingOrbitMap: Bool

    var body: some View {
        // YOUR PROFILE SECTION
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Circle()
                    .fill(bleManager.isBroadcasting ? .green : .gray)
                    .frame(width: 10, height: 10)
                    .symbolEffect(.pulse, isActive: bleManager.isBroadcasting)

                Text("YOUR PROFILE").font(.caption).bold().foregroundColor(.secondary)
                Button(action: { showingEditProfile = true }) {
                    Label("Edit", systemImage: "pencil").font(.caption)
                }.foregroundColor(.gray)

                Spacer()

                Toggle("", isOn: Binding(
                    get: { bleManager.isBroadcasting },
                    set: { _ in bleManager.toggleBroadcasting(myName: myName, myBio: myBio) }
                ))
                .labelsHidden()
                .tint(.green)
                .scaleEffect(0.8)
            }

            MyProfileCard(name: myName, bio: myBio)
                .opacity(bleManager.isBroadcasting ? 1.0 : 0.6)
                .grayscale(bleManager.isBroadcasting ? 0.0 : 0.5)
        }
        .padding()
        .background(RoundedRectangle(cornerRadius: 16).fill(Color(UIColor.secondarySystemBackground).opacity(0.5)))
        .padding(.horizontal)

        // PEOPLE NEARBY SECTION
        VStack(alignment: .leading, spacing: 15) {
            HStack {
                Image(systemName: "person.2").foregroundColor(.secondary)
                Text("People Nearby").font(.headline)
                Spacer()
                Button(action: {
                    if bleManager.isScanning { bleManager.stopScanning() }
                    else { bleManager.startScanning() }
                }) {
                    Text(bleManager.isScanning ? "Stop Scan" : "Start Scan")
                        .font(.caption2).bold()
                        .padding(.horizontal, 8).padding(.vertical, 4)
                        .background(bleManager.isScanning ? Color.red.opacity(0.1) : Color.blue.opacity(0.1))
                        .foregroundColor(bleManager.isScanning ? .red : .blue)
                        .cornerRadius(6)
                }
            }
            .padding(.horizontal)

            Button(action: { showingOrbitMap = true }) {
                HStack {
                    Image(systemName: "map")
                    Text("Show Orbit Map")
                }
                .font(.subheadline).bold()
                .frame(maxWidth: .infinity)
                .padding()
                .background(Color(UIColor.secondarySystemBackground))
                .cornerRadius(12)
                .foregroundColor(.primary)
            }
            .padding(.horizontal)

            ForEach(bleManager.discoveredProfiles) { profile in
                let enriched = bleManager.enrichedProfiles[profile.hexID]
                OrbitProfileCard(
                    profile: profile,
                    enriched: enriched,
                    myName: myName,
                    bleManager: bleManager
                )
                .padding(.horizontal)
            }
        }
    }
}

struct OrbitProfileCard: View {
    let profile: NearbyProfile
    let enriched: EnrichedProfile?
    let myName: String
    let bleManager: BLEManager

    @State private var connectSent = false

    private var isConnected: Bool { bleManager.connectedIDs.contains(profile.hexID) }

    // Only show enriched data if there's an actual connection
    private var displayName: String { isConnected ? (enriched?.displayName ?? profile.name) : profile.name }
    private var displayBio:  String { isConnected ? (enriched?.displayBio  ?? profile.details) : profile.details }
    private var techStack:   [String] { isConnected ? (enriched?.techStack ?? []) : [] }
    private var linkedIn:    String? { isConnected ? enriched?.linkedIn : nil }

    private var distanceLabel: String {
        if profile.rssi > -60 { return "~2 ft" }
        else if profile.rssi > -80 { return "~15 ft" }
        else { return "Far" }
    }
    private var rssiColor: Color {
        profile.rssi > -60 ? .green : (profile.rssi > -80 ? .orange : .gray)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                Image(systemName: "person.circle.fill")
                    .resizable()
                    .frame(width: 50, height: 50)
                    .foregroundColor(rssiColor)

                VStack(alignment: .leading, spacing: 2) {
                    Text(displayName).font(.headline)
                    HStack(spacing: 4) {
                        Circle().fill(rssiColor).frame(width: 8, height: 8)
                        Text("\(distanceLabel)  \(profile.rssi) dBm")
                            .font(.caption).foregroundColor(.secondary)
                    }
                }

                Spacer()

                // Enrichment badge — only meaningful after connection
                if isConnected && enriched != nil {
                    Label("Connected", systemImage: "checkmark.seal.fill")
                        .font(.caption).foregroundColor(.blue)
                } else if isConnected {
                    Label("Connected", systemImage: "person.2.fill")
                        .font(.caption).foregroundColor(.green)
                }
            }

            Text(displayBio).font(.subheadline).foregroundColor(.primary)

            // Tech stack chips — only shown when enriched
            if !techStack.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(techStack, id: \.self) { tag in
                            Text(tag)
                                .font(.caption2).bold()
                                .padding(.horizontal, 8).padding(.vertical, 3)
                                .background(Capsule().fill(Color.blue.opacity(0.1)))
                                .foregroundColor(.blue)
                        }
                    }
                }
            }

            HStack {
                // Connect button — hidden once connected
                if !isConnected {
                    Button(action: {
                        bleManager.sendConnectionRequest(to: profile, myName: myName)
                        connectSent = true
                    }) {
                        HStack(spacing: 4) {
                            Image(systemName: connectSent ? "checkmark" : "person.badge.plus")
                            Text(connectSent ? "Sent" : "Connect")
                        }
                        .font(.subheadline).bold()
                    }
                    .buttonStyle(.bordered)
                    .tint(connectSent ? .green : .blue)
                    .disabled(connectSent)
                }

                Spacer()

                if let li = linkedIn {
                    Link(destination: URL(string: "https://\(li)")!) {
                        Image(systemName: "link.circle.fill")
                            .font(.title2).foregroundColor(.blue)
                    }
                }
            }
        }
        .padding()
        .background(Color(UIColor.systemBackground))
        .cornerRadius(16)
        .shadow(color: .black.opacity(0.05), radius: 5, x: 0, y: 2)
    }
}

// MARK: - ConnectionRequestSheet

/// Presented when another device sends a CC connection request to this device
struct ConnectionRequestSheet: View {
    let packet: CCPacket
    let myName: String
    let bleManager: BLEManager
    @Environment(\.dismiss) var dismiss

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: "person.badge.plus")
                .font(.system(size: 60))
                .foregroundColor(.blue)

            VStack(spacing: 6) {
                Text("Connection Request")
                    .font(.title2).bold()
                Text("\(packet.fromName) wants to connect")
                    .font(.subheadline).foregroundColor(.secondary)
                Text("ID: \(packet.fromID)")
                    .font(.caption).foregroundColor(.secondary)
            }

            HStack(spacing: 16) {
                Button(action: {
                    bleManager.rejectConnectionRequest(from: packet, myName: myName)
                    dismiss()
                }) {
                    Text("Decline")
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color(UIColor.secondarySystemBackground))
                        .cornerRadius(12)
                        .foregroundColor(.primary)
                }

                Button(action: {
                    bleManager.acceptConnectionRequest(from: packet, myName: myName)
                    dismiss()
                }) {
                    Text("Accept")
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.blue)
                        .cornerRadius(12)
                        .foregroundColor(.white)
                }
            }
            .font(.headline)
            .padding(.horizontal)

            Spacer()
        }
        .padding()
    }
}

// MARK: - CCPacket: Identifiable (for .sheet(item:))
// Needed so ContentView can use .sheet(item: $bleManager.pendingConnectionRequest)
extension CCPacket: Identifiable {
    public var id: String { "\(fromID)-\(toID)" }
}

// MARK: - Helper Components

struct EmptyStateView: View {
    let icon: String
    let message: String
    var isActive: Bool = false

    var body: some View {
        VStack(spacing: 20) {
            Spacer()
            Image(systemName: icon)
                .font(.system(size: 60))
                .foregroundColor(.gray)
                .symbolEffect(.variableColor.iterative, options: .repeating, isActive: isActive)
            Text(message).foregroundColor(.secondary).font(.subheadline)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }
}

struct MyProfileCard: View {
    let name: String
    let bio: String

    var body: some View {
        VStack(alignment: .leading, spacing: 15) {
            HStack(alignment: .center, spacing: 15) {
                Image("profile_photo")
                    .resizable()
                    .scaledToFill()
                    .frame(width: 60, height: 60)
                    .clipShape(RoundedRectangle(cornerRadius: 12))

                VStack(alignment: .leading, spacing: 2) {
                    Text(name).font(.title3).bold()
                    Text(bio).font(.subheadline).foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            HStack(spacing: 12) {
                SocialIcon(name: "linkedin", color: .blue)
                SocialIcon(name: "facebook", color: .blue)
                SocialIcon(name: "instagram", color: .pink)
            }

            Divider()

            HStack {
                Image(systemName: "sparkles").foregroundColor(.secondary)
                Text("Your profile is visible to people nearby")
                    .font(.caption).foregroundColor(.secondary)
            }
        }
        .padding()
        .background(Color(UIColor.systemBackground))
        .cornerRadius(16)
        .shadow(color: .black.opacity(0.05), radius: 10, x: 0, y: 5)
    }
}

struct SocialIcon: View {
    let name: String
    let color: Color
    var body: some View {
        Image(systemName: "link.circle.fill")
            .font(.title2)
            .foregroundColor(color.opacity(0.1))
            .overlay(Image(systemName: "link").font(.caption).foregroundColor(color))
    }
}

#Preview { ContentView() }
