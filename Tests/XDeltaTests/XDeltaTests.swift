import XCTest
@testable import XDelta

final class XDeltaTests: XCTestCase {
    func testXDelta() throws {
        // a known vcdiff that gets from the first data blob to the second
        // create patch with:
        // xdelta3 -e -N -D -f -S - -s /tmp/file1.txt /tmp/file2.txt /tmp/deltafile.txt
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

    func testRandomDeltas() throws {

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

    @discardableResult private func delta(urlMode: Bool = true, d1: Data, d2: Data, options: XDelta.Options = XDelta.Options()) throws -> Data {
        let delta = XDelta(options: options)

        if urlMode {
            func tmpfile(_ data: Data? = nil) throws -> URL {
                let tmpURL = URL(fileURLWithPath: "xdelta-\(UUID().uuidString)", isDirectory: false, relativeTo: URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true))
                if let data = data {
                    try data.write(to: tmpURL)
                }
                return tmpURL
            }

            let patchURL = try tmpfile(Data())
            let f1 = try tmpfile(d1)
            let f2 = try tmpfile(d2)
            try delta.createPatch(fromSourceURL: f1, toTargetURL: f2, patchURL: patchURL)
            //try print("  createPatch:", f1.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0, f2.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0, patchURL.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0)
            try delta.applyPatch(patchURL: patchURL, toSourceURL: f1, targetURL: f2)
            //try print("   applyPatch:", f1.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0, f2.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0, patchURL.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0)

            return try Data(contentsOf: patchURL)
        } else { // memory mode
            let vcdiff = try delta.createPatch(fromSourceData: d1, toTargetData: d2)
            let decoded = try delta.applyPatch(patchData: vcdiff, toSourceData: d1)
            XCTAssertEqual(d2, decoded)
            return vcdiff
        }
    }
}
