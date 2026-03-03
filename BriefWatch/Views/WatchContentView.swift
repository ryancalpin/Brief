// WatchContentView.swift
// Root navigation view for the Apple Watch app

import SwiftUI

struct WatchContentView: View {
    @EnvironmentObject var vm: WatchViewModel
    @EnvironmentObject var connectivity: WatchConnectivityHandler
    @State private var selectedTab = 0

    var body: some View {
        TabView(selection: $selectedTab) {
            WatchRecordingView()
                .tag(0)

            WatchItemListView()
                .tag(1)
        }
        .tabViewStyle(.verticalPage)
    }
}
