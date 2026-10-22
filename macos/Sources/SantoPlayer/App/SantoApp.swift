import AppKit
import SwiftUI

@main
struct SantoApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    var body: some Scene {
        Window("Santo Video Player", id: "main") {
            ContentView(model: delegate.model, pip: delegate.pip)
                .frame(minWidth: 640, minHeight: 380)
                .preferredColorScheme(.dark)
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1100, height: 660)
        .commands { PlayerCommands(model: delegate.model, pip: delegate.pip) }

        Settings {
            SettingsView(settings: AppSettings.shared, model: delegate.model)
        }
        .windowResizability(.contentSize)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    @MainActor let model = PlayerModel()
    @MainActor lazy var pip = PictureInPicture(model: model)
    @MainActor private var nowPlaying: NowPlayingController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        if RenderCheck.runIfRequested() { exit(0) }
        MainActor.assumeIsolated {
            nowPlaying = NowPlayingController(model: model)
            let pip = self.pip
            let previous = model.onStateChange
            model.onStateChange = { previous?(); pip.syncState() }
        }
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        MainActor.assumeIsolated { model.open(urls) }
    }

    func applicationWillTerminate(_ notification: Notification) {
        MainActor.assumeIsolated { model.shutdown() }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}
