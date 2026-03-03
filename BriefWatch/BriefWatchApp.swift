// BriefWatchApp.swift
// Apple Watch app entry point

import SwiftUI
import WatchConnectivity

@main
struct BriefWatchApp: App {

    @StateObject private var connectivityHandler = WatchConnectivityHandler.shared
    @StateObject private var watchVM = WatchViewModel()

    var body: some Scene {
        WindowGroup {
            WatchContentView()
                .environmentObject(connectivityHandler)
                .environmentObject(watchVM)
                .onAppear {
                    connectivityHandler.activate()
                }
        }
    }
}
