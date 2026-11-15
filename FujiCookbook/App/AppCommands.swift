import SwiftUI

extension FocusedValues {
    /// The router of the window in front, for the menu bar.
    @Entry var appRouter: AppRouter?
}

/// The menu bar's own commands: on the Mac, and on an iPad with a keyboard, where holding ⌘ lists
/// them. Each acts on the window in front.
struct AppCommands: Commands {
    @FocusedValue(\.appRouter) private var router

    var body: some Commands {
        CommandGroup(after: .newItem) {
            Button("Import Photos from Camera…") {
                router?.selectedTab = .camera
                router?.photoImport = .camera
            }
                .keyboardShortcut("i", modifiers: [.command, .shift])
                .disabled(router == nil || SharedContainer.isLocalMacBuild)
        }
        CommandMenu("Go") {
            ForEach(Array(Self.tabs.enumerated()), id: \.offset) { index, entry in
                Button(entry.title) { router?.selectedTab = entry.tab }
                    .keyboardShortcut(KeyEquivalent(Character("\(index + 1)")), modifiers: .command)
                    .disabled(router == nil)
            }
        }
    }

    /// The tabs in sidebar order, so ⌘1 is the first one shown.
    static var tabs: [(title: String, tab: AppTab)] {
        [("Recipes", .library), ("Rolls", .chapters), ("Darkroom", .kitchen), ("Camera", .camera)]
    }
}
