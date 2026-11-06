import Foundation

/// Byte order of a TIFF-structured block. A file's Exif block declares its own; the Fujifilm
/// MakerNote nested inside it is always little-endian regardless (see `FujiMakerNote`).
enum ByteOrder {
    case little
    case big
}

// MARK: - ByteView

/// A bounds-checked, endianness-aware window onto a byte buffer.
///
/// Every accessor assembles its result from individually bounds-checked bytes and returns `nil`
/// rather than trapping. That is deliberate and not negotiable: these bytes come from a file the
/// user picked, so a malformed — or hostile — offset has to produce a message, never a crash.
/// No `withUnsafeBytes`, no `loadUnaligned`, no force unwraps, no arithmetic that can overflow.
/// The per-byte cost is irrelevant here: a Fujifilm MakerNote is on the order of a hundred entries.
struct ByteView {
    let data: Data
    let order: ByteOrder

    init(_ data: Data, order: ByteOrder = .little) {
        self.data = data
        self.order = order
    }

    /// Length of the buffer. Offsets passed to the accessors are relative to its start.
    var count: Int { data.count }

    /// The same bytes read in the other order, for a nested block that fixes its own endianness.
    func reordered(_ order: ByteOrder) -> ByteView { ByteView(data, order: order) }

    // MARK: Primitives

    /// `data.startIndex + offset` is load-bearing. A `Data` slice keeps its parent's indices, so a
    /// view built over `data[100...]` would trap on `data[0]` even though `count` says it's in
    /// range. `Data.readLE(_:at:)` in `FujiPTP.swift` already carries this rule; the whole of this
    /// file follows it by never slicing — regions are `(base, length)` pairs over the whole file.
    func byte(_ offset: Int) -> UInt8? {
        guard offset >= 0, offset < data.count else { return nil }
        return data[data.startIndex + offset]
    }

    func u8(at offset: Int) -> UInt8? { byte(offset) }

    func u16(at offset: Int) -> UInt16? {
        guard let a = byte(offset), let b = byte(offset + 1) else { return nil }
        return order == .little ? UInt16(a) | UInt16(b) << 8
                                : UInt16(a) << 8 | UInt16(b)
    }

    func u32(at offset: Int) -> UInt32? {
        guard let a = byte(offset), let b = byte(offset + 1),
              let c = byte(offset + 2), let d = byte(offset + 3) else { return nil }
        return order == .little
            ? UInt32(a) | UInt32(b) << 8 | UInt32(c) << 16 | UInt32(d) << 24
            : UInt32(a) << 24 | UInt32(b) << 16 | UInt32(c) << 8 | UInt32(d)
    }

    /// Signed reads reinterpret the unsigned bits. `Int8(bitPattern:)` rather than `Int8(_:)`
    /// matters: MakerNote 0x1049 (Monochromatic Color WC) is signed 8-bit, and a cool value of −4
    /// arrives as 0xFC — which `Int8(_:)` would refuse.
    func i8(at offset: Int) -> Int8? { u8(at: offset).map(Int8.init(bitPattern:)) }
    func i16(at offset: Int) -> Int16? { u16(at: offset).map(Int16.init(bitPattern:)) }
    func i32(at offset: Int) -> Int32? { u32(at: offset).map(Int32.init(bitPattern:)) }

    /// NUL-terminated ASCII, trimmed. Returns nil only if the very first byte is out of bounds,
    /// so a string running off the end of the file still yields what was readable.
    func ascii(at offset: Int, count: Int) -> String? {
        guard count > 0, byte(offset) != nil else { return nil }
        var bytes: [UInt8] = []
        bytes.reserveCapacity(min(count, 256))
        for index in 0..<count {
            guard let value = byte(offset + index) else { break }
            if value == 0 { break }
            bytes.append(value)
        }
        let text = String(decoding: bytes, as: UTF8.self)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? nil : text
    }

