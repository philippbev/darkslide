import SwiftUI

/// The five presets of the share-card renderer (design handoff "Recipe Share Card").
///
/// They are presets, not separate features: one content model, one sign-off, five layouts.
///
/// A style owns no canvas size. The design was drawn at four fixed shapes — 1080 × 1440,
/// × 1920, × 1350, × 1080 — but those shapes are an *output ratio*, which Frame & Fit already models
/// as `FrameCanvas` and lets the photographer choose. So a style here describes only a layout, and
/// `metrics(canvas:content:)` resolves it against whatever shape it is asked for. Every number in
/// the resolved metrics is a fraction of the canvas's **short edge**, so a card at 4:5 and the same
/// card at 9:16 are the same design rather than the same numbers.
enum ShareCardStyle: String, CaseIterable, Identifiable {
    /// Settings set straight onto the photograph, in a corner of your choosing.
    case plain
    /// Details in a gradient foot over a full-bleed photograph.
    case story
    /// Photo-forward: the photograph on top, the settings as a ledger on paper below.
    case feed
    /// The photograph inset in a paper page, with a visible margin.
    case specimen
    /// A 2 × 2 grid of equal cells on paper — the recipe in the first, a photograph in each of the
    /// other three (design 2a, "Quarter grid").
    case quarterGrid

    var id: String { rawValue }

    var title: String {
        switch self {
        case .plain: return "Plain"
        case .story: return "Story"
        case .feed: return "Feed"
        case .specimen: return "Specimen"
        case .quarterGrid: return "Quarter Grid"
        }
    }

    /// The shape the design was drawn at, used only to explain a style that a canvas can't hold.
    var nativeRatioText: String {
        switch self {
        case .plain: return "any shape"
        case .story: return "9:16"
        case .feed: return "4:5"
        case .specimen: return "1:1"
        case .quarterGrid: return "4:5"
        }
    }

    /// Column count the design used at the style's native shape. Resolution never goes below it —
    /// extra columns are added only when a wider or shorter canvas needs the block to get shorter.
    var designColumns: Int {
        switch self {
        case .plain: return 1
        case .story: return 2
        case .feed, .specimen: return 3
        case .quarterGrid: return 1
        }
    }

    /// Most columns a ledger is ever split into, however much width there is. Past five the labels
    /// stop being a ledger and start being a table.
    static let maxColumns = 5

    /// True when the style brings its own paper — a ledger under the photograph, or a page around it.
    ///
    /// This is the line between the two kinds of card. An overlay style only writes on the
    /// photograph, so it lives inside whatever opening the frame gives it and the mat is none of its
    /// business. A paper style *is* a mat, which is why the frame's own border stands down for it:
    /// two stacked paper margins is nobody's design.
    var suppliesPaper: Bool {
        switch self {
        case .plain, .story: return false
        case .feed, .specimen, .quarterGrid: return true
        }
    }

    /// What the style asks of the frame's own layout, when it needs more than a band of the canvas.
    ///
    /// Feed and Specimen need the frame only to hold back a strip of canvas for their type. Quarter
    /// Grid needs the frame to lay its photographs out on a grid with one cell left empty for the
    /// recipe. Rather than composite photographs itself — and lose the per-cell pan and
    /// zoom Frame & Fit already has — it hands the frame a plan and draws only the paper and the
    /// type, which is the same division of labour as every other card.
    var framePlan: ShareCardFramePlan? {
        switch self {
        case .plain, .story, .feed, .specimen:
            return nil
        case .quarterGrid:
            return ShareCardFramePlan(arrangement: .grid,
                                      border: QuarterGridSpec.border,
                                      gap: QuarterGridSpec.gap,
                                      bandTop: 0,
                                      bandBottom: QuarterGridSpec.footerBand,
                                      reservedCells: 1,
                                      photoCapacity: 3)
        }
    }
}

