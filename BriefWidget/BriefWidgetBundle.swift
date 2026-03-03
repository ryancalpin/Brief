// BriefWidgetBundle.swift
// Widget Extension entry point — registers all Brief widgets

import WidgetKit
import SwiftUI

@main
struct BriefWidgetBundle: WidgetBundle {
    var body: some Widget {
        RecentItemsWidget()
        QuickRecordWidget()
        StatsWidget()
    }
}