    func matches(_ signature: [UInt8], at offset: Int) -> Bool {
        for (index, expected) in signature.enumerated() {
            guard byte(offset + index) == expected else { return false }
        }
        return true
    }
}

// MARK: - TIFF structure

/// The TIFF component types. 1…12 are the only values a well-formed IFD entry may declare;
/// `TIFFBlock.ifd(at:hasNextPointer:)` refuses a directory holding any other.
enum TIFFType: UInt16 {
    case byte = 1
    case ascii = 2
    case short = 3
    case long = 4
    case rational = 5
    case sbyte = 6
    case undefined = 7
    case sshort = 8
    case slong = 9
    case srational = 10
    case float = 11
    case double = 12

    var byteWidth: Int {
        switch self {
        case .byte, .ascii, .sbyte, .undefined: return 1
        case .short, .sshort: return 2
        case .long, .slong, .float: return 4
        case .rational, .srational, .double: return 8
        }
    }

    /// Short label for the diagnostics dump, in ExifTool's spelling so the two can be read
    /// side by side during verification.
    var debugName: String {
        switch self {
        case .byte: return "int8u"
        case .ascii: return "string"
        case .short: return "int16u"
        case .long: return "int32u"
        case .rational: return "rational"
        case .sbyte: return "int8s"
        case .undefined: return "undef"
        case .sshort: return "int16s"
        case .slong: return "int32s"
        case .srational: return "srational"
        case .float: return "float"
        case .double: return "double"
        }
    }
}

/// One 12-byte IFD entry, already validated as far as its own header goes.
struct TIFFEntry {
    let tag: UInt16
    let type: TIFFType
    let count: Int
    /// The raw 4-byte value field. Only an offset when the value is too big to sit inline.
    let valueOffset: UInt32
    /// Where the entry itself begins, so the inline case can read out of its own bytes.
    let entryOffset: Int
}

/// A TIFF-structured region: where it starts in the file, and how its bytes are ordered.
///
/// Every offset inside an IFD entry is relative to `base`, which is the one thing that differs
/// between the file's Exif block and the Fujifilm MakerNote nested in it. That is why one type
/// serves both — the walker never needs to know which it is looking at.
struct TIFFBlock {
    /// Always the whole file. Never a slice: see `ByteView.byte(_:)`.
    let view: ByteView
    /// Offset of this block's first byte within the file.
    let base: Int
    /// Exclusive end of the declared TIFF or MakerNote region, not the containing JPEG.
    let end: Int
    /// Offset of the first IFD, relative to `base`.
    let ifd0Offset: Int

    /// A directory with more entries than this is not a real one. Bounded so a corrupt count can't
    /// make us allocate.
    private static let maxEntries = 4096

    // MARK: Walking

    func ifd(at relativeOffset: Int, hasNextPointer: Bool = true) throws -> [TIFFEntry] {
        guard base >= 0, end <= view.count, end >= base,
              relativeOffset >= 0, relativeOffset <= end - base - 2 else {
            throw ExifError.malformedTIFF
        }
        let start = base + relativeOffset
        guard start >= 0, let declared = view.u16(at: start) else { throw ExifError.malformedTIFF }
        let entryCount = Int(declared)
        guard entryCount <= Self.maxEntries,
              start <= end - 2 - 12 * entryCount - (hasNextPointer ? 4 : 0) else {
            throw ExifError.malformedTIFF
        }

        var entries: [TIFFEntry] = []
        entries.reserveCapacity(entryCount)
        for index in 0..<entryCount {
            let offset = start + 2 + 12 * index
            guard let tag = view.u16(at: offset),
                  let rawType = view.u16(at: offset + 2),
                  let components = view.u32(at: offset + 4),
                  let value = view.u32(at: offset + 8) else { throw ExifError.malformedTIFF }
            guard let type = TIFFType(rawValue: rawType) else { throw ExifError.malformedTIFF }
            entries.append(TIFFEntry(tag: tag, type: type, count: Int(components),
                                     valueOffset: value, entryOffset: offset))
        }
        return entries
    }