/// A layout a style dictates to Frame & Fit while it is on: the grid; the mat, gutter and bands as
/// fractions of the short edge, the reference `FrameOptions` measures its mat by; the leading grid
/// cells the card keeps for its type; and how many photographs the rest of the grid holds.
struct ShareCardFramePlan: Equatable {
    let arrangement: FrameArrangement
    let border: CGFloat
    let gap: CGFloat
    /// Canvas held back beyond the mat, top and bottom. Off the short edge rather than the height
    /// so the frame and the card round the same number to the same pixel.
    let bandTop: CGFloat
    let bandBottom: CGFloat
    let reservedCells: Int
    let photoCapacity: Int
}

/// Which way the Plain card's type runs: light on a dark photograph, or ink on a bright one.
enum PlainTone: String, CaseIterable, Identifiable {
    /// Paper-white type with a dark shadow — for a dark photograph.
    case light
    /// Ink type with a paper-coloured halo — for a bright one.
    case dark

    var id: String { rawValue }

    var title: String {
        switch self {
        case .light: return "Light Text"
        case .dark: return "Dark Text"
        }
    }
}

/// Which corner of the Plain card the block sits in.
enum PlainCorner: String, CaseIterable, Identifiable {
    case topLeading, topTrailing, bottomLeading, bottomTrailing

    var id: String { rawValue }

    var alignment: Alignment {
        switch self {
        case .topLeading: return .topLeading
        case .topTrailing: return .topTrailing
        case .bottomLeading: return .bottomLeading
        case .bottomTrailing: return .bottomTrailing
        }
    }

    /// The type is flush to whichever side the block is on, so the block reads as a margin note
    /// rather than as a caption that lost its edge.
    var isTrailing: Bool { self == .topTrailing || self == .bottomTrailing }

    var horizontal: HorizontalAlignment { isTrailing ? .trailing : .leading }

    var title: String {
        switch self {
        case .topLeading: return "Top left"
        case .topTrailing: return "Top right"
        case .bottomLeading: return "Bottom left"
        case .bottomTrailing: return "Bottom right"
        }
    }
}

/// How a recipe card is drawn, beyond the recipe and the canvas. The photograph isn't here: in
/// Frame & Fit the frame owns it, crop and all.
struct ShareCardOptions: Equatable {
    var style: ShareCardStyle = .plain
    var tone: PlainTone = .light
    var corner: PlainCorner = .bottomTrailing
}

// MARK: - Resolved geometry

/// One card's layout, resolved against a concrete canvas.
///
/// Card views read every size through `s(_:)`, never as a literal, so the whole design travels
/// between shapes intact. Two things can't be a constant fraction and so are decided here: where the
/// photograph goes (on the paper styles it gets whatever the type doesn't need) and how many columns
/// the ledger is split into.
struct ShareCardMetrics: Equatable {
    let style: ShareCardStyle
    let canvas: CGSize
    /// The short edge — the reference every size is a fraction of.
    let unit: CGFloat
    /// Where the photograph is drawn, in canvas coordinates.
    let photoFrame: CGRect
    /// How many columns the settings ledger is split into.
    let ledgerColumns: Int
    /// How many lines the recipe name actually takes — one or two.
    ///
    /// The design reserved two lines always, so a short name left a hole and the ledger stayed put.
    /// That was the right call for a card of fixed height. Here the photograph takes whatever the
    /// type doesn't, so measuring the name instead means a one-line name buys a bigger picture.
    let nameLines: Int
    /// Every window a photograph shows through, in canvas coordinates. One entry — `photoFrame`
    /// itself — on every style but Quarter Grid, which has three.
    let photoFrames: [CGRect]
    /// Where Quarter Grid sets its type: the grid cell it keeps, less the design's cell padding.
    /// `.zero` on the styles that lay their type out from the canvas edges instead.
    let textFrame: CGRect
    /// Quarter Grid's text block, scaled down to fit its cell — 1 when it fits as drawn. Every size
    /// in the block is multiplied by this, so a long name and a full list shrink together and the
    /// block keeps its proportions rather than losing rows.
    let textScale: CGFloat

    /// A design fraction resolved to canvas points.
    func s(_ fraction: CGFloat) -> CGFloat { fraction * unit }

