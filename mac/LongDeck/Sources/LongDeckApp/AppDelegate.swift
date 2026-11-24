import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    @MainActor static weak var editor: EditorWindowController?

    @MainActor
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        (AppDelegate.editor?.closeForQuit() ?? true) ? .terminateNow : .terminateCancel
    }
}