    /// Where an entry's value actually lives — the 4-byte inline rule.
    func valueRange(of entry: TIFFEntry) throws -> Range<Int> {
        // Int64 so a crafted component count cannot overflow the multiply on any architecture.
        let size64 = Int64(entry.type.byteWidth) * Int64(entry.count)
        guard size64 > 0, size64 <= Int64(end - base) else { throw ExifError.malformedTIFF }
        let size = Int(size64)
        // Four bytes or fewer sit in the entry's own value field; anything larger is stored
        // elsewhere, at an offset relative to this block's base.
        let start = size <= 4 ? entry.entryOffset + 8 : base + Int(entry.valueOffset)
        guard start >= base, start <= end - size else { throw ExifError.malformedTIFF }
        return start..<(start + size)
    }

    // MARK: Component readers

    /// The entry's components as `Int`s, sign-corrected for its declared type. Capped, because a
    /// recipe tag never has more than a handful and we have no use for a thousand-element array.
    func ints(_ entry: TIFFEntry, max limit: Int = 8) -> [Int] {
        guard let range = try? valueRange(of: entry) else { return [] }
        let width = entry.type.byteWidth
        var values: [Int] = []
        for index in 0..<Swift.min(entry.count, limit) {
            let at = range.lowerBound + index * width
            let value: Int?
            switch entry.type {
            case .byte, .undefined, .ascii: value = view.u8(at: at).map(Int.init)
            case .sbyte: value = view.i8(at: at).map(Int.init)
            case .short: value = view.u16(at: at).map(Int.init)
            case .sshort: value = view.i16(at: at).map(Int.init)
            case .long: value = view.u32(at: at).map(Int.init)
            case .slong: value = view.i32(at: at).map(Int.init)
            case .rational:
                if let n = view.u32(at: at), let d = view.u32(at: at + 4), d != 0 {
                    value = Int(n) / Int(d)
                } else { value = nil }
            case .srational:
                if let n = view.i32(at: at), let d = view.i32(at: at + 4), d != 0 {
                    value = Int(n) / Int(d)
                } else { value = nil }
            case .float, .double: value = nil
            }
            guard let value else { break }
            values.append(value)
        }
        return values
    }

    /// The first component, which is all any recipe tag but the white-balance shift needs.
    func int(_ entry: TIFFEntry) -> Int? { ints(entry, max: 1).first }

    func string(_ entry: TIFFEntry) -> String? {
        guard let range = try? valueRange(of: entry) else { return nil }
        return view.ascii(at: range.lowerBound, count: range.count)
    }
}

// MARK: - What the bytes actually are

/// What a file looks like from its first few bytes, so a refusal can name the format rather than
/// saying "not a JPEG" about a HEIF the camera legitimately wrote.
enum FileKind: String, Equatable {
    case jpeg, heif, png, tiff, gif, webp, raf, unknown

    var displayName: String {
        switch self {
        case .jpeg: return "JPEG"
        case .heif: return "HEIF"
        case .png: return "PNG"
        case .tiff: return "TIFF"
        case .gif: return "GIF"
        case .webp: return "WebP"
        case .raf: return "Fujifilm RAW"
        case .unknown: return "file of an unrecognised kind"
        }
    }

    static func detect(_ data: Data) -> FileKind {
        let view = ByteView(data, order: .big)
        if view.u16(at: 0) == 0xFFD8 { return .jpeg }
        // Raw bytes, not a string literal: "\u{89}" in a Swift string UTF-8-encodes to the two
        // bytes 0xC2 0x89 (U+0089 is outside ASCII), not the single 0x89 byte PNG's real signature
        // uses — that mismatch would make this check silently never match a real PNG.
        if view.matches([0x89, 0x50, 0x4E, 0x47], at: 0) { return .png }
        if view.matches(Array("GIF8".utf8), at: 0) { return .gif }
        if view.matches(Array("FUJIFILMCCD-RAW".utf8), at: 0) { return .raf }
        if view.matches(Array("RIFF".utf8), at: 0), view.matches(Array("WEBP".utf8), at: 8) { return .webp }
        if view.matches(Array("ftyp".utf8), at: 4) { return .heif }
        // "II*\0" / "MM\0*" — a bare TIFF, which includes most RAW containers.
        if view.matches([0x49, 0x49, 0x2A, 0x00], at: 0) || view.matches([0x4D, 0x4D, 0x00, 0x2A], at: 0) {
            return .tiff
        }
        return .unknown
    }
}

