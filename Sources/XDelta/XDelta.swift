import XDeltaC
#if canImport(Glibc)
import Glibc
#endif
import Foundation

/// Handles the creation of binary patch files in the rfc3284 `vcdiff` format,
/// as well as applying the patch to source data.
public struct XDelta {
    /// Create patch data in the `vcdiff` format. The patch can then be applied to the source data using
    /// `applyPath` to derive the target data.
    ///
    /// - Note: Compressed patch blocks are not yet supported.
    /// - See: https://www.rfc-editor.org/rfc/rfc3284
    public static func createPatch(fromSourceData sourceData: Data, toTargetData targetData: Data) throws -> Data {
        try run(encode: true, from: targetData, to: sourceData)
    }

    /// Apply a patch data in the `vcdiff` format. The patch may have been created using the
    /// `createPatch` function, or the `xdelta` command line tool.
    ///
    /// - Note: Compressed patch blocks are not yet supported, and patch files using compression (LZMA or other) will result in an error.
    /// - See: https://www.rfc-editor.org/rfc/rfc3284
    public static func applyPatch(patchData: Data, toSourceData sourceData: Data) throws -> Data {
        try run(encode: false, from: patchData, to: sourceData)
    }

    private static func run(encode: Bool, from d1: Data, to d2: Data) throws -> Data {
        let tmp = NSTemporaryDirectory()
        let fid = UUID().uuidString

        let f1 = URL(fileURLWithPath: tmp + "/xdelta1-\(fid).dat")
        try d1.write(to: f1)
        defer { try? FileManager.default.removeItem(at: f1) }

        let f2 = URL(fileURLWithPath: tmp + "/xdelta2-\(fid).dat")
        try d2.write(to: f2)
        defer { try? FileManager.default.removeItem(at: f2) }

        let df = URL(fileURLWithPath: tmp + "/xdelta3-\(fid).dat")
        defer { try? FileManager.default.removeItem(at: df) }

        try apply(encode: encode, inURL: f1, srcURL: f2, outURL: df)
        return try Data(contentsOf: df) // read the patch from the output file
    }

    static func apply(encode: Bool, inURL: URL, srcURL: URL, outURL: URL, bufferSize: Int = 0x1000) throws {
        guard let srcFile = fopen(srcURL.path, "rb") else {
            fatalError("Failed to open source file")
        }
        defer { fclose(srcFile) }

        guard let inFile = fopen(inURL.path, "rb") else {
            fatalError("Failed to open target file")
        }
        defer { fclose(inFile) }

        guard let outFile = fopen(outURL.path, "wb") else {
            fatalError("Failed to open target file")
        }
        defer { fclose(outFile) }

        try code(encode: encode, inFile: inFile, srcFile: srcFile, outFile: outFile, bufSize: bufferSize)
    }

    private static func code(encode: Bool,
              inFile: UnsafeMutablePointer<FILE>,
              srcFile: UnsafeMutablePointer<FILE>?,
              outFile: UnsafeMutablePointer<FILE>,
              bufSize bsize: Int) throws {
        var r: Int32
        var statbuf = stat()
        var stream = xd3_stream()
        var config = xd3_config()
        var source = xd3_source()
        var inputBuf: UnsafeMutableRawPointer?
        var inputBufRead: Int

        var bufSize = bsize
        if bufSize < XD3_ALLOCSIZE {
            bufSize = Int(XD3_ALLOCSIZE)
        }

        memset(&stream, 0, MemoryLayout<xd3_stream>.size)
        memset(&source, 0, MemoryLayout<xd3_source>.size)
        defer { xd3_close_stream(&stream) }
        defer { xd3_free_stream(&stream) }

        xd3_init_config(&config, XD3_ADLER32.rawValue)
        config.winsize = bufSize
        xd3_config_stream(&stream, &config)

        if let srcFile = srcFile {
            r = fstat(fileno(srcFile), &statbuf)
            if r != 0 {
                throw POSIXError(POSIXErrorCode(rawValue: r) ?? .EPIPE)
            }

            source.blksize = bufSize
            let blk = UnsafeMutablePointer<UInt8>.allocate(capacity: source.blksize)
            source.curblk = UnsafePointer(blk)
            r = fseek(srcFile, 0, SEEK_SET)
            if r != 0 {
                throw POSIXError(POSIXErrorCode(rawValue: r) ?? .EPIPE)
            }

            source.onblk = fread(UnsafeMutableRawPointer(mutating: source.curblk), 1, source.blksize, srcFile)
            source.curblkno = 0

            xd3_set_source(&stream, &source)
        }

        inputBuf = malloc(bufSize)

        fseek(inFile, 0, SEEK_SET)

        readInputBuffer: repeat {
            inputBufRead = fread(inputBuf, 1, bufSize, inFile)

            if inputBufRead < bufSize {
                xd3_set_flags(&stream, XD3_FLUSH.rawValue | stream.flags)
            }

            xd3_avail_input(&stream, inputBuf, inputBufRead)

            var ret: xd3_rvalues
            codeStream: while true {
                ret = xd3_rvalues(encode ? xd3_encode_input(&stream) : xd3_decode_input(&stream))

                switch ret {
                case XD3_INPUT:
                    continue readInputBuffer

                case XD3_OUTPUT:
                    r = Int32(fwrite(stream.next_out, 1, stream.avail_out, outFile))
                    if r != stream.avail_out {
                        throw POSIXError(POSIXErrorCode(rawValue: r) ?? .EPIPE)
                    }
                    xd3_consume_output(&stream)
                    continue codeStream

                case XD3_GETSRCBLK:
                    r = fseek(srcFile, source.blksize * Int(source.getblkno), SEEK_SET)
                    if r != 0 {
                        throw POSIXError(POSIXErrorCode(rawValue: r) ?? .EPIPE)
                    }
                    source.onblk = fread(UnsafeMutableRawPointer(mutating: source.curblk), 1, source.blksize, srcFile)

                    source.curblkno = source.getblkno
                    continue codeStream

                case XD3_GOTHEADER:
                    continue codeStream

                case XD3_WINSTART:
                    continue codeStream

                case XD3_WINFINISH:
                    continue codeStream

                default: // XD3_TOOFARBACK, XD3_INTERNAL, XD3_INVALID_INPUT, etc.
                    throw Errors.inputError(code: ret.rawValue, message: String(cString: stream.msg))
                }
            }
        } while inputBufRead == bufSize

        free(inputBuf)
        //free(&source.curblk)

    }

    public enum Errors : Error {
        case inputError(code: Int32, message: String)
    }
}
