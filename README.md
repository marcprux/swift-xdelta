# swift-xdelta

This repository is a fork of https://github.com/jmacd/xdelta that adds a `Package.swift`
and Swift wrapper interface to the existing C xdelta library. 

Xdelta is an implementation of VCDIFF ([RFC 3284](https://www.rfc-editor.org/rfc/rfc3284)) binary deltas.
It can be used to create and process patches between two arbitrary binaries, similar
to the `diff` and `patch` commands for text files. 
It is compatible with the [xdelta3](https://formulae.brew.sh/formula/xdelta) command-line tool (when disabling compression).

## Requirements

| Platform | Minimum Swift Version
| --- | --- |
| iOS 14+ / macOS 12+ / tvOS 8+ / watchOS 8+ | 5.8 |
| Linux | 5.8 |
| Windows | Unsupported |
| Android | Unsupported |

## Installation

### Swift Package Manager

The [Swift Package Manager](https://swift.org/package-manager/) is a tool for automating the distribution of Swift code and is integrated into the `swift` compiler. 

Once you have your Swift package set up, adding swift-xdelta as a dependency is as easy as adding it to the `dependencies` value of your `Package.swift`.

```swift
dependencies: [
	.package(url: "https://github.com/marcprux/swift-xdelta.git", .from(from: "0.0.2"))
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

swift-xdelta does not itself have a CLI, but the standard `xdelta3`
command can create and process patches. For example, creating a diff
for some random text:

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

