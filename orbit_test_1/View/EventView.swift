//
//  EventView.swift
//  orbit_test_1
//
//  Events mode UI. Supports two roles:
//    Host   — create an event, send actions, see roll call responses
//    Guest  — join an event, receive and react to host actions
//

import SwiftUI

struct EventView: View {
    @ObservedObject var bleManager: BLEManager

    @State private var eventIDInput: String = ""
    @State private var showingHostSetup = false

    var body: some View {
        ZStack {
            ScrollView {
                VStack(spacing: 20) {
                    if bleManager.isHostingEvent {
                        HostDashboard(bleManager: bleManager)
                    } else if bleManager.eventHandler_isAttending {
                        AttendantView(bleManager: bleManager)
                    } else {
                        IdleEventView(
                            bleManager: bleManager,
                            eventIDInput: $eventIDInput,
                            showingHostSetup: $showingHostSetup
                        )
                    }
                }
                .padding()
            }

            // Full-screen action overlay — shown on all attendant devices
            if let action = bleManager.activeEventAction {
                ActionOverlay(action: action)
            }
        }
    }
}

// MARK: - Idle (no active event)

private struct IdleEventView: View {
    @ObservedObject var bleManager: BLEManager
    @Binding var eventIDInput: String
    @Binding var showingHostSetup: Bool

    var body: some View {
        VStack(spacing: 24) {
            Image(systemName: "party.popper.fill")
                .font(.system(size: 60))
                .foregroundColor(.secondary)

            Text("No Active Event")
                .font(.title2).bold()
            Text("Host a new event or wait to receive one nearby.")
                .font(.subheadline).foregroundColor(.secondary)
                .multilineTextAlignment(.center)

            // Host button
            Button(action: { showingHostSetup = true }) {
                Label("Host an Event", systemImage: "megaphone.fill")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.blue)
                    .foregroundColor(.white)
                    .cornerRadius(14)
            }

            Text("or wait to receive an event broadcast nearby")
                .font(.caption).foregroundColor(.secondary)
        }
        .sheet(isPresented: $showingHostSetup) {
            HostSetupSheet(bleManager: bleManager)
        }
    }
}

// MARK: - Host Setup Sheet

struct HostSetupSheet: View {
    @ObservedObject var bleManager: BLEManager
    @Environment(\.dismiss) var dismiss

    @State private var eventID = ""
    private let maxEventIDLength = 6

    var body: some View {
        NavigationView {
            Form {
                Section(
                    header: Text("Event ID"),
                    footer: Text("Up to 6 characters. Attendees see this to identify your event.")
                ) {
                    VStack(alignment: .trailing, spacing: 4) {
                        TextField("e.g. CMU25A", text: $eventID)
                            .autocapitalization(.allCharacters)
                            .onChange(of: eventID) { _, new in
                                if new.count > maxEventIDLength {
                                    eventID = String(new.prefix(maxEventIDLength))
                                }
                            }
                        Text("\(eventID.count)/\(maxEventIDLength)")
                            .font(.caption2)
                            .foregroundColor(eventID.count == maxEventIDLength ? .red : .secondary)
                    }
                }
            }
            .navigationTitle("New Event")
            .navigationBarItems(
                leading: Button("Cancel") { dismiss() },
                trailing: Button("Start") {
                    let id = eventID.trimmingCharacters(in: .whitespaces)
                    guard !id.isEmpty else { return }
                    bleManager.startHostingEvent(eventID: id)
                    dismiss()
                }
                .disabled(eventID.trimmingCharacters(in: .whitespaces).isEmpty)
                .bold()
            )
        }
    }
}

// MARK: - Host Dashboard

private struct HostDashboard: View {
    @ObservedObject var bleManager: BLEManager

