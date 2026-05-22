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
        ("GB2312", stringEncoding(for: kCFStringEncodingGB_2312_80)),
        ("GBK", stringEncoding(for: kCFStringEncodingGBK_95)),
        ("GB18030", stringEncoding(for: kCFStringEncodingGB_18030_2000))
    ]

    private static func stringEncoding(for encoding: CFStringEncoding) -> String.Encoding {
        String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding(encoding))
    }
}
