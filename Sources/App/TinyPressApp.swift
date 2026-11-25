import SwiftUI

@main
struct TinyPressApp: App {
    @State private var libraryViewModel = LibraryViewModel()

    var body: some Scene {
        WindowGroup {
            RootContentView(viewModel: libraryViewModel)
        }
    }
}
