//
//  OrbitMapView.swift
//  orbit_test_1
//
//  Created by Reed Stewart on 2/19/26.
//

import SwiftUI

struct OrbitMapView: View {
    // We pass in the existing bleManager so it shares the exact same live data
    @ObservedObject var bleManager: BLEManager
    @Environment(\.dismiss) var dismiss
    
    @AppStorage("userName") private var myName: String = "Reed"
    
    var body: some View {
        NavigationView {
            ZStack {
                // Background color
                Color(UIColor.systemBackground).edgesIgnoringSafeArea(.all)
                
                // Static Radar Rings for aesthetics
                Circle().stroke(Color.gray.opacity(0.2), lineWidth: 1).frame(width: 100, height: 100)
                Circle().stroke(Color.gray.opacity(0.2), lineWidth: 1).frame(width: 220, height: 220)
                Circle().stroke(Color.gray.opacity(0.1), lineWidth: 1).frame(width: 340, height: 340)
                
                // CENTER NODE: You
                VStack {
                    Image(systemName: "person.circle.fill") // Replace with "profile_photo" if you added it
                        .resizable()
                        .frame(width: 50, height: 50)
                        .clipShape(Circle())
                        .overlay(Circle().stroke(Color.green, lineWidth: 2))
                        .shadow(radius: 5)
                    
                    Text(myName)
                        .font(.caption)
                        .bold()
                        .padding(.top, 2)
                }
                .zIndex(1) // Ensures you stay on top of the orbiting nodes
                
                // ORBITING NODES: The people you find
                ForEach(bleManager.discoveredProfiles) { profile in
                    OrbitNodeView(profile: profile)
                }
            }
            .navigationTitle("Live Radar")
            .navigationBarTitleDisplayMode(.inline)
            .navigationBarItems(trailing: Button("Close") {
                dismiss()
            })
        }
    }
}

// Extracted Component for the individual orbiting icons
struct OrbitNodeView: View {
    let profile: NearbyProfile
    
    var body: some View {
        // 1. Calculate the smoothed distance (radius)
        let radius = radiusFor(rssi: profile.rssi)
        // 2. Calculate their permanent angle
        let angle = angleFor(id: profile.id)
        
        VStack {
            Image(systemName: "person.circle.fill")
                .resizable()
                .frame(width: 40, height: 40)
                .foregroundColor(colorFor(rssi: profile.rssi))
                .background(Circle().fill(Color(UIColor.systemBackground)))
            
            Text(profile.name)
                .font(.caption2)
                .lineLimit(1)
                .frame(width: 60)
        }
        .offset(x: radius * cos(angle), y: radius * sin(angle))
        // Watch the 'radius' for changes instead of the raw RSSI, and use a smooth glide!
        .animation(.easeInOut(duration: 0.8), value: radius)
    }
    
    // MARK: - Core Math Logic
    
    private func angleFor(id: UUID) -> Double {
        let hash = abs(id.uuidString.hashValue)
        return Double(hash % 360) * .pi / 180.0
    }
    
    // Maps the RSSI to physical pixels, bucketing into increments of 5
    private func radiusFor(rssi: Int) -> CGFloat {
        // 1. Bucket the RSSI to the nearest 5 (e.g., -62 becomes -60, -64 becomes -65)
        let smoothedRSSI = Double(Int(round(Double(rssi) / 5.0)) * 5)
        
        // 2. Clamp the smoothed value so they stay on screen
        let clamped = max(-100.0, min(-30.0, smoothedRSSI))
        
        // 3. Normalize to a 0.0 (closest) to 1.0 (furthest) scale
        let normalized = (clamped + 30.0) / -70.0
        
        let minRadius: CGFloat = 65
        let maxRadius: CGFloat = 160
        
        return minRadius + CGFloat(normalized) * (maxRadius - minRadius)
    }
    
    private func colorFor(rssi: Int) -> Color {
        if rssi > -60 { return .green }
        else if rssi > -80 { return .orange }
        else { return .gray }
    }
}
