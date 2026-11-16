import SwiftUI

@main
struct ToobitRenkoApp: App {
    @StateObject private var session = MarketSession()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(session)
        }
    }
}
