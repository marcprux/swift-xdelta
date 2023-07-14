# swift-xdelta

VCDIFF is an algorithm that computes changes between a source and target file, and can later apply those changes to the source file to derive the target file. These changes (deltas) are similar to the output of the “diff” program in that they may be used to store and transmit only the changes between files.

This is useful for streamlining the distribution of changes to large files over potentially slow or expensive data connections, such as when making updates to large online assets for mobile or embedded applications. 

The `xdelta` library is an encoder and decoder that can write and read the VCDIFF format described in [RFC 3284 : The VCDIFF Generic Differencing and Compression Data Format](https://www.rfc-editor.org/rfc/rfc3284). 
The encoder uses the [Bentley/McIlroy technique](http://citeseerx.ist.psu.edu/viewdoc/download?doi=10.1.1.11.8470&rep=rep1&type=pdf) for finding matches between the source and target data. 

The `swift-xdelta` repository is a fork of https://github.com/jmacd/xdelta that adds a `Package.swift`
and Swift wrapper interface to the existing C `xdelta3` library. It has no dependencies, and runs on macOS, iOS, tvOS, watchOS, and Linux.

The `XDelta` Swift module can be used to create and process patches between two files.
Files can be arbitrarily large, and are never loaded into memory in their entirety.
The `vcdiff` files are compatible with the [xdelta3](https://formulae.brew.sh/formula/xdelta) command-line tool when run with compression disabled.

## Requirements

| Platform | Minimum Swift Version
| --- | --- |
| iOS 14 | 5.8 |
| macOS 12 | 5.8 |
| tvOS 8 | 5.8 |
| watchOS 8 | 5.8 |
| Linux | 5.8 |
| Windows | Untested |
| Android | Untested |

## Installation

### Swift Package Manager

The [Swift Package Manager](https://swift.org/package-manager/) is a tool for automating the distribution of Swift code and is integrated into the `swift` compiler. 

Add swift-xdelta to your `Package.swift` by adding it to the `dependencies` property of your target.

```swift
dependencies: [
  .package(url: "https://github.com/marcprux/swift-xdelta.git", .from(from: "1.0.0"))
]
```


## API Sample

### Create a patch

The following sample will take the file URL at `sourceFile`, and
generate a patch that, when applied, will transform the source data into the
contents of the `targetFile` file URL.

```swift
import XDelta
let delta = XDelta(options: XDelta.Options())

var patchData = Data()
try delta.createPatch(fromSourceURL: sourceFile, toTargetURL: targetFile) {
	patchData += $0
}
```

### Streaming patch creation

Note that since patch data can be quite large when the source or target files are
large, you may want to stream the patch output to a `FileHandle` rather 
than to in-memory data. This can be done like:

```swift
let patchWriter = FileHandle(forWritingTo: patchFile)
try delta.createPatch(fromSourceURL: sourceFile, toTargetURL: targetFile) {
	try Task.checkCancellation()
	try patchWriter.write(data)
}
```


### Apply a patch

Now given the `sourceFile` and a `patchFile` containing the patch data,
an `outputFile` can be derived whose contents will be the same as `targetFile`.

```swift
let targetWriter = FileHandle(forWritingTo: outputFile)
try delta.applyPatch(toSourceURL: sourceFile, patchURL: patchFile) { data in
	try Task.checkCancellation()
	try targetWriter.write(data)
}
```


## Command-line usage

swift-xdelta does not itself have a CLI, but the standard `xdelta3` command can create and process patches. 
It can be installed with `brew install xdelta` on macOS and `apt install xdelta` on Debian.
For example, creating a diff for some random text:

```
head -n 5000 /usr/share/dict/words > OLD_FILE
tail -n 5000 /usr/share/dict/words > NEW_FILE

xdelta3 -efS -D -s OLD_FILE NEW_FILE DELTA.vcdiff
xdelta3 -dfS -D -s OLD_FILE DELTA.vcdiff DECODED_FILE

diff NEW_FILE DECODED_FILE
```


# Limitations

Compression is not supported in the Swift package.
To add support for, e.g., LZMA compression,
we would need to build LZMA as part of this package.

# Documentation

For the `xdelta3` command-line tools, 
see [command-line usage](https://github.com/jmacd/xdelta/blob/wiki/CommandLineSyntax.md).  

