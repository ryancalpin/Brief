// swift-tools-version: 6.0
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "Brief",
    platforms: [
        .iOS(.v18),
        .watchOS(.v11),
    ],
    products: [
        // Brief is an XcodeGen-managed app; no library products.
        // This Package.swift exists solely to pin dependency versions
        // for any SPM packages added to the Xcode project.
        //
        // To add a dependency:
        // 1. Add it below
        // 2. In Xcode: Target > Frameworks, Libraries, and Embedded Content > +
        // 3. Or in project.yml: add to dependencies for the target
    ],
    dependencies: [
        // No external Swift packages currently required.
        // All functionality uses Apple frameworks:
        //   - SwiftData, SwiftUI, Observation (system)
        //   - Speech, AVFoundation (voice)
        //   - EventKit (reminders/calendar)
        //   - WatchConnectivity (Watch ↔ iPhone)
        //   - ActivityKit (Dynamic Island)
        //   - AppIntents (Siri/Action Button)
        //   - Security (Keychain)
        //
        // If adding packages later, pin exact versions:
        // .package(url: "https://github.com/example/package", exact: "1.2.3"),
    ],
    targets: [
        // This is a documentation-only manifest.
        // Actual targets are defined in project.yml via XcodeGen.
        .target(
            name: "Brief",
            path: "Brief",
            swiftSettings: [
                .enableUpcomingFeature("ExistentialAny"),
                .swiftLanguageMode(.v6),
            ]
        ),
    ]
)