// MARK: - Errors

/// Everything that can stop a read, each specific enough for the screen to say what to do next.
///
/// Note what is *not* here: a Fujifilm MakerNote that parses but carries no recipe tags. That is a
/// successful read with an empty recipe and a warning, so camera and exposure still render.
enum ExifError: LocalizedError, Equatable {
    case notAJPEG(kind: FileKind)
    /// The file could not be opened at all, so nothing about its contents is known.
    case unreadable
    case malformedJPEG
    case noExif
    case noMakerNote
    case notFujifilm(signature: String?, make: String?)
    case malformedTIFF
    case malformedMakerNote

    var errorDescription: String? {
        switch self {
        case .notAJPEG(let kind):
            return "This is a \(kind.displayName), and Read Recipe can only open JPEGs."
        case .unreadable:
            return "This file couldn't be opened."
        case .malformedJPEG:
            return "This file is damaged, or was only partly copied."
        case .noExif:
            return "There's no EXIF in this file at all."
        case .noMakerNote:
            return "The Fujifilm section, where the recipe lives, has been removed from this file."
        case .notFujifilm(_, let make):
            if let make { return "This was shot on a \(make), not a Fujifilm camera." }
            return "This photo has no Fujifilm recipe data in it."
        case .malformedTIFF, .malformedMakerNote:
            return "The metadata in this file isn't in a shape this app knows."
        }
    }
}

// MARK: - ExifParser

/// The format layer: find the Exif block in a JPEG, walk its directories, and hand back where the
/// vendor MakerNote sits. Knows nothing about Fujifilm and nothing about recipes.
enum ExifParser {
    /// The six bytes that distinguish an Exif APP1 from an XMP one. Fuji JPEGs carry both, so
    /// checking the marker alone would hand back an XML packet and call it TIFF.
    static let exifSignature: [UInt8] = Array("Exif\u{0}\u{0}".utf8)

    /// Belt-and-braces cap. The length check below already guarantees termination.
    private static let maxSegments = 1024

    private enum Tag {
        static let make: UInt16 = 0x010F
        static let model: UInt16 = 0x0110
        static let exifIFDPointer: UInt16 = 0x8769
        static let makerNote: UInt16 = 0x927C
    }

    // MARK: Container

    /// Walk the JPEG's segments to the Exif APP1 and return the TIFF block inside it.
    static func exifBlock(inJPEG data: Data) throws -> TIFFBlock {
        // Segment lengths are big-endian whatever the TIFF inside later declares.
        let scan = ByteView(data, order: .big)
        guard scan.count >= 4, scan.u16(at: 0) == 0xFFD8 else {
            throw ExifError.notAJPEG(kind: FileKind.detect(data))
        }

        var position = 2
        var segments = 0
        var found: TIFFBlock?
        while position + 2 <= scan.count, segments < maxSegments {
            guard scan.byte(position) == 0xFF else { throw ExifError.malformedJPEG }
            // Any number of 0xFF fill bytes may precede a marker.
            while scan.byte(position) == 0xFF { position += 1 }
            guard let marker = scan.byte(position) else { throw ExifError.malformedJPEG }
            segments += 1

            // TEM, the restart markers and a stray SOI carry no length field.
            if marker == 0x01 || (0xD0...0xD8).contains(marker) {
                position += 1
                continue
            }
            // Start of scan, or end of image. Exif is always ahead of the compressed data, so
            // there is nothing left to look at.
            if marker == 0xDA || marker == 0xD9 { break }

            // `length >= 2` is what guarantees `position` strictly increases, and so that this
            // loop terminates on any input at all.
            guard let length = scan.u16(at: position + 1), length >= 2 else {
                throw ExifError.malformedJPEG
            }
            let payloadStart = position + 3
            let payloadEnd = position + 1 + Int(length)
            guard payloadEnd <= scan.count else { throw ExifError.malformedJPEG }

            if marker == 0xE1, scan.matches(exifSignature, at: payloadStart) {
                guard found == nil else { throw ExifError.malformedTIFF }
                found = try tiffBlock(in: data, at: payloadStart + exifSignature.count, end: payloadEnd)
            }
            position = payloadEnd
        }
        guard segments < maxSegments else { throw ExifError.malformedJPEG }
        guard let found else { throw ExifError.noExif }
        return found
    }

