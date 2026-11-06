import SwiftUI
import UIKit

/// The recipe card as it sits on a Frame & Fit canvas: **everything except the photograph.**
///
/// Frame & Fit already owns the picture — which photos, how they're cropped, the mat, the carousel
/// tiles — so the card contributes only its type and its paper, transparent wherever the frame
/// beneath should show through. That is what lets the same drag pan a photo under a card, instead
/// of the card carrying a second, rival crop of its own.
///
/// Authored at whatever canvas the photographer picked, with every size resolved from that canvas's
/// short edge by `ShareCardMetrics`. Nothing here may consult the size class, the safe area, or
/// Dynamic Type: it is a poster, not a screen, and it has to come out identical on every device.
///
/// `Equatable` on purpose, and applied with `.equatable()` in Frame & Fit's preview: the preview
/// redraws on every point of a photo drag, but a drag moves the picture *inside* its opening and
/// leaves the opening — and so this whole card — untouched. Being comparable lets SwiftUI skip
/// laying out forty-odd views and re-breaking the title with Core Text for a change that cannot have
/// affected any of it.
struct ShareCardOverlay: View, Equatable {
    let options: ShareCardOptions
    let content: ShareCardContent
    let metrics: ShareCardMetrics

    var body: some View {
        Group {
            switch options.style {
            case .plain:
                PlainCard(content: content, tone: options.tone, corner: options.corner, m: metrics)
            case .story:
                StoryCard(content: content, m: metrics)
            case .feed:
                FeedCard(content: content, m: metrics)
            case .specimen:
                SpecimenCard(content: content, m: metrics)
            case .quarterGrid:
                QuarterGridCard(content: content, m: metrics)
            }
        }
        .frame(width: metrics.canvas.width, height: metrics.canvas.height)
        .clipped()
        // The paper cards must stay warm paper after dark, and no card may reflow at an
        // accessibility text size — the export has to be the same picture for everyone.
        .environment(\.colorScheme, .light)
        .dynamicTypeSize(.large)
    }
}

// MARK: - Plain

/// The settings set straight onto the photograph — no panel, no rules, no scrim.
///
/// The design drew this twice, once light-on-dark anchored bottom-right and once ink-on-light
/// anchored top-right. Both are this one layout: a `tone` picks the palette and a `corner` picks
/// where the block sits, because "put the type where the photograph is quiet" is a decision about a
/// particular frame, not one a preset can make in advance. What buys legibility either way is the
/// block's drop shadow rather than a gradient — the photo is never dimmed.
private struct PlainCard: View {
    let content: ShareCardContent
    let tone: PlainTone
    let corner: PlainCorner
    let m: ShareCardMetrics

    /// Ink type on a bright photograph — the design's Style B.
    private var usesInk: Bool { tone == .dark }

    // The design's opacities were drawn against an empty frame. Over a real photograph — dappled
    // foliage, grass, anything with its own texture — a faded half of each line doesn't hold up,
    // so everything is lifted and the hierarchy is carried by the gap between 100% and 82%
    // rather than by fading the values toward the picture.
    private var textColor: Color { usesInk ? CardPalette.overlayInk : CardPalette.overlayLight }
    private var labelOpacity: Double { 1.0 }
    private var valueOpacity: Double { 0.82 }
    private var signOffOpacity: Double { usesInk ? 0.85 : 0.88 }
    /// Only a touch under full strength. This was drawn faint against an empty frame; over a real
    /// photograph a faded byline stops being quiet and starts being unreadable, so it sits within
    /// a few points of full strength and the hierarchy is carried by size instead.
    private var creditOpacity: Double { usesInk ? 0.88 : 0.92 }

    private var blockWidth: CGFloat { m.canvas.width - 2 * m.s(PlainSpec.inset) }

    var body: some View {
        Color.clear
            .overlay(alignment: corner.alignment) {
                block.padding(m.s(PlainSpec.inset))
            }
    }

