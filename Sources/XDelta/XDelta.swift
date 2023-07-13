import XDeltaC
#if canImport(Glibc)
import Glibc
#endif
import struct Foundation.URL
import struct Foundation.Data

public struct XDelta {
    func applyPatch(encode: Bool = false, patchFile: URL, inURL: URL, outURL: URL, bufferSize: Int = 0x1000) throws -> Bool {
        guard let srcFile = fopen(patchFile.path, "rb") else {
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

        return code(encode: false, srcFile: inFile, inFile: srcFile, outFile: outFile, bufSize: bufferSize) == 0
    }

    func code(encode: Bool,
              srcFile: UnsafeMutablePointer<FILE>?,
              inFile: UnsafeMutablePointer<FILE>,
              outFile: UnsafeMutablePointer<FILE>,
              bufSize bsize: Int) -> Int {

        var r: Int
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

        xd3_init_config(&config, XD3_ADLER32.rawValue)
        config.winsize = bufSize
        xd3_config_stream(&stream, &config)

        if let srcFile = srcFile {
            r = Int(fstat(fileno(srcFile), &statbuf))
            if r != 0 {
                // TODO: throw Errors.couldNotReadSourceFileError
                return Int(r)
            }

            source.blksize = bufSize
            let blk = UnsafeMutablePointer<UInt8>.allocate(capacity: source.blksize)
            source.curblk = UnsafePointer(blk)
            r = Int(fseek(srcFile, 0, SEEK_SET))
            if r != 0 {
                return Int(r)
            }

            source.onblk = fread(UnsafeMutableRawPointer(mutating: source.curblk), 1, source.blksize, srcFile)
            source.curblkno = 0

            xd3_set_source(&stream, &source)
        }

        inputBuf = malloc(bufSize)

        fseek(inFile, 0, SEEK_SET)

        outerLoop: repeat {
            inputBufRead = fread(inputBuf, 1, bufSize, inFile)

            if inputBufRead < bufSize {
                xd3_set_flags(&stream, XD3_FLUSH.rawValue | stream.flags)
            }

            xd3_avail_input(&stream, inputBuf, inputBufRead)

            var ret: Int32
            innerLoop: while true {
                ret = encode ? xd3_encode_input(&stream) : xd3_decode_input(&stream)

                switch ret {
                case XD3_INPUT.rawValue:
                    print("XD3_INPUT")
                    continue outerLoop

                case XD3_OUTPUT.rawValue:
                    print("XD3_OUTPUT")
                    r = fwrite(stream.next_out, 1, stream.avail_out, outFile)
                    if r != stream.avail_out {
                        return Int(r)
                    }
                    xd3_consume_output(&stream)
                    continue innerLoop

                case XD3_GETSRCBLK.rawValue:
                    print("XD3_GETSRCBLK %qd", source.getblkno)
                    r = Int(fseek(srcFile, source.blksize * Int(source.getblkno), SEEK_SET))
                    if r != 0 {
                        return Int(r)
                    }
                    source.onblk = fread(UnsafeMutableRawPointer(mutating: source.curblk), 1, source.blksize, srcFile)

                    source.curblkno = source.getblkno
                    continue innerLoop

                case XD3_GOTHEADER.rawValue:
                    print("XD3_GOTHEADER")
                    continue innerLoop

                case XD3_WINSTART.rawValue:
                    print("XD3_WINSTART")
                    continue innerLoop

                case XD3_WINFINISH.rawValue:
                    print("XD3_WINFINISH")
                    continue innerLoop

                default:
                    // TODO: throw exception

                    // FIXME: magic not being loaded from tmp diff file for some reason
                    print("!!! INVALID %s %d !!!", String(cString: stream.msg), ret)
                    return Int(ret)
                }
            }
        } while inputBufRead == bufSize

        free(inputBuf)
        //free(&source.curblk)

        xd3_close_stream(&stream)
        xd3_free_stream(&stream)

        return 0
    }
}
