import SwiftUI

/// The Settings gear — one leading toolbar item plus the sheet it opens — for the root of every tab.
///
/// Settings is app-wide (iCloud sync, AI features and keys, export, the diagnostics report), so an
/// entry point only on Recipes would read like a Recipes feature: from Kitchen or Camera, "turn on
/// AI" and "report a problem" would mean switching tabs with nothing on screen saying so.
///
/// A modifier rather than four copies of the same button: the placement, the accessibility label and
/// the sheet are exactly the details that drift once they're duplicated.
extension View {
    /// The gear, managing its own presentation state. What a tab root wants.
    func settingsToolbarItem() -> some View {
        modifier(SelfPresentingSettingsToolbarItem())
    }

    /// The gear, driven by a flag the caller already owns — for a screen that also opens Settings
    /// from somewhere else (Library's "AI Scanning Isn't Set Up" alert), where a second, private
    /// `isPresented` would mean two sheets racing for one slot.
    func settingsToolbarItem(isPresented: Binding<Bool>) -> some View {
        modifier(SettingsToolbarItem(isPresented: isPresented))
    }
}

private struct SettingsToolbarItem: ViewModifier {
    @Binding var isPresented: Bool

    func body(content: Content) -> some View {
        content
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { isPresented = true } label: {
                        Image(systemName: "gearshape")
                    }
                    .accessibilityLabel("Settings")
                }
            }
            .sheet(isPresented: $isPresented) { SettingsView() }
    }
}

private struct SelfPresentingSettingsToolbarItem: ViewModifier {
    @State private var isPresented = false

    func body(content: Content) -> some View {
        content.modifier(SettingsToolbarItem(isPresented: $isPresented))
    }
}
