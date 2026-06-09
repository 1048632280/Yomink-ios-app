import Foundation

let targetBytes = 30 * 1024 * 1024
let scriptURL = URL(fileURLWithPath: CommandLine.arguments[0])
let outputURL = scriptURL
    .deletingLastPathComponent()
    .appendingPathComponent("large-30mb.generated.txt")

let paragraph = """
Chapter Stress Fixture

This generated file is used for ReaderV2 pagination and open-time stress testing.
The content is deterministic and ASCII-only so the byte size is exact and stable.
ReaderV2 should be able to import, index, paginate, scroll, and close this file without sustained CPU or memory growth.

"""

let paragraphData = Data(paragraph.utf8)
FileManager.default.createFile(atPath: outputURL.path, contents: nil)

let handle = try FileHandle(forWritingTo: outputURL)
defer {
    try? handle.close()
}

var writtenBytes = 0
while writtenBytes + paragraphData.count <= targetBytes {
    try handle.write(contentsOf: paragraphData)
    writtenBytes += paragraphData.count
}

let remainingBytes = targetBytes - writtenBytes
if remainingBytes > 0 {
    try handle.write(contentsOf: Data(repeating: 120, count: remainingBytes))
}

print("Generated \(outputURL.path) (\(targetBytes) bytes)")