    /// Read a TIFF header at `base` and return the block it describes.
    private static func tiffBlock(in data: Data, at base: Int, end: Int) throws -> TIFFBlock {
        guard base >= 0, end <= data.count, base <= end - 8 else { throw ExifError.malformedTIFF }
        let probe = ByteView(data, order: .big)
        let order: ByteOrder
        switch probe.u16(at: base) {
        case 0x4949: order = .little     // "II"
        case 0x4D4D: order = .big        // "MM"
        default: throw ExifError.malformedTIFF
        }
        let view = ByteView(data, order: order)
        guard view.u16(at: base + 2) == 42, let ifd0 = view.u32(at: base + 4), ifd0 >= 8 else {
            throw ExifError.malformedTIFF
        }
        return TIFFBlock(view: view, base: base, end: end, ifd0Offset: Int(ifd0))
    }

    // MARK: Directories

    /// IFD0 → 0x8769 → the Exif IFD → 0x927C. Deliberately does *not* follow IFD0's next-IFD
    /// pointer to the thumbnail directory: nothing we want is in there, and walking it is free
    /// surface area on untrusted input.
    static func makerNoteRange(in block: TIFFBlock) throws -> Range<Int> {
        let ifd0 = try block.ifd(at: block.ifd0Offset)
        let pointers = ifd0.filter { $0.tag == Tag.exifIFDPointer }
        guard !pointers.isEmpty else { throw ExifError.noMakerNote }
        guard pointers.count == 1, let pointer = pointers.first,
              pointer.type == .long, pointer.count == 1,
              let exifOffset = block.int(pointer), exifOffset >= 8,
              exifOffset != block.ifd0Offset else { throw ExifError.malformedTIFF }
        let exifIFD = try block.ifd(at: exifOffset)
        let notes = exifIFD.filter { $0.tag == Tag.makerNote }
        guard !notes.isEmpty else { throw ExifError.noMakerNote }
        guard notes.count == 1, let makerNote = notes.first,
              makerNote.type == .undefined else { throw ExifError.malformedTIFF }
        return try block.valueRange(of: makerNote)
    }

    /// The camera manufacturer, for the "this isn't a Fujifilm photo" message. Best-effort:
    /// a file with no IFD0 simply has no maker to name.
    static func make(in block: TIFFBlock) -> String? {
        guard let ifd0 = try? block.ifd(at: block.ifd0Offset),
              ifd0.filter({ $0.tag == Tag.make }).count == 1,
              let entry = ifd0.first(where: { $0.tag == Tag.make }), entry.type == .ascii else { return nil }
        return block.string(entry)
    }

    /// The camera body, used to resolve a `CameraModel` when the MakerNote doesn't name one.
    static func model(in block: TIFFBlock) -> String? {
        guard let ifd0 = try? block.ifd(at: block.ifd0Offset),
              ifd0.filter({ $0.tag == Tag.model }).count == 1,
              let entry = ifd0.first(where: { $0.tag == Tag.model }), entry.type == .ascii else { return nil }
        return block.string(entry)
    }
}