    private var block: some View {
        VStack(alignment: corner.horizontal, spacing: 0) {
            CardTitle(text: content.name,
                      size: m.s(PlainSpec.name),
                      lineHeight: PlainSpec.nameLineHeight,
                      trackingEm: PlainSpec.nameTracking,
                      color: textColor,
                      maxWidth: blockWidth,
                      alignment: corner.horizontal)

            if let credit = content.creditLine {
                CardCredit(text: credit, size: m.s(PlainSpec.credit), trackingEm: 0.12,
                           color: textColor.opacity(creditOpacity), maxWidth: blockWidth)
                    .padding(.top, m.s(PlainSpec.creditTop))
            }

            // Film simulation heads the list as its own row, styled exactly like the parameters
            // beneath it — Plain has no swatch or small-caps meta line to set it apart with.
            VStack(alignment: corner.horizontal, spacing: m.s(PlainSpec.settingsSpacing)) {
                ForEach(content.linesWithFilmSimulation) { line in
                    (Text(line.label).foregroundStyle(textColor.opacity(labelOpacity))
                        + Text(" ")
                        + Text(line.value).foregroundStyle(textColor.opacity(valueOpacity)))
                        .font(.system(size: m.s(PlainSpec.settings)))
                        .monospacedDigit()
                        .fixedSize()
                        .frame(height: m.s(PlainSpec.settings) * PlainSpec.settingsLineHeight)
                }
            }
            .padding(.top, m.s(PlainSpec.settingsTop))

            // The mark sits on the outside of the wordmark, so the sign-off hangs off the same edge
            // the rest of the block is flush to.
            CardWordmark(textSize: m.s(PlainSpec.wordmark),
                         color: textColor.opacity(signOffOpacity),
                         markColor: usesInk ? CardPalette.mark : CardPalette.markOnDark,
                         markTrails: corner.isTrailing)
                .padding(.top, m.s(PlainSpec.signOffTop))
        }
        // Two shadow passes, because one wide soft one isn't enough on its own: a wide blur spreads
        // its darkness so thin that a light stroke over a bright leaf still lands on a bright leaf.
        // The tight pass hugs the letterforms and gives every stroke its own edge; the wide one still
        // separates the whole block from the picture. Together they hold the type without a scrim,
        // which is the point of the style.
        .shadow(color: usesInk ? CardPalette.overlayLightShadowTight : CardPalette.overlayShadowTight,
                radius: m.s(0.0037), y: m.s(0.000926))
        .shadow(color: usesInk ? CardPalette.overlayLightShadow : CardPalette.overlayShadow,
                radius: m.s(usesInk ? 0.0148 : 0.0130), y: m.s(0.000926))
    }
}

// MARK: - Story

/// The photo fills the whole frame and the details sit in a gradient foot, so they hold over any
/// photograph rather than only a calm one.
private struct StoryCard: View {
    let content: ShareCardContent
    let m: ShareCardMetrics

    private var light: Color { CardPalette.storyLight }
    private var contentWidth: CGFloat { m.canvas.width - 2 * m.s(StorySpec.side) }
    private var columnWidth: CGFloat {
        let columns = CGFloat(m.ledgerColumns)
        return (contentWidth - m.s(StorySpec.columnGap) * (columns - 1)) / columns
    }

    var body: some View {
        Color.clear
            .overlay(alignment: .top) { topBar }
            .overlay(alignment: .bottom) { foot }
    }

    private var topBar: some View {
        HStack(spacing: 0) {
            CardWordmark(textSize: m.s(StorySpec.barText),
                         color: light,
                         markColor: CardPalette.markOnDark)
            Spacer(minLength: m.s(StorySpec.barGap) * 2)
        }
        // The sign-off carries its own shadow rather than leaning on the gradient alone. The foot has
        // a deep gradient to sit on; the top bar has a shallow one, and a photograph whose top edge
        // is bright sky — the common case — leaves white type on white. The two passes are the Plain
        // card's: a tight one to give each stroke an edge, a wide one to lift the whole run.
        .shadow(color: CardPalette.overlayShadowTight, radius: m.s(0.0037), y: m.s(0.000926))
        .shadow(color: CardPalette.overlayShadow, radius: m.s(0.0130), y: m.s(0.000926))
        .padding(.top, m.s(StorySpec.barTop))
        .padding(.horizontal, m.s(StorySpec.side))
        .padding(.bottom, m.s(StorySpec.barBottom))
        .frame(maxWidth: .infinity)
        .background(
            LinearGradient(colors: [Color(red: 18 / 255, green: 16 / 255, blue: 12 / 255).opacity(0.62),
                                    Color(red: 18 / 255, green: 16 / 255, blue: 12 / 255).opacity(0)],
                           startPoint: .top, endPoint: .bottom)
        )
    }

