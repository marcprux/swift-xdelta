import XCTest
@testable import XDelta

final class XDeltaTests: XCTestCase {
    func testXDelta() throws {
        // a known vcdiff that gets from the first data blob to the second
        // create patch with:
        // xdelta3 -e -N -D -f -S - -s /tmp/file1.txt /tmp/file2.txt /tmp/deltafile.txt
        XCTAssertEqual(try delta(d1: Data([0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0]), d2: Data([0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1, 0, 0, 0, 0, 0, 0, 0, 0, 0])).base64EncodedString(), "1sPEAAAFCgAQFQACBAEAIAACAQAaAgAKAA==")

        XCTAssertEqual(try delta(d1: Data([]), d2: Data([])).base64EncodedString(), "1sPEAAAECQAAAAAAAAAAAQ==")
        XCTAssertEqual(try delta(d1: Data([0x00]), d2: Data([])).base64EncodedString(), "1sPEAAAECwEAAQEAAAEAAQAC")
        XCTAssertEqual(try delta(d1: Data([]), d2: Data([0x00])).base64EncodedString(), "1sPEAAAECQAAAAAAAAAAAQ==")
        XCTAssertEqual(try delta(d1: Data([0x00]), d2: Data([0x00])).base64EncodedString(), "1sPEAAAECwEAAQEAAAEAAQAC")
        XCTAssertEqual(try delta(d1: Data([0x01, 0x02, 0x03]), d2: Data([0x03, 0x02, 0x01])).base64EncodedString(), "1sPEAAAEDQMAAwEAAA0ABwECAwQ=")
        XCTAssertEqual(try delta(d1: Data([0x01, 0x01, 0x01]), d2: Data([0x01, 0x01, 0x01, 0x01, 0x01, 0x01, 0x01, 0x00])).base64EncodedString(), "1sPEAAAEDQMAAwEAAAkABAEBAQQ=")

        XCTAssertEqual(try delta(d1: Data(Array(repeating: 0x00, count: 1000)), d2: Data(Array(repeating: 0x00, count: 1001))).base64EncodedString(), "1sPEAAAFh2gADodoAAADAQPoAAETh2gA")

        XCTAssertEqual(try delta(d1: Data(Array(repeating: 0x02, count: 1000)), d2: Data(Array(repeating: 0x03, count: 1001))).base64EncodedString(), "1sPEAAAEDodoAAEDAErxB9ECAIdo")
    }

    func testRandomDeltas() throws {

        func rndData(count: Int) -> Data {
            Data((0..<count).map({ _ in UInt8.random(in: (.min)...(.max)) }))
        }

        // create and verify patches from some random sets of data
        for count in stride(from: 0, to: 1024 * 1024, by: 1024 * 432) {
            let result = try delta(d1: rndData(count: count), d2: rndData(count: count))
            // patch should have been smaller than input data
            if count > 0 {
                XCTAssertLessThanOrEqual(result.count, count * 2, "patch should have been smaller than input data * 2")
            }

            let _ = try delta(d1: rndData(count: count / 2), d2: rndData(count: count))
            let _ = try delta(d1: rndData(count: count), d2: rndData(count: count / 2))

            let _ = try delta(d1: rndData(count: count), d2: rndData(count: 0))
            let _ = try delta(d1: rndData(count: 0), d2: rndData(count: count))
        }

    }


    func delta(d1: Data, d2: Data) throws -> Data {
        let xdelta = XDelta()

        let fid = UUID().uuidString
        // test two data blobs with a slight difference
        let f1 = URL(fileURLWithPath: NSTemporaryDirectory() + "/testXDelta1-\(fid).txt")
        try d1.write(to: f1)

        let f2 = URL(fileURLWithPath: NSTemporaryDirectory() + "/testXDelta2-\(fid).txt")
        try d2.write(to: f2)

        let df = URL(fileURLWithPath: NSTemporaryDirectory() + "/testXDelta-delta-\(fid).txt")

        let encoded = try xdelta.apply(encode: true, inURL: f1, srcURL: f2, outURL: df)

        XCTAssertEqual(true, encoded)

        let deltaContents = try Data(contentsOf: df)

        let contents = try Data(contentsOf: f2)
        XCTAssertEqual(d2, contents)

        let decoded = try xdelta.apply(encode: false, inURL: df, srcURL: f2, outURL: f1)

        XCTAssertEqual(true, decoded)
        let f2Contents = try Data(contentsOf: f2)
        XCTAssertEqual(d2, f2Contents)

        return deltaContents
    }
}
