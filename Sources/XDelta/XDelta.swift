import XDeltaC
#if canImport(Glibc)
import Glibc
#endif
import Foundation

/// Handles the creation of binary patch files in the rfc3284 `vcdiff` format,
/// as well as applying the patch to source data.
public struct XDelta {
    /// Options for stream handling
    public let options: Options
    /// The size of the read buffer. Must be a power of 2.
    public var bufferSize: Int

    public init(options: Options = .standard, bufferSize: Int? = nil) {
        self.options = options
        self.bufferSize = bufferSize ?? Int(XD3_ALLOCSIZE) // (1U<<14)
        assert((self.bufferSize & (self.bufferSize - 1)) == 0, "buffer size must be a power of 2 (\(self.bufferSize))")
    }

    /// Create patch data in the `vcdiff` format. The patch can then be applied to the source data using
    /// `applyPath` to derive the target data.
    ///
    /// - Note: Compressed patch blocks are not yet supported.
    /// - See: https://www.rfc-editor.org/rfc/rfc3284
    public func createPatch(fromSourceURL sourceURL: URL, toTargetURL targetURL: URL, patchDataHandler resultHandler: (Data) throws -> ()) throws {
        try apply(encode: true, inURL: targetURL, srcURL: sourceURL, resultHandler: resultHandler)
    }

    /// Apply a patch data in the `vcdiff` format. The patch may have been created using the
    /// `createPatch` function, or the `xdelta` command line tool.
    ///
    /// - Note: Compressed patch blocks are not yet supported, and patch files using compression (LZMA or other) will result in an error.
    /// - See: https://www.rfc-editor.org/rfc/rfc3284
    public func applyPatch(toSourceURL sourceURL: URL, patchURL: URL, targetDataHandler resultHandler: (Data) throws -> ()) throws {
        try apply(encode: false, inURL: patchURL, srcURL: sourceURL, resultHandler: resultHandler)
    }

    private func apply(encode: Bool, useFileHandles: Bool = false, inURL: URL, srcURL: URL, resultHandler: (Data) throws -> ()) throws {

        if #available(macOS 13, iOS 13.4, tvOS 13.4, watchOS 13.4, *), useFileHandles {
            #if os(Linux) // codeHandle does not work on Linux due to missing InputStream.read()
            try readFS()
            #else
            guard let stream = InputStream(url: inURL) else {
                throw Errors.cannotOpenStream(url: inURL)
            }
            stream.open()

            // don't bother using the FileHandle version, since it always copies data
            try Self.codeHandle(encode: encode, inStream: stream, srcFile: FileHandle(forReadingFrom: srcURL), options: options, bufSize: bufferSize, resultHandler: resultHandler)
            #endif
        } else {
            try readFS()
        }