    private var foot: some View {
        VStack(alignment: .leading, spacing: 0) {
            CardTitle(text: content.name,
                      size: m.s(StorySpec.name),
                      lineHeight: StorySpec.nameLineHeight,
                      trackingEm: -0.015,
                      color: light,
                      maxWidth: contentWidth)

            if let credit = content.creditLine {
                CardCredit(text: credit, size: m.s(StorySpec.credit), trackingEm: 0.14,
                           color: light.opacity(0.88), maxWidth: contentWidth)
                    .padding(.top, m.s(StorySpec.creditTop))
            }

            if let simulation = content.filmSimulationName {
                HStack(spacing: m.s(StorySpec.filmGap)) {
                    FilmSwatch(simulation: content.filmSimulation, size: m.s(StorySpec.swatch))
                    CardCaps(text: simulation, size: m.s(StorySpec.film), trackingEm: 0.18,
                             color: light.opacity(0.78))
                }
                .padding(.top, m.s(StorySpec.filmTop))
            }

            CardLedger(columns: content.columns(m.ledgerColumns),
                       columnWidth: columnWidth,
                       gap: m.s(StorySpec.columnGap),
                       labelSize: m.s(StorySpec.label),
                       valueSize: m.s(StorySpec.value),
                       labelColor: light.opacity(0.55),
                       valueColor: light,
                       ruleColor: light.opacity(0.18),
                       verticalPadding: m.s(StorySpec.rowPadding),
                       ruleHeight: m.hairline)
                .padding(.top, m.s(StorySpec.ledgerTop))
        }
        .padding(.top, m.s(StorySpec.footTop))
        .padding(.horizontal, m.s(StorySpec.side))
        // Deliberate: it keeps the block clear of the story UI Instagram draws along the bottom.
        .padding(.bottom, m.s(StorySpec.footBottom))
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            LinearGradient(stops: [.init(color: CardPalette.gradientInk(0.92), location: 0),
                                   .init(color: CardPalette.gradientInk(0.92), location: 0.34),
                                   .init(color: CardPalette.gradientInk(0.6), location: 0.60),
                                   .init(color: CardPalette.gradientInk(0), location: 1)],
                           startPoint: .bottom, endPoint: .top)
        )
    }
}

// MARK: - Feed

/// Photo-forward, with the settings as a ledger on paper beneath it. The photograph takes whatever
/// height the type doesn't need, so the split follows the canvas instead of being drawn into it.
private struct FeedCard: View {
    let content: ShareCardContent
    let m: ShareCardMetrics

    private var contentWidth: CGFloat { m.canvas.width - 2 * m.s(FeedSpec.side) }
    private var columnWidth: CGFloat {
        let columns = CGFloat(m.ledgerColumns)
        return (contentWidth - m.s(FeedSpec.columnGap) * (columns - 1)) / columns
    }

    var body: some View {
        VStack(spacing: 0) {
            photoTreatment
            paperBlock.background(CardPalette.paper)
        }
    }

    /// Over the photograph the card adds only a gradient; the picture itself is the frame's, drawn
    /// beneath. The gradient is what settles the join between the photograph and the paper.
    private var photoTreatment: some View {
        Color.clear
            .frame(width: m.canvas.width, height: m.photoFrame.height)
            .overlay(alignment: .bottom) {
                LinearGradient(colors: [CardPalette.photoGradientInk(0.55),
                                        CardPalette.photoGradientInk(0)],
                               startPoint: .bottom, endPoint: .top)
                    .frame(height: m.s(FeedSpec.gradient))
            }
    }