    /// The same metrics with the windows and the text cell taken from somewhere more exact — the
    /// frame's real openings, once its layout has run.
    func with(photoFrames: [CGRect], textFrame: CGRect) -> ShareCardMetrics {
        let union = photoFrames.dropFirst().reduce(photoFrames.first ?? photoFrame) { $0.union($1) }
        return ShareCardMetrics(style: style, canvas: canvas, unit: unit, photoFrame: union,
                                ledgerColumns: ledgerColumns, nameLines: nameLines,
                                photoFrames: photoFrames, textFrame: textFrame, textScale: textScale)
    }

    /// A hairline that stays a hairline: one pixel at the design's own scale, never less than one.
    var hairline: CGFloat { max(1, (unit / 1080).rounded()) }
}

// MARK: - Design fractions
//
// Every number below is the design document's point size divided by 1080 — the short edge of every
// shape it was drawn at. They live beside the resolver rather than inside the views so that fitting
// a card and drawing it can never disagree about how tall it is.

/// Shared by the three ledger styles: Story, Feed and Specimen.
private enum LedgerSpec {
    /// Smallest gap allowed between a label and its value before a column counts as too narrow.
    static let minLabelValueGap: CGFloat = 0.0111      // 12
}

// The sign-off is the brand kit's lockup (`CardWordmark`) rather than the design's caps run, so its
// sizes are not the design's: each wordmark is about 1.4 times the caps the design sets there,
// chosen against renders so the serif carries the same weight. The mark follows from the type size.
enum PlainSpec {
    static let inset: CGFloat = 0.0481                 // 52
    static let name: CGFloat = 0.0481                  // 52
    static let nameLineHeight: CGFloat = 1.0
    static let nameTracking: CGFloat = -0.01
    static let creditTop: CGFloat = 0.0111             // 12
    static let credit: CGFloat = 0.0148                // 16
    // The film simulation heads the settings block as its own row rather than a separate meta line
    // above it — so this is the one gap from the byline to the parameters, the design's
    // byline-to-film distance, since that's the breathing room the block wants above whatever its
    // first row is.
    static let settingsTop: CGFloat = 0.0222           // 24
    static let settings: CGFloat = 0.0241              // 26
    static let settingsLineHeight: CGFloat = 1.1
    static let settingsSpacing: CGFloat = 0.00833      // 9
    static let signOffTop: CGFloat = 0.0241            // 26
    static let wordmark: CGFloat = 0.0222              // 24

    /// `lines` includes the film simulation row — callers pass `content.linesWithFilmSimulation.count`.
    static func blockHeight(lines: Int, nameLines: Int, showsCredit: Bool) -> CGFloat {
        CGFloat(nameLines) * name * nameLineHeight
            + (showsCredit ? creditTop + credit : 0)
            + settingsTop
            + CGFloat(lines) * settings * settingsLineHeight
            + CGFloat(max(0, lines - 1)) * settingsSpacing
            + signOffTop + wordmark
    }
}

enum StorySpec {
    static let side: CGFloat = 0.0593                  // 64
    static let barTop: CGFloat = 0.0704                // 76
    static let barBottom: CGFloat = 0.0556             // 60
    static let barText: CGFloat = 0.0315               // 34
    static let barGap: CGFloat = 0.0111                // 12
    static let footTop: CGFloat = 0.2778               // 300 — the gradient's fade, not content
    static let footBottom: CGFloat = 0.1019            // 110 — clears the story UI
    static let name: CGFloat = 0.0815                  // 88
    static let nameLineHeight: CGFloat = 0.98
    static let filmTop: CGFloat = 0.0204               // 22
    static let swatch: CGFloat = 0.0120                // 13
    static let filmGap: CGFloat = 0.0120               // 13
    static let film: CGFloat = 0.0241                  // 26
    static let creditTop: CGFloat = 0.0176             // 19
    static let credit: CGFloat = 0.0204                // 22
    static let ledgerTop: CGFloat = 0.0426             // 46
    static let columnGap: CGFloat = 0.0593             // 64
    static let label: CGFloat = 0.0222                 // 24
    static let value: CGFloat = 0.0250                 // 27
    static let rowPadding: CGFloat = 0.0157            // 17

