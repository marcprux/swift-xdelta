// swift-tools-version: 5.8
import PackageDescription

let package = Package(
    name: "swift-xdelta",
    products: [
        .library(name: "XDelta", targets: ["XDelta"]),
    ],
    targets: [
        .target(name: "XDelta", dependencies: ["XDeltaC"]),
        .target(name: "XDeltaC", path: "xdelta3", exclude: ["examples/iOS"], sources: ["xdelta3.c"], publicHeadersPath: "headers", cSettings: [.define("SIZEOF_SIZE_T", to: "8"), .define("XD3_USE_LARGEFILE64", to: "0")]),
        .testTarget(name: "XDeltaTests", dependencies: ["XDelta"]),
    ]
)
