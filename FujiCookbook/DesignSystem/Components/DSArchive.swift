import SwiftUI

/// One field of a data sheet: a mono caption over a mono value.
struct DSDataField: Identifiable, Equatable {
    let label: String
    let value: String
    var id: String { label }
}

/// A field's caption and value, stacked.
struct DSDataFieldCell: View {
    let field: DSDataField
    var valueColor: Color = DSColor.textPrimary

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(field.label).dsFieldLabel()
            Text(field.value)
                .font(DSFont.valueMono)
                .foregroundStyle(valueColor)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

/// A row of equally wide fields separated by 1.5 pt rules, framed: "ARCHIVE 024 | CAMERA 5/7".
struct DSDataFieldRow: View {
    let fields: [DSDataField]
    /// Counters read in signal blue.
    var valueColor: Color = DSColor.signalText

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Array(fields.enumerated()), id: \.element.id) { index, field in
                if index > 0 { DSRule(vertical: true) }
                DSDataFieldCell(field: field, valueColor: valueColor)
                    .padding(.horizontal, DSSpacing.m)
                    .padding(.vertical, DSSpacing.s)
            }
        }
        .fixedSize(horizontal: false, vertical: true)
        .dsArchiveFrame()
    }
}

/// The square archive card: `surface` inside a 1.5 pt rule. Its parts stack with rules between
/// them; see `DSArchiveHeader`, `DSSimulationBand`, `DSDataSheet` and `DSArchiveFooter`.
struct DSArchiveCard<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) { content }
            .dsArchiveFrame()
    }
}

/// The card's head: the object number on the left, side fields (SLOT, CHAPTER, CREATED) on the
/// right, a rule between them.
struct DSArchiveHeader: View {
    /// "034".
    let objectNumber: String
    let fields: [DSDataField]

    var body: some View {
        HStack(spacing: 0) {
            Text(objectNumber)
                .dsObjectNumber(size: 64)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .padding(.horizontal, DSSpacing.m)
                .padding(.vertical, DSSpacing.s)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityLabel("Archive number \(objectNumber)")
            DSRule(vertical: true)
            VStack(spacing: 0) {
                ForEach(Array(fields.enumerated()), id: \.element.id) { index, field in
                    if index > 0 { DSSeparator() }
                    DSDataFieldCell(field: field)
                        .padding(.horizontal, DSSpacing.m)
                        .padding(.vertical, DSSpacing.xs + 2)
                }
            }
            .frame(width: 128)
        }
        .fixedSize(horizontal: false, vertical: true)
    }
}

/// The title and description between the head and the simulation band.
struct DSArchiveTitle: View {
    let title: String
    var description: String?

