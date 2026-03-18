// SndysApp.swift — SwiftUI app entry point
import SwiftUI
import AppKit

class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        sndys_init()
        NSApp.activate(ignoringOtherApps: true)
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}

@main
struct SndysApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var store = AnalysisStore()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(store)
                .frame(minWidth: 900, minHeight: 600)
                .onAppear {
                    let args = ProcessInfo.processInfo.arguments
                    if args.count >= 2 {
                        store.loadFile(path: args[1])
                    }
                }
        }
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("Open...") { store.openFile() }
                    .keyboardShortcut("o")
            }
        }
    }
}
