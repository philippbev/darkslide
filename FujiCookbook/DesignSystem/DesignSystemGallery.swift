import SwiftUI

/// Every token and component of the design system on one screen, to judge them in light and dark
/// before any real screen uses them. Reached from Settings ▸ Diagnostics while the diagnostic tools
/// are shown. The values are samples; no component reads app data.
struct DesignSystemGallery: View {
    @Environment(\.colorScheme) private var colorScheme
    @State private var chapter = "All"
    @State private var selectedSlot = "C3"
    @State private var locationOn = true
    @State private var onlyNew = false
    @State private var selectedFrames: Set<Int> = [0, 1, 3, 4]

    private let chapters = ["All", "Street", "Portrait", "Travel", "Black & White"]
    private let slots: [(slot: String, name: String?)] = [
        ("C1", "Kodachrome"), ("C2", "Tri-X"), ("C3", "Lua de Mel"), ("C4", nil),
        ("C5", "Portra 400"), ("C6", nil), ("C7", "Velvia 50")
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DSSpacing.xxxl) {
                header
                colors
                simulations
                typography
                metrics
                keys
                ledsAndSwitch
                slotKeys
                knobs
                devicePanel
                archiveCard
                recipeList
                tagsAndBarcode
                contactSheet
            }
            .padding(.vertical, DSSpacing.xxl)
        }
        .background(DSColor.background.ignoresSafeArea())
        .safeAreaInset(edge: .bottom) {
            DSFloatingActionBar(status: "Target \(selectedSlot)   Write  Read back  Verify") {
                HStack(spacing: DSSpacing.m) {
                    Button("Undo") {}.buttonStyle(.dsSecondary)
                    Button("Load into \(selectedSlot)") {}.buttonStyle(.dsPrimary)
                }
            }
        }
        .tint(DSColor.signal)
        .navigationTitle("Design System")
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: Header

    private var header: some View {
        VStack(alignment: .leading, spacing: DSSpacing.m) {
            Text("Recipes").dsLargeTitle()
            DSDataFieldRow(fields: [DSDataField(label: "Archive", value: "024"),
                                    DSDataField(label: "Camera", value: "5/7")])
            Text("v2.1   \(colorScheme == .dark ? "Dark" : "Light")").dsMetaMono()
        }
        .padding(.horizontal, DSSpacing.screenMargin)
    }

    // MARK: Tokens

    private var colors: some View {
        section("Colors") {
            DSArchiveList(items: DSColor.Tokens.all) { token in
                HStack(spacing: DSSpacing.m) {
                    Rectangle()
                        .fill(token.color)
                        .frame(width: 36, height: 36)
                        .overlay(Rectangle().strokeBorder(DSColor.separator, lineWidth: DSLine.hairline))
                    VStack(alignment: .leading, spacing: 2) {
                        Text(token.name)
                            .font(DSFont.subhead)
                            .foregroundStyle(DSColor.textPrimary)
                        Text(hexLine(token)).dsMetaMono()
                    }
                    Spacer(minLength: 0)
                }
                .padding(DSSpacing.s)
            }
        }
    }

    private func hexLine(_ token: DSColorToken) -> String {
        func hex(_ value: UInt32, _ opacity: Double) -> String {
            let base = String(format: "#%06X", value)
            return opacity < 1 ? "\(base) \(Int((opacity * 100).rounded()))%" : base
        }
        return "\(hex(token.light, token.lightOpacity))   \(hex(token.dark, token.darkOpacity))"
    }

    private var simulations: some View {
        section("Film Simulations") {
            DSArchiveList(items: FilmSimulation.allCases.map(SimulationItem.init)) { item in
                HStack(spacing: DSSpacing.m) {
                    Text(item.simulation.dsCode)
                        .dsSmallMono(size: 11, weight: .bold)
                        .foregroundStyle(item.simulation.dsText)
                        .frame(width: DSSize.simulationColumn, height: 32)
                        .background(item.simulation.dsFill)
                    Text(item.simulation.displayName)
                        .font(DSFont.subhead)
                        .foregroundStyle(DSColor.textPrimary)
                    Spacer(minLength: 0)
                }
                .padding(DSSpacing.xs)
            }
        }
    }

    private var typography: some View {
        section("Typography") {
            VStack(alignment: .leading, spacing: DSSpacing.m) {
                HStack(alignment: .firstTextBaseline, spacing: DSSpacing.l) {
                    Text("034").dsObjectNumber(size: 64)
                    Text("034").dsObjectNumber(size: 26)
                }
                Text("Large Title").dsLargeTitle()
                Text("Title").font(DSFont.title).foregroundStyle(DSColor.textPrimary)
                Text("Headline").font(DSFont.headline).foregroundStyle(DSColor.textPrimary)
                Text("Body text reads at the reader's size.").font(DSFont.body).foregroundStyle(DSColor.textPrimary)
                Text("Subhead for secondary lines").font(DSFont.subhead).foregroundStyle(DSColor.textSecondary)
                Text("Field label").dsFieldLabel()
                Text("Classic Chrome   Grain Weak").dsMetaMono()
                Text("R+2  B\(DSValueFormat.signed(-5))   DR200   \(DSValueFormat.signed(2))")
                    .font(DSFont.valueMono).foregroundStyle(DSColor.textPrimary)
                Text("C1").dsKeyLabel().foregroundStyle(DSColor.textPrimary)
            }
        }
    }

    private var metrics: some View {
        section("Spacing, Radii, Lines") {
            VStack(alignment: .leading, spacing: DSSpacing.l) {
                ForEach(DSSpacing.scale, id: \.name) { step in
                    HStack(spacing: DSSpacing.m) {
                        Text(step.name).dsFieldLabel().frame(width: 40, alignment: .leading)
                        Rectangle().fill(DSColor.signal).frame(width: step.value, height: 10)
                        Text("\(Int(step.value))").dsMetaMono()
                    }
                }
                HStack(spacing: DSSpacing.m) {
                    ForEach(DSRadius.scale, id: \.name) { radius in
                        VStack(spacing: DSSpacing.xs) {
                            RoundedRectangle(cornerRadius: radius.value, style: .continuous)
                                .strokeBorder(DSColor.rule, lineWidth: DSLine.rule)
                                .frame(width: 44, height: 44)
                            Text("\(Int(radius.value))").dsFieldLabel()
                        }
                    }
                }
                VStack(alignment: .leading, spacing: DSSpacing.s) {
                    Text("Rule 1.5").dsFieldLabel()
                    DSRule()
                    Text("Separator 1").dsFieldLabel()
                    DSSeparator()
                }
            }
        }
    }

    // MARK: Instrument

    private var keys: some View {
        VStack(alignment: .leading, spacing: DSSpacing.m) {
            sectionTitle("Hardware Keys").padding(.horizontal, DSSpacing.screenMargin)
            HStack(spacing: DSSpacing.m) {
                DSIconKey(systemImage: "line.3.horizontal.decrease", label: "Filter") {}
                DSIconKey(systemImage: "plus", label: "New Recipe", isActive: true) {}
                DSIconKey(systemImage: "square.and.arrow.up", label: "Share") {}
                    .disabled(true)
            }
            .padding(.horizontal, DSSpacing.screenMargin)
            DSKeyRow {
                ForEach(chapters, id: \.self) { name in
                    DSTextKey(label: name, isOn: chapter == name) { chapter = name }
                }
            }
            VStack(spacing: DSSpacing.m) {
                Button("Load onto Camera") {}.buttonStyle(.dsPrimary)
                Button("Share") {}.buttonStyle(.dsSecondary)
                Button("Delete", role: .destructive) {}.buttonStyle(.dsSecondary)
            }
            .padding(.horizontal, DSSpacing.screenMargin)
        }
    }

    private var ledsAndSwitch: some View {
        section("LEDs and Switch") {
            VStack(alignment: .leading, spacing: DSSpacing.l) {
                HStack(spacing: DSSpacing.l) {
                    DSLED(isOn: true, size: 6)
                    DSLED(isOn: true, glows: true)
                    DSLED(isOn: true, color: .ok, size: 10, glows: true)
                    DSLED(isOn: false, size: 10)
                    DSLEDIndicator(label: "Link", isOn: true)
                    DSLEDIndicator(label: "R/W", isOn: false)
                }
                Toggle("Location from Track", isOn: $locationOn)
                    .toggleStyle(.dsHardware)
                    .font(DSFont.body)
                    .foregroundStyle(DSColor.textPrimary)
                Toggle("Only New", isOn: $onlyNew)
                    .toggleStyle(.dsHardware)
                    .font(DSFont.body)
                    .foregroundStyle(DSColor.textPrimary)
            }
        }
    }

    private var slotKeys: some View {
        section("Slot Keys") {
            DSSlotGrid {
                ForEach(slots, id: \.slot) { entry in
                    DSSlotKey(slot: entry.slot, name: entry.name, isOccupied: entry.name != nil,
                              isSelected: selectedSlot == entry.slot) { selectedSlot = entry.slot }
                }
                DSSlotImportKey(newCount: 12) {}
            }
        }
    }

    private var knobs: some View {
        section("Knobs") {
            HStack {
                DSKnob(label: "Color", value: DSValueFormat.signed(2), position: DSKnobScale.position(of: 2, in: -4...4))
                Spacer()
                DSKnob(label: "Grain", value: "Weak", position: DSKnobScale.position(ofStep: 1, count: 3))
                Spacer()
                DSKnob(label: "Dynamic", value: "DR400", position: DSKnobScale.position(ofStep: 3, count: 4))
            }
        }
    }

    private var devicePanel: some View {
        section("Device Panel") {
            VStack(spacing: DSSpacing.m) {
                DSDevicePanel(title: "X100VI", meta: "FW 1.31   USB   RAW Conv. Mode") {
                    DSPanelLEDs(indicators: [("Link", true), ("R/W", true)])
                }
                DSDevicePanel(title: "Location from Track", meta: "12 of 40 located") {
                    Toggle("Location", isOn: $locationOn).toggleStyle(.dsHardwareSwitchOnly)
                }
            }
        }
    }

    // MARK: Archive

    private var archiveCard: some View {
        section("Archive Card") {
            VStack(alignment: .leading, spacing: DSSpacing.m) {
                DSArchiveCard {
                    DSArchiveHeader(objectNumber: "034",
                                    fields: [DSDataField(label: "Slot", value: "C3"),
                                             DSDataField(label: "Chapter", value: "Street"),
                                             DSDataField(label: "Created", value: "2026-11-14")])
                    DSRule()
                    DSArchiveTitle(title: "Lua de Mel", description: "Warm and soft, for late light.")
                    DSSimulationBand(simulation: .classicNeg)
                    DSDataSheet(fields: [DSDataField(label: "Dynamic Range", value: "DR400"),
                                         DSDataField(label: "Grain", value: "Weak Small"),
                                         DSDataField(label: "Highlight", value: DSValueFormat.signed(-1)),
                                         DSDataField(label: "Shadow", value: DSValueFormat.signed(2)),
                                         DSDataField(label: "Color", value: DSValueFormat.signed(3)),
                                         DSDataField(label: "White Balance", value: "R+2  B\(DSValueFormat.signed(-5))")])
                    DSRule()
                    DSArchiveFooter(barcodeSeed: "lua-de-mel", text: "X100VI  As Written")
                }
                HStack(spacing: DSSpacing.s) {
                    DSTag(text: "Street")
                    DSTag(text: "Travel")
                }
            }
        }
    }

    private var recipeList: some View {
        section("Recipe Rows") {
            DSArchiveList(items: Self.sampleRecipes) { recipe in
                DSRecipeRow(simulation: recipe.simulation, objectNumber: recipe.number, name: recipe.name,
                            meta: recipe.meta, slot: recipe.slot, slotIsLoaded: recipe.slot != "C4")
            }
        }
    }

    private var tagsAndBarcode: some View {
        section("Barcode and Tags") {
            VStack(alignment: .leading, spacing: DSSpacing.m) {
                DSBarcode(seed: "034")
                DSBarcode(seed: "035")
                HStack(spacing: DSSpacing.s) {
                    DSTag(text: "Street")
                    DSTag(text: "Card only partly read", systemImage: "exclamationmark.triangle")
                }
            }
        }
    }

    private var contactSheet: some View {
        section("Contact Sheet") {
            VStack(alignment: .leading, spacing: DSSpacing.s) {
                DSContactSheetDayHeader(title: "Today   November 14", frameRange: "0142–0150")
                DSContactSheetGrid {
                    ForEach(0..<6) { index in
                        Button {
                            if selectedFrames.contains(index) { selectedFrames.remove(index) }
                            else { selectedFrames.insert(index) }
                        } label: {
                            DSContactSheetTile(image: nil,
                                               frameNumber: String(format: "%04d", 142 + index),
                                               simulation: Self.frameSimulations[index % Self.frameSimulations.count],
                                               format: index == 2 ? "RAF+JPG" : nil,
                                               isSelected: selectedFrames.contains(index))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    // MARK: Layout

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: DSSpacing.m) {
            sectionTitle(title)
            content()
        }
        .padding(.horizontal, DSSpacing.screenMargin)
    }

    private func sectionTitle(_ title: String) -> some View {
        Text(title)
            .dsMetaMono(DSColor.textPrimary)
            .accessibilityAddTraits(.isHeader)
    }

    // MARK: Samples

    private struct SimulationItem: Identifiable {
        let simulation: FilmSimulation
        var id: String { simulation.rawValue }
    }

    private struct SampleRecipe: Identifiable {
        let number: String
        let name: String
        let simulation: FilmSimulation?
        let meta: String
        let slot: String?
        var id: String { number }
    }

    private static let sampleRecipes = [
        SampleRecipe(number: "034", name: "Kodachrome 64", simulation: .classicChrome,
                     meta: "Classic Chrome   Grain Weak", slot: "C1"),
        SampleRecipe(number: "035", name: "Lua de Mel", simulation: .classicNeg,
                     meta: "Classic Neg.   DR400", slot: "C3"),
        SampleRecipe(number: "036", name: "Tri-X 400 with a deliberately long name", simulation: .acrosYe,
                     meta: "ACROS + Ye Filter   Grain Strong", slot: "C4"),
        SampleRecipe(number: "037", name: "Velvia Summer", simulation: .velvia,
                     meta: "Velvia / Vivid   Color +3", slot: nil),
        SampleRecipe(number: "038", name: "Untitled", simulation: nil, meta: "No Film Simulation", slot: nil)
    ]

    private static let frameSimulations: [FilmSimulation] = [.classicChrome, .velvia, .acros, .nostalgicNeg, .eterna, .provia]
}

#Preview("Gallery, light") {
    NavigationStack { DesignSystemGallery() }
        .preferredColorScheme(.light)
}

#Preview("Gallery, dark") {
    NavigationStack { DesignSystemGallery() }
        .preferredColorScheme(.dark)
}
