//
//  ContentView.swift
//  orbit_test_1
//
//  Created by Reed Stewart on 2/19/26.
//
import SwiftUI

struct ContentView: View {
    // @StateObject ensures the manager stays alive as long as this view exists
    @StateObject private var bleManager = BLEManager()
    @State private var showingEditProfile = false // Controls the popup sheet
    @State private var showingOrbitMap = false
    @AppStorage("userName") private var myName: String = "Reed"
    @AppStorage("userBio") private var myBio: String = "React, Python, C#"
    
    var body: some View {
        NavigationView {
            ScrollView { // Switch to ScrollView for custom layout freedom
                VStack(spacing: 20) {
                    // Header (e.g., Orbit Logo/Title)
                    HeaderView()

                    // YOUR PROFILE SECTION
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Circle()
                                .fill(bleManager.isBroadcasting ? .green : .gray) // Indicator turns green when live
                                .frame(width: 10, height: 10)
                                .symbolEffect(.pulse, isActive: bleManager.isBroadcasting) // Visual feedback
                            
                            Text("YOUR PROFILE").font(.caption).bold().foregroundColor(.secondary)
                            Button(action: { showingEditProfile = true }) {
                                    Label("Edit", systemImage: "pencil").font(.caption)
                                }.foregroundColor(.gray)
                            
                            Spacer()
                            
                            // The Broadcaster Toggle
                            Toggle("", isOn: Binding(
                                get: { bleManager.isBroadcasting },
                                set: { _ in bleManager.toggleBroadcasting(myName: myName, myBio: myBio) }
                            ))
                            .labelsHidden() // Keeps the UI minimal
                            .tint(.green)
                            .scaleEffect(0.8) // Makes the toggle slightly smaller to fit the header
                        }
                        
                        // Main User Card
                        MyProfileCard(name: myName, bio: myBio)
                            .opacity(bleManager.isBroadcasting ? 1.0 : 0.6) // Dim the card when not broadcasting
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
                            
                            // Scanner Toggle Button
                            Button(action: {
                                if bleManager.isScanning { bleManager.stopScanning() }
                                else { bleManager.startScanning() }
                            }) {
                                Text(bleManager.isScanning ? "Stop Scan" : "Start Scan")
                                    .font(.caption2)
                                    .bold()
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
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

                        // The Dynamic Feed
                        ForEach(bleManager.discoveredProfiles) { profile in
                            OrbitProfileCard(
                                name: profile.name,
                                bio: profile.details, // This is the 11-char bio parsed from the packet
                                distance: profile.rssi > -60 ? "~2 ft" : (profile.rssi > -80 ? "~15 ft" : "Far"),
                                status: "\(profile.rssi) dBm",
                                statusColor: profile.rssi > -70 ? .green : .orange
                            )
                        }
                    }
                }
                .padding(.bottom)
            }
            .sheet(isPresented: $showingEditProfile) {
                        EditProfileView()
                    }
            .sheet(isPresented: $showingOrbitMap) {
                // Pass the existing bleManager so the map uses your live data!
                OrbitMapView(bleManager: bleManager)
            }
            .navigationBarHidden(true)
        }
    }
}

// MARK: - Helper Components

// Extracted UI for the empty states to keep the main view clean
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
            
            Text(message)
                .foregroundColor(.secondary)
                .font(.subheadline)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }
}

// Extracted UI for the individual person rows
struct OrbitProfileCard: View {
    let name: String
    let bio: String
    let distance: String
    let status: String // "Nearby", "15 ft", etc.
    let statusColor: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                // Placeholder for profile image
                Image(systemName: "person.circle.fill")
                    .resizable()
                    .frame(width: 50, height: 50)
                    .clipShape(Circle())
                
                VStack(alignment: .leading) {
                    Text(name)
                        .font(.headline)
                    HStack(spacing: 4) {
                        Circle().fill(statusColor).frame(width: 8, height: 8)
                        Text(status)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                Spacer()
                // Action Button
                Capsule()
                    .fill(Color.green.opacity(0.1))
                    .frame(width: 100, height: 30)
                    .overlay(Text("Open to Chat").font(.caption2).bold().foregroundColor(.green))
            }
            
            Text(bio)
                .font(.subheadline)
                .foregroundColor(.primary)
            
            HStack {
                Button(action: {}) { Text("Connect").font(.subheadline).bold() }
                    .buttonStyle(.bordered)
                Spacer()
                // Simple Social Icons
                HStack(spacing: 15) {
                    Image(systemName: "link")
                    Image(systemName: "f.circle")
                    Image(systemName: "camera")
                }.foregroundColor(.gray)
            }
        }
        .padding()
        .background(Color(UIColor.systemBackground))
        .cornerRadius(16)
        .shadow(color: .black.opacity(0.05), radius: 5, x: 0, y: 2)
    }
}

struct MyProfileCard: View {
    let name: String
    let bio: String
    
    var body: some View {
        VStack(alignment: .leading, spacing: 15) {
            HStack(alignment: .center, spacing: 15) {
                // Profile Photo
                Image("profile_photo") // Make sure to add your photo to Assets.xcassets
                    .resizable()
                    .scaledToFill()
                    .frame(width: 60, height: 60)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(name)
                        .font(.title3)
                        .bold()
                    Text(bio)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            
            // Social Icons Row
            HStack(spacing: 12) {
                SocialIcon(name: "linkedin", color: .blue)
                SocialIcon(name: "facebook", color: .blue)
                SocialIcon(name: "instagram", color: .pink)
            }
            
            Divider()
            
            HStack {
                Image(systemName: "sparkles")
                    .foregroundColor(.secondary)
                Text("Your profile is visible to people nearby")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding()
        .background(Color(UIColor.systemBackground))
        .cornerRadius(16)
        .shadow(color: .black.opacity(0.05), radius: 10, x: 0, y: 5)
    }
}

// Small helper for social buttons
struct SocialIcon: View {
    let name: String
    let color: Color
    var body: some View {
        Image(systemName: "link.circle.fill") // Replace with specific brand icons
            .font(.title2)
            .foregroundColor(color.opacity(0.1))
            .overlay(Image(systemName: "link").font(.caption).foregroundColor(color))
    }
}

#Preview {
    ContentView()
}
