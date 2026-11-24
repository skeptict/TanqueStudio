import Foundation
import CoreImage
import CoreImage.CIFilterBuiltins

// MARK: - .cube LUT
//
// Film Finish prototype, part 1 of 2 (see HalationFilter.swift for part 2).
//
// Parses Adobe/Resolve `.cube` 3D LUTs and applies them with
// CIColorCubeWithColorSpace. Two details matter:
//
// 1. Ordering. `.cube` lists entries red-fastest, then green, then blue —
//    the same order CIColorCube expects, so the parsed table goes straight
//    into `cubeData` with an alpha of 1 appended to each entry.
// 2. Colour space. LUTs are authored against gamma-encoded values (sRGB /
//    Rec.709), but Core Image's working space is linear. Passing sRGB as the
//    cube's colour space makes CI convert into sRGB before the lookup and back
//    out after, so the LUT sees the numbers it was built for.

nonisolated struct CubeLUT: Equatable, Sendable {
    var title: String?
    /// Edge length of the cube: 33 means 33×33×33 entries.
    var size: Int
    /// RGB triples in file order (red fastest), each component 0...1.
    var table: [SIMD3<Float>]

    /// Core Image's cube filter tops out at 128 per side; real LUTs are 17–65.
    static let maxSize = 128

    nonisolated enum ParseError: Error, Equatable, LocalizedError {
        case missingSize
        case oneDimensionalNotSupported
        case sizeOutOfRange(Int)
        case wrongEntryCount(expected: Int, found: Int)
        case badLine(number: Int, text: String)
        /// DOMAIN_MIN/MAX other than 0...1. Rare in practice (log-input LUTs);
        /// remapping would have to happen in the LUT's own encoded space, so
        /// the prototype refuses rather than grading wrongly.
        case unsupportedDomain

        var errorDescription: String? {
            switch self {
            case .missingSize: "No LUT_3D_SIZE line — this doesn't look like a 3D .cube file."
            case .oneDimensionalNotSupported: "This is a 1D LUT. Only 3D LUTs are supported."
            case .sizeOutOfRange(let n): "LUT_3D_SIZE \(n) is outside 2…\(CubeLUT.maxSize)."
            case .wrongEntryCount(let e, let f): "Expected \(e) entries, found \(f)."
            case .badLine(let n, let t): "Couldn't read line \(n): \(t)"
            case .unsupportedDomain: "This LUT uses an input domain other than 0–1, which isn't supported yet."
            }
        }
    }

    init(title: String? = nil, size: Int, table: [SIMD3<Float>]) {
        self.title = title
        self.size = size
        self.table = table
    }

    init(contentsOf url: URL) throws {
        try self.init(parsing: String(contentsOf: url, encoding: .utf8))
    }

    init(parsing text: String) throws {
        var title: String?
        var size: Int?
        var domainMin = SIMD3<Float>(0, 0, 0)
        var domainMax = SIMD3<Float>(1, 1, 1)
        var table: [SIMD3<Float>] = []

        for (index, rawLine) in text.split(omittingEmptySubsequences: false,
                                           whereSeparator: \.isNewline).enumerated() {
            var line = Substring(rawLine)
            if let hash = line.firstIndex(of: "#") { line = line[..<hash] }
            line = Substring(line.trimmingCharacters(in: .whitespaces))
            guard !line.isEmpty else { continue }

            let fields = line.split(whereSeparator: \.isWhitespace)
            let keyword = fields[0].uppercased()

            // Data lines start with a number (including "-0.0" or ".5").
            if let first = fields[0].first, first.isNumber || first == "-" || first == "." || first == "+" {
                let values = fields.compactMap { Float($0) }
                guard fields.count == 3, values.count == 3 else {
                    throw ParseError.badLine(number: index + 1, text: String(line))
                }
                table.append(SIMD3(values[0], values[1], values[2]))
                continue
            }

            switch keyword {
            case "TITLE":
                title = line.dropFirst("TITLE".count)
                    .trimmingCharacters(in: .whitespaces)
                    .trimmingCharacters(in: CharacterSet(charactersIn: "\""))
            case "LUT_3D_SIZE":
                guard fields.count == 2, let n = Int(fields[1]) else {
                    throw ParseError.badLine(number: index + 1, text: String(line))
                }
                size = n
            case "LUT_1D_SIZE":
                throw ParseError.oneDimensionalNotSupported
            case "DOMAIN_MIN", "DOMAIN_MAX":
                let v = fields.dropFirst().compactMap { Float($0) }
                guard v.count == 3 else { throw ParseError.badLine(number: index + 1, text: String(line)) }
                if keyword == "DOMAIN_MIN" { domainMin = SIMD3(v[0], v[1], v[2]) }
                else { domainMax = SIMD3(v[0], v[1], v[2]) }
            case "LUT_3D_INPUT_RANGE":   // Resolve's spelling of the domain
                let v = fields.dropFirst().compactMap { Float($0) }
                guard v.count == 2 else { throw ParseError.badLine(number: index + 1, text: String(line)) }
                domainMin = SIMD3(repeating: v[0]); domainMax = SIMD3(repeating: v[1])
            default:
                continue   // LUT_1D_INPUT_RANGE and vendor keywords: ignore
            }
        }

        guard let size else { throw ParseError.missingSize }
        guard (2...Self.maxSize).contains(size) else { throw ParseError.sizeOutOfRange(size) }
        guard domainMin == SIMD3(0, 0, 0), domainMax == SIMD3(1, 1, 1) else {
            throw ParseError.unsupportedDomain
        }
        let expected = size * size * size
        guard table.count == expected else {
            throw ParseError.wrongEntryCount(expected: expected, found: table.count)
        }
        self.init(title: title, size: size, table: table)
    }

    /// RGBA Float32 data in the layout CIColorCube wants.
    var cubeData: Data {
        var floats = [Float]()
        floats.reserveCapacity(table.count * 4)
        for entry in table {
            floats.append(entry.x); floats.append(entry.y); floats.append(entry.z); floats.append(1)
        }
        return floats.withUnsafeBufferPointer { Data(buffer: $0) }
    }

    /// Grade `image`. `strength` 0 returns the input, 1 the full LUT; between,
    /// a dissolve (done in CI's linear working space).
    func apply(to image: CIImage, strength: Float = 1,
               colorSpace: CGColorSpace = CGColorSpace(name: CGColorSpace.sRGB)!) -> CIImage {
        let clamped = max(0, min(1, strength))
        guard clamped > 0 else { return image }

        let cube = CIFilter.colorCubeWithColorSpace()
        cube.inputImage = image
        cube.cubeDimension = Float(size)
        cube.cubeData = cubeData
        cube.colorSpace = colorSpace
        guard let graded = cube.outputImage else { return image }
        guard clamped < 1 else { return graded }

        let mix = CIFilter.dissolveTransition()
        mix.inputImage = image
        mix.targetImage = graded
        mix.time = clamped
        return mix.outputImage ?? graded
    }

    /// The do-nothing LUT, handy for tests and as a neutral default.
    static func identity(size: Int = 2) -> CubeLUT {
        var table: [SIMD3<Float>] = []
        let d = Float(size - 1)
        for b in 0..<size { for g in 0..<size { for r in 0..<size {
            table.append(SIMD3(Float(r) / d, Float(g) / d, Float(b) / d))
        } } }
        return CubeLUT(title: "Identity", size: size, table: table)
    }
}