    static var rowHeight: CGFloat { value + 2 * rowPadding }

    /// Content plus the bottom margin — what the foot actually occupies. The 300 of top padding is
    /// the gradient's fade and sits over the photograph, so it isn't part of the budget.
    static func footHeight(rows: Int, nameLines: Int, showsCredit: Bool) -> CGFloat {
        CGFloat(nameLines) * name * nameLineHeight
            + (showsCredit ? creditTop + credit : 0)
            + filmTop + film
            + ledgerTop
            + CGFloat(rows) * rowHeight
            + footBottom
    }

    /// How much of the canvas the foot may eat before there is no photograph left to look at.
    static let footBudget: CGFloat = 0.58
}

enum FeedSpec {
    static let side: CGFloat = 0.0593                  // 64
    static let paperTop: CGFloat = 0.0370              // 40
    static let paperBottom: CGFloat = 0.0407           // 44
    static let name: CGFloat = 0.0648                  // 70
    static let nameLineHeight: CGFloat = 1.0
    static let nameTracking: CGFloat = -0.015
    static let filmTop: CGFloat = 0.0148               // 16
    static let swatch: CGFloat = 0.0120                // 13
    static let filmGap: CGFloat = 0.0111               // 12
    static let film: CGFloat = 0.0241                  // 26
    static let creditTop: CGFloat = 0.0148             // 16
    static let credit: CGFloat = 0.0194                // 21
    static let ruleTop: CGFloat = 0.0241               // 26
    static let ruleBottom: CGFloat = 0.00185           // 2
    static let columnGap: CGFloat = 0.0519             // 56
    static let label: CGFloat = 0.0194                 // 21
    static let value: CGFloat = 0.0222                 // 24
    static let rowPadding: CGFloat = 0.0111            // 12
    static let footerText: CGFloat = 0.025             // 27
    static let footerGap: CGFloat = 0.0130             // 14
    static let footerTop: CGFloat = 0.0185             // breathing room above the sign-off
    static let gradient: CGFloat = 0.1667              // 180

    static var rowHeight: CGFloat { value + 2 * rowPadding }

    /// The paper block's height — the photograph gets whatever is left.
    static func paperHeight(rows: Int, nameLines: Int, showsCredit: Bool) -> CGFloat {
        paperTop
            + CGFloat(nameLines) * name * nameLineHeight
            + (showsCredit ? creditTop + credit : 0)
            + ruleTop + ruleBottom
            + filmTop + film
            + CGFloat(rows) * rowHeight
            + footerTop + footerText
            + paperBottom
    }
}

enum SpecimenSpec {
    static let margin: CGFloat = 0.0519                // 56
    static let headerWordmark: CGFloat = 0.0231        // 25
    static let headerText: CGFloat = 0.0167            // 18
    static let headerGap: CGFloat = 0.0102             // 11
    static let headerBottom: CGFloat = 0.0241          // 26
    static let nameTop: CGFloat = 0.0315               // 34
    static let name: CGFloat = 0.0574                  // 62
    static let nameLineHeight: CGFloat = 1.0
    static let nameTracking: CGFloat = -0.015
    static let filmTop: CGFloat = 0.0148               // 16
    static let swatch: CGFloat = 0.0102                // 11
    static let filmGap: CGFloat = 0.0102               // 11
    static let film: CGFloat = 0.0194                  // 21
    static let creditTop: CGFloat = 0.0139             // 15
    static let credit: CGFloat = 0.0167                // 18
    static let ruleTop: CGFloat = 0.0278               // 30
    static let columnGap: CGFloat = 0.0407             // 44
    static let label: CGFloat = 0.0167                 // 18
    static let value: CGFloat = 0.0185                 // 20
    static let rowPadding: CGFloat = 0.0102            // 11

    static var rowHeight: CGFloat { value + 2 * rowPadding }
    static var headerHeight: CGFloat { max(headerWordmark, headerText) + headerBottom }
    static var filmRowHeight: CGFloat { film }

