import CoreFoundation
import Foundation

struct TXTTextDecoder {
    struct DecodedText: Equatable {
        var text: String
        var encodingName: String
    }

    enum DecodeError: LocalizedError {
        case unsupportedEncoding

        var errorDescription: String? {
            switch self {
            case .unsupportedEncoding:
                return NSLocalizedString("import.error.unsupportedEncoding", comment: "")
            }
        }
    }

    func decode(_ data: Data) throws -> DecodedText {
        if data.starts(with: Self.utf8BOM) {
            let textData = Data(data.dropFirst(Self.utf8BOM.count))
            guard let text = String(data: textData, encoding: .utf8) else {
                throw DecodeError.unsupportedEncoding
            }
            return DecodedText(text: text, encodingName: "UTF-8 BOM")
        }

        if let text = String(data: data, encoding: .utf8) {
            return DecodedText(text: text, encodingName: "UTF-8")
        }

        for candidate in Self.legacyChineseEncodings {
            if let text = String(data: data, encoding: candidate.encoding) {
                return DecodedText(
                    text: text,
                    encodingName: candidate.name
                )
            }
        }

        throw DecodeError.unsupportedEncoding
    }

    private static let utf8BOM = Data([0xEF, 0xBB, 0xBF])

    private static let legacyChineseEncodings: [(name: String, encoding: String.Encoding)] = [
        ("GB2312", stringEncoding(for: 0x0630)),
        ("GBK", stringEncoding(for: 0x0631)),
        ("GB18030", stringEncoding(for: 0x0632))
    ]

    private static func stringEncoding(for cfEncoding: UInt32) -> String.Encoding {
        let nsEncoding = CFStringConvertEncodingToNSStringEncoding(
            CFStringEncoding(cfEncoding)
        )
        return String.Encoding(rawValue: nsEncoding)
    }
}