    private var paperBlock: some View {
        VStack(alignment: .leading, spacing: 0) {
            CardTitle(text: content.name,
                      size: m.s(FeedSpec.name),
                      lineHeight: FeedSpec.nameLineHeight,
                      trackingEm: FeedSpec.nameTracking,
                      color: CardPalette.ink,
                      maxWidth: contentWidth)

            if let credit = content.creditLine {
                CardCredit(text: credit, size: m.s(FeedSpec.credit), trackingEm: 0.12,
                           color: CardPalette.ink2, maxWidth: contentWidth)
                    .padding(.top, m.s(FeedSpec.creditTop))
            }

            // The rule divides identity from recipe: the name and its byline above it, the base
            // film simulation and every parameter that adjusts it below.
            Rectangle()
                .fill(CardPalette.line)
                .frame(height: m.hairline)
                .padding(.top, m.s(FeedSpec.ruleTop))
                .padding(.bottom, m.s(FeedSpec.ruleBottom))

            HStack(spacing: m.s(FeedSpec.filmGap)) {
                if let simulation = content.filmSimulationName {
                    FilmSwatch(simulation: content.filmSimulation, size: m.s(FeedSpec.swatch))
                    CardCaps(text: simulation, size: m.s(FeedSpec.film), trackingEm: 0.16,
                             color: CardPalette.ink2)
                }
            }
            .frame(height: m.s(FeedSpec.film))
            .padding(.top, m.s(FeedSpec.filmTop))

            CardLedger(columns: content.columns(m.ledgerColumns),
                       columnWidth: columnWidth,
                       gap: m.s(FeedSpec.columnGap),
                       labelSize: m.s(FeedSpec.label),
                       valueSize: m.s(FeedSpec.value),
                       labelColor: CardPalette.ink3,
                       valueColor: CardPalette.ink,
                       ruleColor: CardPalette.line,
                       verticalPadding: m.s(FeedSpec.rowPadding),
                       ruleHeight: m.hairline)

            Spacer(minLength: 0)

            HStack(spacing: 0) {
                CardWordmark(textSize: m.s(FeedSpec.footerText),
                             color: CardPalette.ink,
                             markColor: CardPalette.mark)
                Spacer(minLength: m.s(FeedSpec.footerGap))
            }
            .padding(.top, m.s(FeedSpec.footerTop))
        }
        .padding(.top, m.s(FeedSpec.paperTop))
        .padding(.horizontal, m.s(FeedSpec.side))
        .padding(.bottom, m.s(FeedSpec.paperBottom))
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

// MARK: - Specimen

/// A page with a visible paper margin, so the photo sits *inside* it rather than filling it — the
/// specimen sheet of the set.
private struct SpecimenCard: View {
    let content: ShareCardContent
    let m: ShareCardMetrics

    private var contentWidth: CGFloat { m.canvas.width - 2 * m.s(SpecimenSpec.margin) }
    private var columnWidth: CGFloat {
        let columns = CGFloat(m.ledgerColumns)
        return (contentWidth - m.s(SpecimenSpec.columnGap) * (columns - 1)) / columns
    }

    var body: some View {
        VStack(spacing: 0) {
            header.padding(.bottom, m.s(SpecimenSpec.headerBottom))

            // The photograph's window: left clear so the frame shows through it.
            Color.clear
                .frame(width: contentWidth, height: m.photoFrame.height)

            nameBlock.padding(.top, m.s(SpecimenSpec.nameTop))

            // Identity above the rule, recipe below it — the base film simulation heads the settings
            // it is the base for.
            Rectangle()
                .fill(CardPalette.line)
                .frame(height: m.hairline)
                .padding(.top, m.s(SpecimenSpec.ruleTop))

            filmRow

            CardLedger(columns: content.columns(m.ledgerColumns),
                       columnWidth: columnWidth,
                       gap: m.s(SpecimenSpec.columnGap),
                       labelSize: m.s(SpecimenSpec.label),
                       valueSize: m.s(SpecimenSpec.value),
                       labelColor: CardPalette.ink3,
                       valueColor: CardPalette.ink,
                       ruleColor: CardPalette.line,
                       verticalPadding: m.s(SpecimenSpec.rowPadding),
                       ruleHeight: m.hairline)

            Spacer(minLength: 0)
        }
        .padding(m.s(SpecimenSpec.margin))
        // Paper everywhere except the window — one even-odd fill rather than four rectangles, so the
        // hole is exact and there is no seam for a rounding error to show through.
        .background {
            Path { path in
                path.addRect(CGRect(origin: .zero, size: m.canvas))
                path.addRect(m.photoFrame)
            }
            .fill(CardPalette.paper, style: FillStyle(eoFill: true))
        }
    }

    private var header: some View {
        HStack(spacing: 0) {
            CardWordmark(textSize: m.s(SpecimenSpec.headerWordmark),
                         color: CardPalette.ink,
                         markColor: CardPalette.mark)
            Spacer(minLength: m.s(SpecimenSpec.headerGap) * 2)
            if let number = content.recipeNumber {
                CardCaps(text: "Recipe № \(String(format: "%02d", number))",
                         size: m.s(SpecimenSpec.headerText), trackingEm: 0.14,
                         color: CardPalette.ink2)
            }
        }
        .frame(height: m.s(max(SpecimenSpec.headerWordmark, SpecimenSpec.headerText)))
    }

    /// The name and its byline — everything that says which recipe this is.
    private var nameBlock: some View {
        VStack(alignment: .leading, spacing: 0) {
            CardTitle(text: content.name,
                      size: m.s(SpecimenSpec.name),
                      lineHeight: SpecimenSpec.nameLineHeight,
                      trackingEm: SpecimenSpec.nameTracking,
                      color: CardPalette.ink,
                      maxWidth: contentWidth)

            if let credit = content.creditLine {
                CardCredit(text: credit, size: m.s(SpecimenSpec.credit), trackingEm: 0.12,
                           color: CardPalette.ink2, maxWidth: contentWidth)
                    .padding(.top, m.s(SpecimenSpec.creditTop))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// The base the ledger beneath it adjusts.
    private var filmRow: some View {
        HStack(spacing: m.s(SpecimenSpec.filmGap)) {
            if let simulation = content.filmSimulationName {
                FilmSwatch(simulation: content.filmSimulation, size: m.s(SpecimenSpec.swatch))
                CardCaps(text: simulation, size: m.s(SpecimenSpec.film), trackingEm: 0.16,
                         color: CardPalette.ink2)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(height: m.s(SpecimenSpec.filmRowHeight))
        .padding(.top, m.s(SpecimenSpec.filmTop))
    }
}

// MARK: - Quarter Grid

/// A 2 × 2 grid of equal cells on paper: the recipe in the first, three photographs in the rest.
///
/// The frame lays the grid out (see `ShareCardFramePlan`); the card draws the paper around the
/// windows, the type in the cell the photographs skipped, and the sign-off beneath. Unlike the
/// ledger cards this sets the parameters as a plain list — no rules, no small caps — so it reads as
/// a note beside the pictures it describes rather than a table under them.
private struct QuarterGridCard: View {
    let content: ShareCardContent
    let m: ShareCardMetrics

    /// A size in the text block, scaled to fit the cell.
    private func t(_ fraction: CGFloat) -> CGFloat { m.s(fraction) * m.textScale }

    var body: some View {
        ZStack(alignment: .topLeading) {
            // Paper everywhere except the windows — one even-odd fill, as on the Specimen card. The
            // corners of each window are rounded here, in the paper, because the frame beneath
            // clips its photographs to plain rectangles and knows nothing about the card.
            Path { path in
                path.addRect(CGRect(origin: .zero, size: m.canvas))
                let radius = m.s(QuarterGridSpec.radius)
                for window in m.photoFrames {
                    path.addRoundedRect(in: window,
                                        cornerSize: CGSize(width: radius, height: radius),
                                        style: .continuous)
                }
            }
            .fill(CardPalette.paper, style: FillStyle(eoFill: true))

            textBlock
                .frame(width: m.textFrame.width, height: m.textFrame.height, alignment: .topLeading)
                .offset(x: m.textFrame.minX, y: m.textFrame.minY)
        }
        .frame(width: m.canvas.width, height: m.canvas.height, alignment: .topLeading)
        .overlay(alignment: .bottom) {
            footer.padding(.bottom, m.s(QuarterGridSpec.bottomInset + QuarterGridSpec.footerPad))
        }
    }

    private var textBlock: some View {
        VStack(alignment: .leading, spacing: 0) {
            CardTitle(text: content.name,
                      size: t(QuarterGridSpec.name),
                      lineHeight: QuarterGridSpec.nameLineHeight,
                      trackingEm: QuarterGridSpec.nameTracking,
                      color: CardPalette.ink,
                      maxWidth: m.textFrame.width)

            if let credit = content.credit {
                creditLine(credit).padding(.top, t(QuarterGridSpec.creditTop))
            }

            if let simulation = content.filmSimulationName {
                HStack(spacing: t(QuarterGridSpec.filmGap)) {
                    FilmSwatch(simulation: content.filmSimulation, size: t(QuarterGridSpec.swatch))
                    Text(simulation)
                        .font(.system(size: t(QuarterGridSpec.film), weight: .semibold, design: .serif))
                        .foregroundStyle(CardPalette.ink)
                        .lineLimit(1)
                        .frame(height: t(QuarterGridSpec.film) * QuarterGridSpec.filmLineHeight)
                }
                .frame(height: t(QuarterGridSpec.filmRowHeight))
                .padding(.top, t(QuarterGridSpec.filmTop))
            }

            if !content.lines.isEmpty {
                VStack(spacing: t(QuarterGridSpec.rowGap)) {
                    ForEach(content.lines) { row($0) }
                }
                .padding(.top, t(QuarterGridSpec.listTop))
            }
        }
    }

    /// "by lumenfoto" — plain and quiet, in the design's own voice, on one line.
    private func creditLine(_ credit: String) -> some View {
        let size = t(QuarterGridSpec.credit)
        let font = CardFont(size: size)
        let text = "by \(credit)"
        let fitted = CardTextLayout.lines(text,
                                          font: font.uiFont,
                                          tracking: 0,
                                          maxWidth: m.textFrame.width,
                                          limit: 1).first ?? text
        return Text(fitted)
            .font(font.font)
            .foregroundStyle(CardPalette.ink2)
            .fixedSize()
            .frame(height: size * QuarterGridSpec.creditLineHeight)
    }

    /// One parameter: label on the left in the secondary ink, value on the right in the primary.
    private func row(_ line: ShareCardContent.Line) -> some View {
        let size = t(QuarterGridSpec.row)
        return HStack(alignment: .firstTextBaseline, spacing: t(QuarterGridSpec.rowValueGap)) {
            Text(line.label)
                .font(.system(size: size))
                .foregroundStyle(CardPalette.ink2)
                .lineLimit(1)
            Spacer(minLength: 0)
            Text(line.value)
                .font(.system(size: size, weight: .semibold))
                .monospacedDigit()
                .foregroundStyle(CardPalette.ink)
                .lineLimit(1)
                .layoutPriority(1)
        }
        // Pinned rather than natural, so resolving the block's height and drawing it agree.
        .frame(height: size * QuarterGridSpec.rowLineHeight)
    }

    /// The sign-off, centred under the grid: the brand lockup, with the card's kind in caps on the
    /// same baseline.
    private var footer: some View {
        HStack(alignment: .lastTextBaseline, spacing: m.s(QuarterGridSpec.footerGap)) {
            CardWordmark(textSize: m.s(QuarterGridSpec.footerSerif),
                         color: CardPalette.ink2,
                         markColor: CardPalette.mark)
                .frame(height: m.s(QuarterGridSpec.footerSerif) * QuarterGridSpec.footerLineHeight)
            CardCaps(text: "Recipe card",
                     size: m.s(QuarterGridSpec.footerCaps),
                     weight: .medium,
                     trackingEm: QuarterGridSpec.footerCapsTracking,
                     color: CardPalette.ink3)
        }
    }
}

// MARK: - Shared ledger

/// The multi-column settings ledger shared by the Story, Feed and Specimen cards. The columns arrive
/// filled one at a time (`ShareCardContent.columns(_:)`), so the fixed parameter order reads down
/// the first column and on into the next, and each column drops the hairline under its own last row.
private struct CardLedger: View {
    let columns: [[ShareCardContent.Line]]
    let columnWidth: CGFloat
    let gap: CGFloat
    let labelSize: CGFloat
    let valueSize: CGFloat
    let labelColor: Color
    let valueColor: Color
    let ruleColor: Color
    let verticalPadding: CGFloat
    let ruleHeight: CGFloat

    var body: some View {
        HStack(alignment: .top, spacing: gap) {
            ForEach(Array(columns.enumerated()), id: \.offset) { _, column in
                VStack(spacing: 0) {
                    ForEach(Array(column.enumerated()), id: \.element.id) { index, line in
                        CardLedgerRow(line: line,
                                      labelSize: labelSize,
                                      valueSize: valueSize,
                                      labelColor: labelColor,
                                      valueColor: valueColor,
                                      ruleColor: ruleColor,
                                      verticalPadding: verticalPadding,
                                      showsRule: index < column.count - 1,
                                      ruleHeight: ruleHeight)
                    }
                }
                .frame(width: columnWidth, alignment: .top)
            }
        }
    }
}