    /// Everything on the page except the photograph, which gets the remainder.
    static func typeHeight(rows: Int, nameLines: Int, showsCredit: Bool) -> CGFloat {
        headerHeight
            + nameTop + CGFloat(nameLines) * name * nameLineHeight
            + (showsCredit ? creditTop + credit : 0)
            + ruleTop
            + filmTop + filmRowHeight
            + CGFloat(rows) * rowHeight
    }
}

/// Design 2a, drawn at 1080 × 1350. The grid values double as the frame's plan (`framePlan`), so
/// the mat the frame draws and the windows the card leaves open are one set of numbers.
enum QuarterGridSpec {
    // The grid — 44 all round except 24 at the foot, 24 between cells, 18 on every window corner.
    static let border: CGFloat = 0.0407                // 44
    static let gap: CGFloat = 0.0222                   // 24
    static let radius: CGFloat = 0.01667               // 18
    static let bottomInset: CGFloat = 0.0222           // 24

    // The text cell's own padding: 6 above, 20 on the trailing edge, 4 on the leading, none below.
    static let padTop: CGFloat = 0.00556               // 6
    static let padLeading: CGFloat = 0.0037            // 4
    static let padTrailing: CGFloat = 0.0185           // 20

    static let name: CGFloat = 0.0481                  // 52
    static let nameLineHeight: CGFloat = 1.04
    static let nameTracking: CGFloat = -0.0096         // −0.5 at 52
    static let creditTop: CGFloat = 0.00926            // 10
    static let credit: CGFloat = 0.0222                // 24
    static let creditLineHeight: CGFloat = 1.35
    static let filmTop: CGFloat = 0.0222               // 24
    static let swatch: CGFloat = 0.0241                // 26
    static let filmGap: CGFloat = 0.00926              // 10
    static let film: CGFloat = 0.0259                  // 28
    static let filmLineHeight: CGFloat = 1.2
    static let listTop: CGFloat = 0.0167               // 18
    static let row: CGFloat = 0.0213                   // 23
    static let rowLineHeight: CGFloat = 1.4
    static let rowGap: CGFloat = 0.00185               // 2
    static let rowValueGap: CGFloat = 0.0111           // 12

    // The sign-off: 20 under the grid, a 27 lockup and a 19 caps tag on one baseline, 6 beneath.
    static let gridToFooter: CGFloat = 0.0185          // 20
    static let footerSerif: CGFloat = 0.025            // 27
    static let footerLineHeight: CGFloat = 1.2
    static let footerCaps: CGFloat = 0.0176            // 19
    static let footerCapsTracking: CGFloat = 0.1       // 1.9 at 19
    static let footerGap: CGFloat = 0.00926            // 10
    static let footerPad: CGFloat = 0.00556            // 6

    /// The block may shrink this far to fit its cell before the style is refused instead. At 0.8
    /// the rows are the size of the Specimen card's labels, which the design set that small on
    /// purpose; further and the list stops being readable on a phone.
    static let minTextScale: CGFloat = 0.8

    /// The widest a window may be for its height. The design's cells are upright; on a 1.91:1
    /// canvas they come out as letterboxes with the type shrunk beside them, which is a different
    /// card and not a good one, so that shape is refused rather than served.
    static let maxWindowAspect: CGFloat = 1.5

    /// What the foot needs beyond the mat: the frame's border already covers 44 of the 82 between
    /// the grid and the canvas edge, and this is the rest — the band the frame holds back.
    static var footerBand: CGFloat {
        gridToFooter + footerSerif * footerLineHeight + footerPad + bottomInset - border
    }

    static var filmRowHeight: CGFloat { max(swatch, film * filmLineHeight) }

    /// The text cell less its padding, on whole pixels so the type is rasterised crisp.
    static func textFrame(in cell: CGRect, unit: CGFloat) -> CGRect {
        let left = (cell.minX + padLeading * unit).rounded()
        let top = (cell.minY + padTop * unit).rounded()
        let right = (cell.maxX - padTrailing * unit).rounded()
        return CGRect(x: left, y: top, width: right - left, height: cell.maxY.rounded() - top)
    }