    var body: some View {
        VStack(spacing: 20) {

            // Event header
            HStack {
                VStack(alignment: .leading) {
                    Text("Hosting Event")
                        .font(.caption).foregroundColor(.secondary)
                    Text(bleManager.eventHandler_eventID ?? "—")
                        .font(.title2).bold()
                }
                Spacer()
                Button(action: { bleManager.stopHostingEvent() }) {
                    Text("End Event")
                        .font(.caption).bold()
                        .padding(.horizontal, 12).padding(.vertical, 6)
                        .background(Color.red.opacity(0.1))
                        .foregroundColor(.red)
                        .cornerRadius(8)
                }
            }
            .padding()
            .background(RoundedRectangle(cornerRadius: 14).fill(Color(UIColor.secondarySystemBackground)))

            // Action buttons
            Text("SEND ACTION").font(.caption).bold().foregroundColor(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                ForEach(EventAction.allCases.filter { $0 != .endEvent }, id: \.rawValue) { action in
                    Button(action: { bleManager.broadcastHostAction(action) }) {
                        VStack(spacing: 6) {
                            Image(systemName: action.iconName)
                                .font(.title2)
                            Text(action.displayName)
                                .font(.caption).bold()
                        }
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(RoundedRectangle(cornerRadius: 12).fill(action.color.opacity(0.12)))
                        .foregroundColor(action.color)
                    }
                }
            }

            // Roll call roster
            if !bleManager.eventAttendees.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    Text("ROLL CALL (\(bleManager.eventAttendees.count))")
                        .font(.caption).bold().foregroundColor(.secondary)

                    ForEach(Array(bleManager.eventAttendees.keys.sorted()), id: \.self) { guestID in
                        HStack {
                            Image(systemName: "checkmark.circle.fill").foregroundColor(.green)
                            Text(guestID).font(.subheadline)
                            Spacer()
                            if let date = bleManager.eventAttendees[guestID] {
                                Text(date, style: .time)
                                    .font(.caption).foregroundColor(.secondary)
                            }
                        }
                    }
                }
                .padding()
                .background(RoundedRectangle(cornerRadius: 14).fill(Color(UIColor.secondarySystemBackground)))
            }
        }
    }
}

// MARK: - Attendant View

private struct AttendantView: View {
    @ObservedObject var bleManager: BLEManager

    var body: some View {
        VStack(spacing: 20) {
            HStack {
                VStack(alignment: .leading) {
                    Text("Attending Event")
                        .font(.caption).foregroundColor(.secondary)
                    Text(bleManager.eventHandler_eventID ?? "—")
                        .font(.title2).bold()
                    Text("Hosted by \(bleManager.eventHandler_hostID ?? "—")")
                        .font(.caption).foregroundColor(.secondary)
                }
                Spacer()
                Button(action: { bleManager.leaveEvent() }) {
                    Text("Leave")
                        .font(.caption).bold()
                        .padding(.horizontal, 12).padding(.vertical, 6)
                        .background(Color.orange.opacity(0.1))
                        .foregroundColor(.orange)
                        .cornerRadius(8)
                }
            }
            .padding()
            .background(RoundedRectangle(cornerRadius: 14).fill(Color(UIColor.secondarySystemBackground)))

            Image(systemName: "antenna.radiowaves.left.and.right")
                .font(.system(size: 50))
                .foregroundColor(.green)
                .symbolEffect(.pulse, isActive: true)

            Text("Listening for host actions...")
                .font(.subheadline).foregroundColor(.secondary)
        }
    }
}

// MARK: - Action Overlay

struct ActionOverlay: View {
    let action: EventAction

    var body: some View {
        ZStack {
            action.color.opacity(0.92).ignoresSafeArea()

            VStack(spacing: 20) {
                Image(systemName: action.iconName)
                    .font(.system(size: 80))
                    .foregroundColor(.white)
                Text(action.displayName)
                    .font(.largeTitle).bold()
                    .foregroundColor(.white)
            }
        }
        .transition(.opacity)
        .animation(.easeInOut(duration: 0.3), value: action.rawValue)
    }
}

// MARK: - EventAction UI Extensions

extension EventAction {
    var iconName: String {
        switch self {
        case .rollCall:    return "person.3.fill"
        case .blueScreen:  return "rectangle.fill"
        case .greenScreen: return "rectangle.fill"
        case .endEvent:    return "flag.fill"
        }
    }

    var color: Color {
        switch self {
        case .rollCall:    return .blue
        case .blueScreen:  return .blue
        case .greenScreen: return .green
        case .endEvent:    return .red
        }
    }
}

// MARK: - BLEManager event state passthrough
// Thin computed properties so EventView doesn't reach into eventHandler directly

extension BLEManager {
    var eventHandler_isAttending: Bool { eventHandler.isAttending }
    var eventHandler_eventID: String?  { eventHandler.hostSession?.eventID ?? eventHandler.joinedEventID }
    var eventHandler_hostID: String?   { eventHandler.hostSession?.hostID  ?? eventHandler.joinedHostID }

    func leaveEvent() {
        eventHandler.leaveEvent()
        activeEventAction = nil
    }
}
