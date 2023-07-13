import XCTest
@testable import XDelta

final class XDeltaTests: XCTestCase {
    func testXDelta() throws {
        // test two data blobs with a slight difference
        let d1 = Data([0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0])
        let f1 = URL(fileURLWithPath: NSTemporaryDirectory() + "/testXDelta1.txt")
        try d1.write(to: f1)

        let d2 = Data([0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1, 0, 0, 0, 0, 0, 0, 0, 0, 0])
        let f2 = URL(fileURLWithPath: NSTemporaryDirectory() + "/testXDelta2.txt")
        try d2.write(to: f2)

        let df = URL(fileURLWithPath: NSTemporaryDirectory() + "/testXDelta-delta.txt")

        // a known vcdiff that gets from the first data blob to the second
        // create patch with:
        // xdelta3 -e -N -D -f -S - -s /tmp/file1.txt /tmp/file2.txt /tmp/deltafile.txt
        let delta = Data(base64Encoded: "1sPEAAQVZmlsZTIudHh0Ly9maWxlMS50eHQvBQoAERUAAwQBAB8AAgABABoDAAkA")!

        try delta.write(to: df, options: .atomic)

        try? FileManager.default.removeItem(at: f2) // ensure that an old file does not exist

        let success = try XDelta().applyPatch(encode: false, patchFile: df, inURL: f1, outURL: f2)

        XCTAssertEqual(true, success)
        let contents = try Data(contentsOf: f2)
        XCTAssertEqual(d2, contents)
    }
}