    /// The block's height as drawn at scale 1, in design fractions.
    static func textHeight(rows: Int, nameLines: Int, showsCredit: Bool, showsFilm: Bool) -> CGFloat {
        CGFloat(nameLines) * name * nameLineHeight
            + (showsCredit ? creditTop + credit * creditLineHeight : 0)
            + (showsFilm ? filmTop + filmRowHeight : 0)
            + (rows > 0 ? listTop + CGFloat(rows) * row * rowLineHeight + CGFloat(rows - 1) * rowGap : 0)
    }
}

// MARK: - Resolution

extension ShareCardStyle {

    /// Smallest share of the canvas a photograph may be reduced to before the card stops being a
    /// photo card. Below this the style is refused rather than shipped as a stamp on a strip.
    private static let minimumPhotoShare: CGFloat = 0.30

    /// Resolve this style against a canvas.
    ///
    /// Returns nil when the card can't hold the recipe at that shape — a Story foot needs six rows
    /// of ledger and a two-line name, which on a 1.91:1 banner would leave nothing to look at. The
    /// caller offers the style with the reason rather than shipping a broken card.
    func metrics(canvas: CGSize, content: ShareCardContent) -> ShareCardMetrics? {
        guard canvas.width > 0, canvas.height > 0 else { return nil }
        let unit = min(canvas.width, canvas.height)
        let lines = max(1, content.lines.count)
        let showsCredit = content.creditLine != nil

        func resolved(photoFrame: CGRect, columns: Int, nameLines: Int,
                      photoFrames: [CGRect]? = nil, textFrame: CGRect = .zero,
                      textScale: CGFloat = 1) -> ShareCardMetrics {
            ShareCardMetrics(style: self, canvas: canvas, unit: unit,
                             photoFrame: photoFrame, ledgerColumns: columns, nameLines: nameLines,
                             photoFrames: photoFrames ?? [photoFrame], textFrame: textFrame,
                             textScale: textScale)
        }

        /// How many lines the name takes at a given size and width — the same call `CardTitle` makes
        /// to break it, so fitting a card and drawing it can't disagree.
        func nameLines(size: CGFloat, tracking: CGFloat, width: CGFloat) -> Int {
            max(1, CardTextLayout.lines(content.name,
                                        font: CardFont.recipeName(size: size).uiFont,
                                        tracking: tracking * size,
                                        maxWidth: width,
                                        limit: 2).count)
        }

        switch self {
        case .plain:
            // A corner block on a full-bleed photograph adapts to anything; it only has to fit.
            let blockWidth = canvas.width - 2 * PlainSpec.inset * unit
            let names = nameLines(size: PlainSpec.name * unit,
                                  tracking: PlainSpec.nameTracking, width: blockWidth)
            let available = canvas.height - 2 * PlainSpec.inset * unit
            let plainLines = max(1, content.linesWithFilmSimulation.count)
            guard PlainSpec.blockHeight(lines: plainLines, nameLines: names,
                                        showsCredit: showsCredit) * unit <= available else { return nil }
            return resolved(photoFrame: CGRect(origin: .zero, size: canvas), columns: 1, nameLines: names)

        case .story:
            let contentWidth = canvas.width - 2 * StorySpec.side * unit
            let names = nameLines(size: StorySpec.name * unit, tracking: -0.015, width: contentWidth)
            guard let columns = columnCount(
                lines: content.lines,
                contentWidth: contentWidth,
                columnGap: StorySpec.columnGap * unit,
                unit: unit,
                labelSize: StorySpec.label * unit,
                valueSize: StorySpec.value * unit,
                fits: { rows in
                    StorySpec.footHeight(rows: rows, nameLines: names,
                                         showsCredit: showsCredit) * unit
                        <= StorySpec.footBudget * canvas.height
                }
            ) else { return nil }
            return resolved(photoFrame: CGRect(origin: .zero, size: canvas),
                            columns: columns, nameLines: names)

        case .feed:
            let contentWidth = canvas.width - 2 * FeedSpec.side * unit
            let names = nameLines(size: FeedSpec.name * unit,
                                  tracking: FeedSpec.nameTracking, width: contentWidth)
            guard let columns = columnCount(
                lines: content.lines,
                contentWidth: contentWidth,
                columnGap: FeedSpec.columnGap * unit,
                unit: unit,
                labelSize: FeedSpec.label * unit,
                valueSize: FeedSpec.value * unit,
                fits: { rows in
                    let paper = FeedSpec.paperHeight(rows: rows, nameLines: names,
                                                     showsCredit: showsCredit) * unit
                    return canvas.height - paper >= Self.minimumPhotoShare * canvas.height
                }
            ) else { return nil }
            let rows = rowCount(lines: lines, columns: columns)
            let paper = FeedSpec.paperHeight(rows: rows, nameLines: names,
                                             showsCredit: showsCredit) * unit
            let photo = CGRect(x: 0, y: 0, width: canvas.width, height: (canvas.height - paper).rounded())
            return resolved(photoFrame: photo, columns: columns, nameLines: names)

        case .specimen:
            let margin = SpecimenSpec.margin * unit
            let contentWidth = canvas.width - 2 * margin
            let contentHeight = canvas.height - 2 * margin
            let names = nameLines(size: SpecimenSpec.name * unit,
                                  tracking: SpecimenSpec.nameTracking, width: contentWidth)
            guard let columns = columnCount(
                lines: content.lines,
                contentWidth: contentWidth,
                columnGap: SpecimenSpec.columnGap * unit,
                unit: unit,
                labelSize: SpecimenSpec.label * unit,
                valueSize: SpecimenSpec.value * unit,
                fits: { rows in
                    let type = SpecimenSpec.typeHeight(rows: rows, nameLines: names,
                                                       showsCredit: showsCredit) * unit
                    return contentHeight - type >= Self.minimumPhotoShare * canvas.height
                }
            ) else { return nil }
            let rows = rowCount(lines: lines, columns: columns)
            let type = SpecimenSpec.typeHeight(rows: rows, nameLines: names,
                                               showsCredit: showsCredit) * unit
            let photoHeight = (contentHeight - type).rounded()
            let photo = CGRect(x: margin,
                               y: margin + SpecimenSpec.headerHeight * unit,
                               width: contentWidth,
                               height: photoHeight)
            return resolved(photoFrame: photo, columns: columns, nameLines: names)

        case .quarterGrid:
            // The grid is laid out here with the frame's own arithmetic — the same rounding of the
            // mat, the gutter and the cell edges `FrameRenderer.layout` does — so the windows the
            // paper leaves open are the openings the photographs are clipped to. Once a real layout
            // exists `ShareCardRenderer.metrics` swaps its openings in regardless.
            let borderPx = (QuarterGridSpec.border * unit).rounded()
            let gapPx = (QuarterGridSpec.gap * unit).rounded()
            let bandPx = (QuarterGridSpec.footerBand * unit).rounded()
            let cell = CGSize(width: (canvas.width - 2 * borderPx - gapPx) / 2,
                              height: (canvas.height - 2 * borderPx - bandPx - gapPx) / 2)
            guard cell.width >= 1, cell.height >= 1,
                  cell.width / cell.height <= QuarterGridSpec.maxWindowAspect else { return nil }
            func cellRect(_ position: Int) -> CGRect {
                let left = borderPx + CGFloat(position % 2) * (cell.width + gapPx)
                let top = borderPx + CGFloat(position / 2) * (cell.height + gapPx)
                return CGRect(x: left.rounded(), y: top.rounded(),
                              width: (left + cell.width).rounded() - left.rounded(),
                              height: (top + cell.height).rounded() - top.rounded())
            }
            let windows = (1...3).map(cellRect)
            let textFrame = QuarterGridSpec.textFrame(in: cellRect(0), unit: unit)
            guard textFrame.width > 0, textFrame.height > 0 else { return nil }

            // Fit the block to its cell: measure it as drawn, and when the cell is too short shrink
            // everything by one factor. Past the floor the style is refused, like any other.
            let rows = content.lines.count
            let showsFilm = content.filmSimulationName != nil
            func measured(scale: CGFloat) -> (height: CGFloat, nameLines: Int) {
                let names = nameLines(size: QuarterGridSpec.name * unit * scale,
                                      tracking: QuarterGridSpec.nameTracking, width: textFrame.width)
                let height = QuarterGridSpec.textHeight(rows: rows, nameLines: names,
                                                        showsCredit: showsCredit,
                                                        showsFilm: showsFilm) * unit * scale
                return (height, names)
            }
            var scale: CGFloat = 1
            var fit = measured(scale: 1)
            if fit.height > textFrame.height {
                scale = textFrame.height / fit.height
                // A smaller name may break to fewer lines, so measure once more at the new size.
                fit = measured(scale: scale)
                if fit.height > textFrame.height {
                    scale *= textFrame.height / fit.height
                    fit = measured(scale: scale)
                }
            }
            guard scale >= QuarterGridSpec.minTextScale else { return nil }
            let union = windows.dropFirst().reduce(windows[0]) { $0.union($1) }
            return resolved(photoFrame: union, columns: 1, nameLines: fit.nameLines,
                            photoFrames: windows, textFrame: textFrame, textScale: scale)
        }
    }

