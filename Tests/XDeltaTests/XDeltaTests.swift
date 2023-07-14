import XCTest
@testable import XDelta

final class XDeltaTests: XCTestCase {
    func testXDelta() throws {
        // demo patch:
        /*
         head -n 5000 /usr/share/dict/words > OLD_FILE
         tail -n 5000 /usr/share/dict/words > NEW_FILE

         # use text diff (113K)
         diff OLD_FILE NEW_FILE > DELTA.diff

         # use delta diff (23K)
         xdelta3 -efS -D -s OLD_FILE NEW_FILE DELTA.vcdiff

         # apply delta diff
         xdelta3 -dfS -D -s OLD_FILE DELTA.vcdiff DECODED_FILE

         # verify that it worked
         diff NEW_FILE DECODED_FILE
         */

        XCTAssertEqual(try delta(d1: Data([0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0]), d2: Data([0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1, 0, 0, 0, 0, 0, 0, 0, 0, 0]), options: .adler32).base64EncodedString(), "1sPEAAAFCgARFQADBAEAHwACAAEAGgMACQA=")

        XCTAssertEqual(try delta(d1: Data([]), d2: Data([]), options: .nocompress).base64EncodedString(), "1sPEAAAABQAAAAAA")
        XCTAssertEqual(try delta(d1: Data([]), d2: Data([]), options: .adler32).base64EncodedString(), "1sPEAAAECQAAAAAAAAAAAQ==")

        XCTAssertEqual(try delta(d1: Data([0x00]), d2: Data([]), options: .adler32).base64EncodedString(), "1sPEAAAECQAAAAAAAAAAAQ==")
        XCTAssertEqual(try delta(d1: Data([]), d2: Data([0x00]), options: .adler32).base64EncodedString(), "1sPEAAAECwEAAQEAAAEAAQAC")
        XCTAssertEqual(try delta(d1: Data([0x00]), d2: Data([0x00]), options: .adler32).base64EncodedString(), "1sPEAAAECwEAAQEAAAEAAQAC")
        XCTAssertEqual(try delta(d1: Data([0x01, 0x02, 0x03]), d2: Data([0x03, 0x02, 0x01]), options: .adler32).base64EncodedString(), "1sPEAAAEDQMAAwEAABEABwMCAQQ=")
        XCTAssertEqual(try delta(d1: Data([0x01, 0x01, 0x01]), d2: Data([0x01, 0x01, 0x01, 0x01, 0x01, 0x01, 0x01, 0x00]), options: .adler32).base64EncodedString(), "1sPEAAAEDggAAgIBACsACAEApQIA")

        XCTAssertEqual(try delta(d1: Data(Array(repeating: 0x00, count: 1000)), d2: Data(Array(repeating: 0x00, count: 1001)), options: .nocompress).base64EncodedString(), "1sPEAAABh2gADIdpAAEEAQATh2gCAA==")
        XCTAssertEqual(try delta(d1: Data(Array(repeating: 0x00, count: 1000)), d2: Data(Array(repeating: 0x00, count: 1001)), options: .adler32).base64EncodedString(), "1sPEAAAFh2gAEIdpAAEEAQPpAAEAE4doAgA=")

        XCTAssertEqual(try delta(d1: Data(Array(repeating: 0x02, count: 1000)), d2: Data(Array(repeating: 0x03, count: 1001)), options: .adler32).base64EncodedString(), "1sPEAAAEDodpAAEDAPoqC7wDAIdp")
    }

    func testXRandomDeltas() throws {
        func rndData(count: Int) -> Data {
            #if canImport(Darwin)
            // optimized random buffer creation
            var data = Data(count: count)
            data.withUnsafeMutableBytes { mutableBytes in
                if let bytes = mutableBytes.baseAddress {
                    arc4random_buf(bytes, count)
                }
            }
            return data
            #else
            // no arc4random_buf on Linux, so take the (very) slow path
            var rnd = SystemRandomNumberGenerator()
            return Data((0..<count).map({ _ in rnd.next(upperBound: UInt8.max) }))
            #endif
        }

        // create and verify patches from some random sets of data and with random sizes
        for count in stride(from: 0, to: 1024 * 500, by: .random(in: (1024*15)...(1024*30))) {
            let result = try delta(d1: rndData(count: count), d2: rndData(count: count))
            // patch should have been smaller than input data
            if count > 0 {
                XCTAssertLessThanOrEqual(result.count, count * 2, "patch should have been smaller than input data * 2")
            }

            try delta(d1: rndData(count: count / 2), d2: rndData(count: count))
            try delta(d1: rndData(count: count), d2: rndData(count: count / 2))

            try delta(d1: rndData(count: count), d2: rndData(count: 0))
            try delta(d1: rndData(count: 0), d2: rndData(count: count))
        }
    }

    @discardableResult private func delta(verify: Bool = true, d1 sourceData: Data, d2 targetData: Data, options: XDelta.Options = XDelta.Options()) throws -> Data {
        let delta = XDelta(options: options)

        func tmpfile(_ data: Data? = nil) throws -> URL {
            let tmpURL = URL(fileURLWithPath: "xdelta-\(UUID().uuidString)", isDirectory: false, relativeTo: URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true))
            if let data = data {
                try data.write(to: tmpURL)
            }
            return tmpURL
        }

        let sourceURL = try tmpfile(sourceData)
        defer { try? FileManager.default.removeItem(at: sourceURL) }

        let targetURL = try tmpfile(targetData)
        defer { try? FileManager.default.removeItem(at: targetURL) }

        var patchData = Data()
        try delta.createPatch(fromSourceURL: sourceURL, toTargetURL: targetURL) {
            patchData += $0
        }

        if verify {
            var patchedData = Data()
            try delta.applyPatch(toSourceURL: sourceURL, patchURL: tmpfile(patchData)) {
                //try Task.checkCancellation()
                patchedData += $0
            }
            // now verify that the two targets are identical
            XCTAssertEqual(targetData, patchedData)

            // debug with the cli in case of differences
            if targetData != patchedData {
                let patchFile = try tmpfile(patchData)
                print("xdelta3 -dfS -D -s \(sourceURL.path) \(patchFile.path) DECODED_FILE")
                print("diff \(targetURL.path) DECODED_FILE")
            }
        }

        return patchData
    }
}