        func readFS() throws {
            guard let srcFile = fopen(srcURL.path, "rb") else {
                throw URLError(.fileDoesNotExist, userInfo: [NSURLErrorKey: srcURL])
            }
            defer { fclose(srcFile) }

            guard let inFile = fopen(inURL.path, "rb") else {
                throw URLError(.fileDoesNotExist, userInfo: [NSURLErrorKey: inURL])
            }
            defer { fclose(inFile) }

            try Self.codeFile(encode: encode, inFile: inFile, srcFile: srcFile, options: options, bufSize: bufferSize, resultHandler: resultHandler)
        }
    }

    private static func codeFile(encode: Bool,
              inFile: UnsafeMutablePointer<FILE>,
              srcFile: UnsafeMutablePointer<FILE>,
              options: Options,
              bufSize: Int, resultHandler: (Data) throws -> ()) throws {
        @discardableResult func posix(_ block: @autoclosure () -> Int32) throws -> Int32 {
            let r = block()
            if r != 0 {
                throw POSIXError(POSIXErrorCode(rawValue: r) ?? .EPIPE)
            }
            return r
        }

        var statbuf = stat()
        try posix(fstat(fileno(srcFile), &statbuf))
        try posix(fseek(srcFile, 0, SEEK_SET))
        try posix(fseek(inFile, 0, SEEK_SET))
        try code(encode: encode, bufSize: bufSize, options: options, readInputStream: { bytes, size in
            return fread(bytes, 1, size, inFile)
        }, readSourceBlock: { offset, bytes, size in
            try posix(fseek(srcFile, .init(offset), SEEK_SET))
            return fread(bytes, 1, size, srcFile)
        }, writeTargetData: { bytes, size in
            try resultHandler(Data(bytes: bytes, count: size))
        })
    }

    // InputStream.read does not compile on Linux: error: cannot convert value of type 'UnsafeMutableRawPointer' to expected argument type 'UnsafeMutablePointer<UInt8>' because instance method 'read(_:maxLength:)' was not imported from C header
    #if !os(Linux)
    /// Performs coding on a FileHandle.
    ///
    /// - Note: slower than `codeFile` due to file copies
    @available(macOS 13, iOS 13.4, tvOS 13.4, watchOS 13.4, *)
    private static func codeHandle(encode: Bool,
              inStream: InputStream,
              srcFile: FileHandle,
              options: Options,
              bufSize: Int, resultHandler: (Data) throws -> ()) throws {
        try srcFile.seek(toOffset: 0)

        try code(encode: encode, bufSize: bufSize, options: options, readInputStream: { bytes, size in
            inStream.read(bytes, maxLength: size)
        }, readSourceBlock: { offset, bytes, size in
            try srcFile.seek(toOffset: offset)
            guard let data = try srcFile.read(upToCount: size) else {
                return 0
            }
            data.copyBytes(to: UnsafeMutableRawBufferPointer(start: bytes, count: data.count))
            return data.count
        }, writeTargetData: { bytes, count in
            try resultHandler(Data(bytes: bytes, count: count))
        })
    }
    #endif

    private static func code(encode: Bool, bufSize: Int, options: Options, readInputStream: (_ bytes: UnsafeMutableRawPointer, _ size: Int) throws -> (Int), readSourceBlock: (_ offset: UInt64, _ bytes: UnsafeMutableRawPointer, _ size: Int) throws -> (Int), writeTargetData: (_ bytes: UnsafeMutableRawPointer, _ count: Int) throws -> ()) throws {
        var stream = xd3_stream()
        memset(&stream, 0, MemoryLayout<xd3_stream>.size)
        defer {
            xd3_close_stream(&stream)
            xd3_free_stream(&stream)
        }

        var config = xd3_config()
        xd3_init_config(&config, options.rawValue)
        config.winsize = bufSize
        xd3_config_stream(&stream, &config)

        var source = xd3_source()
        memset(&source, 0, MemoryLayout<xd3_source>.size)

        source.blksize = bufSize

        let sourceBuf = UnsafeMutablePointer<UInt8>.allocate(capacity: source.blksize)
        defer { sourceBuf.deallocate() }

        source.curblk = UnsafePointer(sourceBuf)

        let inputBuf = UnsafeMutableRawPointer.allocate(byteCount: bufSize, alignment: 0)
        defer { inputBuf.deallocate() }

        source.onblk = try readSourceBlock(0, sourceBuf,  source.blksize)
        source.curblkno = 0

        xd3_set_source(&stream, &source)

        var inputBufRead: Int
        readInputBuffer: repeat {
            inputBufRead = try readInputStream(inputBuf, bufSize)
            if inputBufRead < 0 {
                throw Errors.readPastEnd
            }
            if inputBufRead < bufSize {
                xd3_set_flags(&stream, XD3_FLUSH.rawValue | stream.flags)
            }

            xd3_avail_input(&stream, inputBuf, inputBufRead)

            codeStream: while true {
                let ret = xd3_rvalues(encode ? xd3_encode_input(&stream) : xd3_decode_input(&stream))

                switch ret {
                case XD3_INPUT:
                    continue readInputBuffer

                case XD3_OUTPUT:
                    if stream.avail_out > 0 && stream.next_out != nil {
                        try writeTargetData(stream.next_out, stream.avail_out)
                    }
                    xd3_consume_output(&stream)
                    continue codeStream

                case XD3_GETSRCBLK:
                    source.curblkno = source.getblkno
                    source.onblk = try readSourceBlock(UInt64(usize_t(source.getblkno) * source.blksize), sourceBuf, source.blksize)
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
    }

    /// Options for controlling the creation and application of binary patches
    public struct Options : OptionSet {
        public let rawValue: UInt32
        public init(rawValue: UInt32) {
            self.rawValue = rawValue
        }

        public static let standard: Self = [.adler32, .nocompress]

        //public static let justHeader = Options(rawValue: XD3_JUST_HDR.rawValue)
        //public static let skipWindow = Options(rawValue: XD3_SKIP_WINDOW.rawValue)
        //public static let skipEmit = Options(rawValue: XD3_SKIP_EMIT.rawValue)
        //public static let flush = Options(rawValue: XD3_FLUSH.rawValue)

        /// use DJW static huffman
        @available(*, unavailable, message: "compression is not supported")
        public static let compressDJW = Options(rawValue: XD3_SEC_DJW.rawValue)
        /// use FGK adaptive huffman
        @available(*, unavailable, message: "compression is not supported")
        public static let compressFGK = Options(rawValue: XD3_SEC_FGK.rawValue)
        /// use LZMA secondary
        @available(*, unavailable, message: "compression is not supported")
        public static let compressLZMA = Options(rawValue: XD3_SEC_LZMA.rawValue)

        @available(*, unavailable, message: "compression is not supported")
        public static let compressAll = Options(rawValue: XD3_SEC_TYPE.rawValue) // (XD3_SEC_DJW | XD3_SEC_FGK | XD3_SEC_LZMA)

        //public static let nodata = Options(rawValue: XD3_SEC_NODATA.rawValue)
        //public static let noinst = Options(rawValue: XD3_SEC_NOINST.rawValue)
        //public static let noaddr = Options(rawValue: XD3_SEC_NOADDR.rawValue)
        //public static let noall = Options(rawValue: XD3_SEC_NOALL.rawValue) // (XD3_SEC_NODATA | XD3_SEC_NOINST | XD3_SEC_NOADDR),

        /// enable checksum computation in the encoder.
        public static let adler32 = Options(rawValue: XD3_ADLER32.rawValue)
        /// disable checksum verification in the decoder.
        public static let adlre32NoVer = Options(rawValue: XD3_ADLER32_NOVER.rawValue)

        /// disable ordinary data compression feature, only search the source, not the target.
        public static let nocompress = Options(rawValue: XD3_NOCOMPRESS.rawValue)

        /// disable the "1.5-pass algorithm", instead use greedy matching.  Greedy is off by default.
        public static let greedy = Options(rawValue: XD3_BEGREEDY.rawValue)

        /// used by "recode"
        //public static let recode = Options(rawValue: XD3_ADLER32_RECODE.rawValue)
    }

    public enum Errors : Error {
        case inputError(code: Int32, message: String)
        case readPastEnd
        case cannotOpenStream(url: URL)
    }
}