    /// `metrics` with its windows replaced by the frame's real openings, for a style with a plan.
    /// The card's own copy of the grid arithmetic follows the frame's, but the mat is a fraction of
    /// the tile and the footer band a fraction of the canvas, and a rounding pixel between the two
    /// would show as a hairline of background along a window's edge.
    func snapping(_ metrics: ShareCardMetrics, to openings: [CGRect]) -> ShareCardMetrics {
        guard self == .quarterGrid, openings.count >= 3 else { return metrics }
        let windows = Array(openings.prefix(3))
        // The text cell is the grid position the photographs skipped: it shares a column with the
        // bottom-left window and a row with the top-right one.
        let cell = CGRect(x: windows[1].minX, y: windows[0].minY,
                          width: windows[1].width, height: windows[0].height)
        return metrics.with(photoFrames: windows,
                            textFrame: QuarterGridSpec.textFrame(in: cell, unit: metrics.unit))
    }

    /// Rows in the tallest column, when `lines` are dealt into `columns` filling the first column
    /// before the next.
    func rowCount(lines: Int, columns: Int) -> Int {
        guard columns > 1 else { return lines }
        return Int((Double(lines) / Double(columns)).rounded(.up))
    }

    /// Pick a column count: the fewest that make the block fit, never below the design's own choice,
    /// and never so many that a label and its value stop fitting side by side.
    ///
    /// Going wider is what buys a short canvas its layout back — the same eleven parameters as three
    /// rows of four read fine on a banner where six rows of two would bury the photograph. Measuring
    /// the real strings rather than guessing a minimum width is what keeps that honest: "Noise
    /// Reduction" is a much wider label than "WB", and only the recipe on the card knows which of
    /// them it has.
    private func columnCount(lines: [ShareCardContent.Line],
                             contentWidth: CGFloat,
                             columnGap: CGFloat,
                             unit: CGFloat,
                             labelSize: CGFloat,
                             valueSize: CGFloat,
                             fits: (Int) -> Bool) -> Int? {
        guard contentWidth > 0, !lines.isEmpty else { return nil }

        let required = CardTextLayout.widestLedgerEntry(lines,
                                                        labelSize: labelSize,
                                                        valueSize: valueSize)
            + LedgerSpec.minLabelValueGap * unit
        let widest = max(required, 1)

        var viable: [Int] = []
        for columns in designColumns...ShareCardStyle.maxColumns {
            let width = (contentWidth - columnGap * CGFloat(columns - 1)) / CGFloat(columns)
            guard width >= widest else { break }
            viable.append(columns)
        }
        // The design's own column count is kept even when a label measures a hair too wide for it —
        // it was drawn that way, and refusing the native shape over a rounding error helps nobody.
        if viable.isEmpty { viable = [designColumns] }

        for columns in viable where fits(rowCount(lines: lines.count, columns: columns)) {
            return columns
        }
        return nil
    }
}
