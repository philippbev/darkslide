import SwiftUI

/// Every token and component of the design system on one screen, to judge them in light and dark
/// before any real screen uses them. Reached from Settings while the diagnostic tools are shown.
struct DesignSystemGallery: View {
    @Environment(\.colorScheme) private var colorScheme
    @State private var selectedChip = "All"
    @State private var locationOn = true
    @State private var selectedFrames: Set<Int> = [0, 1, 3, 4]

    private let chips = ["All", "Street", "Portrait", "Travel", "Black & White"]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DSSpacing.xxxl) {
                colors
                typography
                metrics
                buttons
                chipsAndBadges
                testStrips
                recipeList
                settings
                statusCards
                contactSheet
            }
            .padding(.horizontal, DSSpacing.screenMargin)
            .padding(.vertical, DSSpacing.xxl)
        }
        .background(DSColor.background.ignoresSafeArea())
        .safeAreaInset(edge: .bottom) {
            DSActionBar {
                DSActionBarDetail(label: "Destination", value: "Photo Library")
                Button("Import \(selectedFrames.count) Photos") {}
                    .buttonStyle(.dsPrimary)
                    .disabled(selectedFrames.isEmpty)
            }
        }
        .tint(DSColor.accent)
        .navigationTitle("Design System")
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: Tokens

    private var colors: some View {
        section("Colors") {
            VStack(spacing: 0) {
                ForEach(Array(DSColor.Tokens.all.enumerated()), id: \.element.id) { index, token in
                    if index > 0 { DSSeparator().padding(.leading, DSSpacing.l) }
                    HStack(spacing: DSSpacing.m) {
                        RoundedRectangle(cornerRadius: DSRadius.badge, style: .continuous)
                            .fill(token.color)
                            .frame(width: 36, height: 36)
                            .overlay(RoundedRectangle(cornerRadius: DSRadius.badge, style: .continuous)
                                .strokeBorder(DSColor.separator))
                        Text(token.name)
                            .font(DSFont.subhead)
                            .foregroundStyle(DSColor.textPrimary)
                        Spacer()
                        Text(hexLabel(for: token))
                            .font(DSFont.valueMono)
                            .foregroundStyle(DSColor.textSecondary)
                    }
                    .padding(.horizontal, DSSpacing.l)
                    .frame(minHeight: DSSize.settingsRowHeight + DSSpacing.s)
                }
            }
            .dsCard()
        }
    }

    private func hexLabel(for token: DSColorToken) -> String {
        let hex = String(format: "#%06X", token.hex(for: colorScheme))
        return token.opacity < 1 ? "\(hex)  \(Int(token.opacity * 100))%" : hex
    }

    private var typography: some View {
        section("Typography") {
            VStack(alignment: .leading, spacing: DSSpacing.m) {
                Text("Large Title").font(DSFont.largeTitle)
                Text("Title").font(DSFont.title)
                Text("Headline").font(DSFont.headline)
                Text("Body. Recipes are written to the camera's custom slots.").font(DSFont.body)
                Text("Subhead").font(DSFont.subhead)
                Text("Footnote").font(DSFont.footnote).foregroundStyle(DSColor.textSecondary)
                Text("Label Mono   Slot C1").dsLabelMono()
                Text("R\(DSValueFormat.signed(2))  B\(DSValueFormat.signed(-5))   DR200").font(DSFont.valueMono)
            }
            .foregroundStyle(DSColor.textPrimary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(DSSpacing.l)
            .dsCard()
        }
    }

    private var metrics: some View {
        section("Spacing & Radii") {
            VStack(alignment: .leading, spacing: DSSpacing.l) {
                VStack(alignment: .leading, spacing: DSSpacing.s) {
                    ForEach(DSSpacing.scale, id: \.name) { step in
                        HStack(spacing: DSSpacing.m) {
                            Text("\(step.name) \(Int(step.value))")
                                .font(DSFont.valueMono)
                                .foregroundStyle(DSColor.textSecondary)
                                .frame(width: 72, alignment: .leading)
                            Capsule().fill(DSColor.accent).frame(width: step.value * 4, height: 8)
                        }
                    }
                }
                DSSeparator()
                HStack(alignment: .bottom, spacing: DSSpacing.m) {
                    ForEach(DSRadius.scale, id: \.name) { radius in
                        VStack(spacing: DSSpacing.s) {
                            RoundedRectangle(cornerRadius: radius.value, style: .continuous)
                                .fill(DSColor.surfaceSecondary)
                                .frame(height: 56)
                            Text("\(radius.name) \(Int(radius.value))").dsLabelMono()
                        }
                    }
                }
            }
            .padding(DSSpacing.l)
            .dsCard()
        }
    }

    // MARK: Components

    private var buttons: some View {
        section("Buttons") {
            VStack(spacing: DSSpacing.m) {
                Button("Send to Camera") {}.buttonStyle(.dsPrimary)
                Button("Share") {}.buttonStyle(.dsSecondary)
                Button("Disabled") {}.buttonStyle(.dsPrimary).disabled(true)
                HStack(spacing: DSSpacing.m) {
                    DSIconButton(systemImage: "gearshape", label: "Settings") {}
                    DSIconButton(systemImage: "square.and.arrow.up", label: "Share") {}
                    Spacer()
                    DSIconButton(systemImage: "plus", label: "New Recipe", prominence: .primary) {}
                }
            }
        }
    }

    private var chipsAndBadges: some View {
        section("Chips, Badges & Pills") {
            VStack(alignment: .leading, spacing: DSSpacing.m) {
                DSChipRow {
                    ForEach(chips, id: \.self) { chip in
                        DSChip(label: chip, isSelected: chip == selectedChip) { selectedChip = chip }
                    }
                }
                .padding(.horizontal, -DSSpacing.screenMargin)
                HStack(spacing: DSSpacing.s) {
                    DSSlotBadge(slot: "C1")
                    DSSlotBadge(slot: "C7")
                    DSHintPill(text: "Runs on X100VI", systemImage: "checkmark.circle")
                }
                DSHintPill(text: "Street", systemImage: "book.closed")
            }
        }
    }

    private var testStrips: some View {
        section("Test Strip") {
            VStack(alignment: .leading, spacing: DSSpacing.l) {
                DSTestStripDetail(simulation: .classicChrome)
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: DSSpacing.s), count: 5),
                          spacing: DSSpacing.s) {
                    ForEach(Self.stripFamilies) { simulation in
                        DSTestStrip(simulation: simulation).aspectRatio(1, contentMode: .fit)
                    }
                }
            }
        }
    }

    private var recipeList: some View {
        section("Recipe Rows") {
            VStack(alignment: .leading, spacing: DSSpacing.s) {
                Text("X100VI   24 Recipes   5 in Camera")
                    .dsLabelMono()
                    .padding(.horizontal, DSSpacing.xs)
                VStack(spacing: 0) {
                    DSRecipeRow(simulation: .classicChrome, name: "Kodachrome 64",
                                meta: "Classic Chrome   Grain Weak", slot: "C1")
                    DSSeparator().padding(.leading, DSSpacing.m)
                    DSRecipeRow(simulation: .classicNeg, name: "Lua de Mel",
                                meta: "Classic Neg.   Grain Strong", slot: "C2")
                    DSSeparator().padding(.leading, DSSpacing.m)
                    DSRecipeRow(simulation: .acros, name: "Tri-X 400 with a deliberately long name",
                                meta: "ACROS + R Filter   Grain Strong")
                }
                .dsCard()
            }
        }
    }

    private var settings: some View {
        section("Settings Group") {
            VStack(spacing: DSSpacing.xl) {
                DSSettingsGroup(title: "Color", rows: [
                    .init(label: "Film Simulation", value: "Classic Chrome"),
                    .init(label: "White Balance Shift",
                          value: "R\(DSValueFormat.signed(2))  B\(DSValueFormat.signed(-5))"),
                    .init(label: "Color", value: DSValueFormat.signed(2))
                ])
                DSSettingsGroup(title: "Tone", rows: [
                    .init(label: "Dynamic Range", value: "DR200"),
                    .init(label: "Highlights", value: DSValueFormat.signed(-1)),
                    .init(label: "Shadows", value: DSValueFormat.signed(1))
                ])
            }
        }
    }

    private var statusCards: some View {
        section("Status Cards") {
            VStack(spacing: DSSpacing.m) {
                DSStatusCard(systemImage: "camera", title: "X100VI", meta: "USB   Card Reader   FW 1.31") {
                    DSStatusDot()
                }
                DSStatusCard(systemImage: "location", title: "Location", meta: "Track   2 h 14 min",
                             iconTint: .accent) {
                    Toggle("Record location", isOn: $locationOn).labelsHidden()
                }
            }
        }
    }

    private var contactSheet: some View {
        section("Contact Sheet") {
            VStack(alignment: .leading, spacing: DSSpacing.s) {
                Text("Today   November 13").dsLabelMono().padding(.horizontal, DSSpacing.xs)
                LazyVGrid(columns: DSContactSheet.columns, spacing: DSContactSheet.spacing) {
                    ForEach(0..<6, id: \.self) { index in
                        Button {
                            selectedFrames.formSymmetricDifference([index])
                        } label: {
                            DSContactSheetTile(placeholder: Self.framePlaceholder(index),
                                               frameNumber: String(format: "%04d", 1284 + index),
                                               format: index.isMultiple(of: 2) ? "RAF+JPG" : "JPG",
                                               isSelected: selectedFrames.contains(index))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    // MARK: Helpers

    private func section(_ title: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: DSSpacing.m) {
            Text(title)
                .font(DSFont.title)
                .foregroundStyle(DSColor.textPrimary)
                .accessibilityAddTraits(.isHeader)
            content()
        }
    }

    /// One simulation per strip in `TestStripPalette`.
    private static let stripFamilies: [FilmSimulation] = [
        .provia, .velvia, .astia, .classicChrome, .proNegHi, .proNegStd, .classicNeg, .nostalgicNeg,
        .eterna, .eternaBleachBypass, .realaAce, .acros, .monochrome, .sepia
    ]

    /// Stand-ins for photos: midtones from the strips.
    private static func framePlaceholder(_ index: Int) -> Color {
        let simulation = stripFamilies[(index * 3) % stripFamilies.count]
        return Color(dsHex: TestStripPalette.hexValues(for: simulation)[2])
    }
}

#Preview("Light") {
    NavigationStack { DesignSystemGallery() }
}

#Preview("Dark") {
    NavigationStack { DesignSystemGallery() }.preferredColorScheme(.dark)
}