    var body: some View {
        VStack(alignment: .leading, spacing: DSSpacing.xs) {
            Text(title)
                .font(DSFont.title)
                .foregroundStyle(DSColor.textPrimary)
            if let description {
                Text(description)
                    .font(DSFont.subhead)
                    .foregroundStyle(DSColor.textSecondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(DSSpacing.m)
    }
}

/// The film simulation as a 64 pt band of its color: its name in heavy type, the code on the right.
struct DSSimulationBand: View {
    let simulation: FilmSimulation?
    @ScaledMetric(relativeTo: .title2) private var nameSize: CGFloat = 22

    private var fill: Color { simulation?.dsFill ?? DSNoSimulation.fill }
    private var text: Color { simulation?.dsText ?? DSNoSimulation.text }

    var body: some View {
        HStack {
            Text(simulation?.displayName ?? "No Film Simulation")
                .font(.system(size: nameSize, weight: .heavy))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Spacer(minLength: DSSpacing.s)
            Text(simulation?.dsCode ?? DSNoSimulation.code)
                .dsSmallMono(size: 13, weight: .bold)
        }
        .foregroundStyle(text)
        .padding(.horizontal, DSSpacing.m)
        .frame(maxWidth: .infinity, minHeight: DSSize.simulationBandHeight)
        .background(fill)
        .accessibilityElement(children: .combine)
    }
}

/// The settings in two columns of caption over value, with 1 pt lines inside.
struct DSDataSheet: View {
    let fields: [DSDataField]

    private var rows: [[DSDataField]] {
        stride(from: 0, to: fields.count, by: 2).map { Array(fields[$0..<min($0 + 2, fields.count)]) }
    }

    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(rows.enumerated()), id: \.offset) { index, row in
                if index > 0 { DSSeparator() }
                HStack(spacing: 0) {
                    DSDataFieldCell(field: row[0])
                        .padding(.horizontal, DSSpacing.m)
                        .padding(.vertical, DSSpacing.s)
                    Rectangle().fill(DSColor.separator).frame(width: DSLine.hairline)
                    Group {
                        if row.count > 1 { DSDataFieldCell(field: row[1]) } else { Color.clear }
                    }
                    .padding(.horizontal, DSSpacing.m)
                    .padding(.vertical, DSSpacing.s)
                }
                .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

/// The card's foot: the decorative barcode and a mono line such as "X100VI  AS WRITTEN".
struct DSArchiveFooter: View {
    let barcodeSeed: String
    let text: String

    var body: some View {
        HStack(spacing: DSSpacing.m) {
            DSBarcode(seed: barcodeSeed)
                .frame(maxWidth: 140)
            Spacer(minLength: 0)
            Text(text).dsMetaMono(DSColor.textPrimary)
        }
        .padding(DSSpacing.m)
    }
}

/// A square tag such as a chapter: STREET.
struct DSTag: View {
    let text: String
    var systemImage: String?

    var body: some View {
        HStack(spacing: DSSpacing.xs) {
            if let systemImage { Image(systemName: systemImage).font(DSFont.metaMono.weight(.bold)) }
            Text(text)
                .dsSmallMono(size: 11, weight: .bold)
                .textCase(.uppercase)
                .tracking(DSFont.metaMonoTracking * DSFont.metaMonoSize)
                .lineLimit(1)
        }
        .foregroundStyle(DSColor.textPrimary)
        .padding(.horizontal, DSSpacing.s)
        .padding(.vertical, DSSpacing.xs)
        .overlay(Rectangle().strokeBorder(DSColor.rule, lineWidth: DSLine.rule))
        .accessibilityElement(children: .combine)
    }
}

#Preview("Archive card") {
    ScrollView {
        VStack(alignment: .leading, spacing: DSSpacing.l) {
            DSDataFieldRow(fields: [DSDataField(label: "Archive", value: "024"),
                                    DSDataField(label: "Camera", value: "5/7")])
            DSArchiveCard {
                DSArchiveHeader(objectNumber: "034",
                                fields: [DSDataField(label: "Slot", value: "C3"),
                                         DSDataField(label: "Chapter", value: "Street"),
                                         DSDataField(label: "Created", value: "2026-11-14")])
                DSRule()
                DSArchiveTitle(title: "Lua de Mel", description: "Warm, soft contrast for late light.")
                DSSimulationBand(simulation: .classicNeg)
                DSDataSheet(fields: [DSDataField(label: "Dynamic Range", value: "DR400"),
                                     DSDataField(label: "Grain", value: "Weak Small"),
                                     DSDataField(label: "Highlight", value: DSValueFormat.signed(-1)),
                                     DSDataField(label: "Shadow", value: DSValueFormat.signed(2)),
                                     DSDataField(label: "White Balance", value: "R+2  B\u{2212}5")])
                DSRule()
                DSArchiveFooter(barcodeSeed: "lua-de-mel", text: "X100VI  As Written")
            }
            HStack { DSTag(text: "Street"); DSTag(text: "Travel", systemImage: "tag") }
        }
        .padding()
    }
    .background(DSColor.background)
}
