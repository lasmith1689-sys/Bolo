import BoloKit
import SwiftUI

@main
struct BoloApp: App {
    @State private var app: AppModel

    init() {
        guard let content = try? Content.bundled() else {
            fatalError("content.json is missing from the BoloKit bundle")
        }
        // Screenshot runs pass -BoloScreen <name>; they use a throwaway progress file.
        let screen = UserDefaults.standard.string(forKey: "BoloScreen")
        let demo = screen != nil || UserDefaults.standard.bool(forKey: "BoloDemo")
        let store = demo
            ? StateStore(url: FileManager.default.temporaryDirectory.appendingPathComponent("bolo-demo-\(UUID().uuidString).json"))
            : StateStore.standard()
        let model = AppModel(content: content, store: store, audio: AudioService(), isDemo: demo)
        if demo { Demo.prepare(model, screen: screen) }
        _app = State(initialValue: model)
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(app)
        }
    }
}

struct RootView: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        @Bindable var app = app
        ZStack {
            ClothBackground()
            switch app.screen {
            case .home:
                HomeView().transition(.opacity)
            case .session(let session):
                SessionView(session: session).transition(.opacity)
            case .summary(let summary):
                SummaryView(summary: summary).transition(.opacity)
            }
        }
        .preferredColorScheme(.dark)
        .dynamicTypeSize(...DynamicTypeSize.xxLarge)
        .sheet(isPresented: $app.showingSettings) { SettingsView() }
    }
}
