import SwiftUI

/// Developer test harness for the Relavoi iOS SDK against the live backend
/// (api.relavoi.com, Bolt Nigeria test tenant). Not a production UI.
///
/// To run: create a new iOS App in Xcode, add the local RelavoiSDK package,
/// and copy these three files (SampleApp.swift, ContentView.swift,
/// SDKLogView.swift) into the project. See README.md.
@main
struct RelavoiSampleApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
