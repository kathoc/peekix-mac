import AVFoundation
import CFFmpeg
import CoreMedia
import CoreVideo
import Foundation
import VideoToolbox
import os

public protocol PlaybackEngineDelegate: AnyObject {
    func playbackEngine(_ engine: PlaybackEngine, didOutputFrame pixelBuffer: CVPixelBuffer, pts: CMTime)
    func playbackEngine(_ engine: PlaybackEngine, didChangeStatus status: PlaybackEngineStatus)
    func playbackEngine(_ engine: PlaybackEngine, didEncounterError error: Error)
}

public enum PlaybackEngineStatus: Equatable, Sendable {
    case idle
    case connecting
    case playing
    case stopped
}

public enum RTSPTransport: String, Sendable {
    case auto
    case tcp
    case udp
}

public enum PlaybackEngineError: Error, CustomStringConvertible {
    case openFailed(Int32)
    case streamInfoFailed(Int32)
    case noVideoStream
    case unsupportedCodec
    case missingExtradata
    case parameterSetParseFailed
    case formatDescriptionFailed(OSStatus)
    case decompressionSessionFailed(OSStatus)
    case readFailed(Int32)
    case sampleBufferFailed(OSStatus)

    public var description: String {
        switch self {
        case .openFailed(let r): return "avformat_open_input failed (\(r))"
        case .streamInfoFailed(let r): return "avformat_find_stream_info failed (\(r))"
        case .noVideoStream: return "no H.264 / HEVC video stream"
        case .unsupportedCodec: return "unsupported codec"
        case .missingExtradata: return "codec extradata missing"
        case .parameterSetParseFailed: return "could not parse SPS/PPS from extradata"
        case .formatDescriptionFailed(let s): return "CMVideoFormatDescription failed (\(s))"
        case .decompressionSessionFailed(let s): return "VTDecompressionSession failed (\(s))"
        case .readFailed(let r): return "av_read_frame failed (\(r))"
        case .sampleBufferFailed(let s): return "CMSampleBuffer failed (\(s))"
        }
    }
}

public final class PlaybackEngine: @unchecked Sendable {
    public weak var delegate: PlaybackEngineDelegate?
    public weak var metalRenderer: MetalRenderer?

    private let ffmpegQueue = DispatchQueue(label: "app.peekix.mac.ffmpeg", qos: .userInteractive)
    private let logger = Logger(subsystem: "app.peekix.mac", category: "PlaybackEngine")
    private let cancelLock = NSLock()
    private var _isCancelled = false
    private var _isRunning = false
    private var _isMuted = false

    // NOTE: 現状このエンジンは映像のみをデコードし、音声デコード/出力は未実装。
    // 以下の mute/unmute API は将来の音声パイプライン用フラグ保持のみで、
    // 実際の音声出力への影響はない。
    public var isMuted: Bool {
        cancelLock.lock(); defer { cancelLock.unlock() }
        return _isMuted
    }

    public func mute() {
        cancelLock.lock(); _isMuted = true; cancelLock.unlock()
        DispatchQueue.main.async { [weak self] in self?.audioPlayerNode?.volume = 0 }
    }

    public func unmute() {
        cancelLock.lock(); _isMuted = false; cancelLock.unlock()
        DispatchQueue.main.async { [weak self] in self?.audioPlayerNode?.volume = 1 }
    }

    // MARK: - Audio output

    private var audioEngine: AVAudioEngine?
    private var audioPlayerNode: AVAudioPlayerNode?
    private var audioFormat: AVAudioFormat?

    private func setupAudioOutput(sampleRate: Double, channels: Int) {
        let chs = AVAudioChannelCount(max(1, min(2, channels)))
        guard let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: chs) else { return }
        let isMutedNow = self.isMuted
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.teardownAudioOutput()
            let engine = AVAudioEngine()
            let node = AVAudioPlayerNode()
            engine.attach(node)
            engine.connect(node, to: engine.mainMixerNode, format: format)
            do {
                try engine.start()
            } catch {
                self.logger.error("AVAudioEngine.start failed: \(String(describing: error), privacy: .public)")
                return
            }
            node.volume = isMutedNow ? 0 : 1
            node.play()
            self.audioEngine = engine
            self.audioPlayerNode = node
            self.audioFormat = format
            self.logger.info("audio engine started: sr=\(Int(sampleRate), privacy: .public) ch=\(Int(chs), privacy: .public)")
        }
    }

    private func teardownAudioOutput() {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.audioPlayerNode?.stop()
            self.audioEngine?.stop()
            self.audioPlayerNode = nil
            self.audioEngine = nil
            self.audioFormat = nil
        }
    }

    fileprivate func decodeAndScheduleAudio(frame: UnsafeMutablePointer<AVFrame>,
                                            swr: OpaquePointer,
                                            outChannels: Int,
                                            outSampleRate: Int) {
        guard outChannels > 0 else { return }
        let inSamples = Int(frame.pointee.nb_samples)
        guard inSamples > 0 else { return }
        let outCapacity = max(Int(swr_get_out_samples(swr, Int32(inSamples))), inSamples + 256)
        guard let format = AVAudioFormat(standardFormatWithSampleRate: Double(outSampleRate),
                                         channels: AVAudioChannelCount(outChannels)) else { return }
        guard let pcm = AVAudioPCMBuffer(pcmFormat: format,
                                         frameCapacity: AVAudioFrameCount(outCapacity)) else { return }
        guard let channelData = pcm.floatChannelData else { return }

        var outPtrs: [UnsafeMutablePointer<UInt8>?] = (0..<outChannels).map { idx in
            UnsafeMutableRawPointer(channelData[idx]).assumingMemoryBound(to: UInt8.self)
        }
        let written = outPtrs.withUnsafeMutableBufferPointer { buf -> Int32 in
            cffmpeg_swr_convert_to_float(swr, buf.baseAddress, Int32(outCapacity), frame)
        }
        if written > 0 {
            pcm.frameLength = AVAudioFrameCount(written)
            scheduleAudioBuffer(pcm)
        }
    }

    fileprivate func scheduleAudioBuffer(_ buffer: AVAudioPCMBuffer) {
        DispatchQueue.main.async { [weak self] in
            guard let self, let node = self.audioPlayerNode else { return }
            node.scheduleBuffer(buffer, completionHandler: nil)
        }
    }

    private var decodedFrameCount: UInt64 = 0
    private var firstFrameLogged = false

    private static let networkInit: Void = {
        let r = avformat_network_init()
        Logger(subsystem: "app.peekix.mac", category: "PlaybackEngine")
            .info("avformat_network_init -> \(r, privacy: .public)")
        return ()
    }()

    public init() {
        _ = PlaybackEngine.networkInit
    }

    public func start(url: URL, transport: RTSPTransport) {
        cancelLock.lock()
        if _isRunning {
            cancelLock.unlock()
            logger.notice("start ignored: already running")
            return
        }
        _isCancelled = false
        _isRunning = true
        cancelLock.unlock()
        decodedFrameCount = 0
        firstFrameLogged = false

        emitStatus(.connecting)
        let urlString = url.absoluteString
        ffmpegQueue.async { [weak self] in
            guard let self else { return }
            self.runDemux(urlString: urlString, transport: transport)
            self.cancelLock.lock()
            self._isRunning = false
            self.cancelLock.unlock()
            self.emitStatus(.stopped)
        }
    }

    public func stop() {
        cancelLock.lock()
        _isCancelled = true
        cancelLock.unlock()
    }

    private var isCancelled: Bool {
        cancelLock.lock(); defer { cancelLock.unlock() }
        return _isCancelled
    }

    // MARK: - Notifications (hop to main)

    private func emitStatus(_ status: PlaybackEngineStatus) {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.delegate?.playbackEngine(self, didChangeStatus: status)
        }
    }

    private func emitError(_ error: Error) {
        logger.error("\(String(describing: error), privacy: .public)")
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.delegate?.playbackEngine(self, didEncounterError: error)
        }
    }

    fileprivate func handleDecodedFrame(_ buffer: CVImageBuffer, pts: CMTime) {
        decodedFrameCount &+= 1
        if !firstFrameLogged {
            firstFrameLogged = true
            let pf = CVPixelBufferGetPixelFormatType(buffer)
            let w = CVPixelBufferGetWidth(buffer)
            let h = CVPixelBufferGetHeight(buffer)
            let fourCC = String(format: "%c%c%c%c",
                                (pf >> 24) & 0xFF, (pf >> 16) & 0xFF, (pf >> 8) & 0xFF, pf & 0xFF)
            logger.info("first decoded frame: \(w, privacy: .public)x\(h, privacy: .public) pixelFormat=\(fourCC, privacy: .public) (0x\(String(pf, radix: 16), privacy: .public))")
        }
        if decodedFrameCount % 120 == 0 {
            logger.info("decoded frames: \(self.decodedFrameCount, privacy: .public)")
        }
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.delegate?.playbackEngine(self, didOutputFrame: buffer, pts: pts)
            self.metalRenderer?.render(pixelBuffer: buffer)
        }
    }

    // MARK: - Demux loop

    private func runDemux(urlString: String, transport: RTSPTransport) {
        var formatCtx: UnsafeMutablePointer<AVFormatContext>? = nil
        var options: OpaquePointer? = nil // AVDictionary*
        if transport != .auto {
            av_dict_set(&options, "rtsp_transport", transport.rawValue, 0)
        }
        av_dict_set(&options, "max_analyze_duration", "2000000", 0)
        av_dict_set(&options, "probesize", "32768", 0)
        av_dict_set(&options, "stimeout", "5000000", 0)

        logger.info("avformat_open_input: transport=\(transport.rawValue, privacy: .public)")
        let openRet = avformat_open_input(&formatCtx, urlString, nil, &options)
        if options != nil {
            av_dict_free(&options)
        }
        if openRet < 0 {
            emitError(PlaybackEngineError.openFailed(openRet))
            return
        }
        logger.info("avformat_open_input ok")

        defer {
            if formatCtx != nil {
                avformat_close_input(&formatCtx)
            }
        }

        let infoRet = avformat_find_stream_info(formatCtx, nil)
        if infoRet < 0 {
            emitError(PlaybackEngineError.streamInfoFailed(infoRet))
            return
        }

        guard let ctx = formatCtx else { return }
        var videoStreamIndex: Int32 = -1
        var codecId: AVCodecID = AV_CODEC_ID_NONE
        var stream: UnsafeMutablePointer<AVStream>? = nil
        var audioStreamIndex: Int32 = -1
        let nbStreams = Int(ctx.pointee.nb_streams)
        for i in 0..<nbStreams {
            guard let s = ctx.pointee.streams[i], let cp = s.pointee.codecpar else { continue }
            if videoStreamIndex < 0 &&
                cp.pointee.codec_type == AVMEDIA_TYPE_VIDEO &&
                (cp.pointee.codec_id == AV_CODEC_ID_H264 || cp.pointee.codec_id == AV_CODEC_ID_HEVC) {
                videoStreamIndex = Int32(i)
                codecId = cp.pointee.codec_id
                stream = s
            } else if audioStreamIndex < 0 && cp.pointee.codec_type == AVMEDIA_TYPE_AUDIO {
                audioStreamIndex = Int32(i)
            }
        }
        guard videoStreamIndex >= 0, let videoStream = stream else {
            emitError(PlaybackEngineError.noVideoStream)
            return
        }
        logger.info("video stream index=\(videoStreamIndex) codec=\(codecId == AV_CODEC_ID_H264 ? "H.264" : "HEVC", privacy: .public)")

        guard let cp = videoStream.pointee.codecpar,
              let extraPtr = cp.pointee.extradata,
              cp.pointee.extradata_size > 0 else {
            emitError(PlaybackEngineError.missingExtradata)
            return
        }
        let extradata = Data(bytes: extraPtr, count: Int(cp.pointee.extradata_size))
        let isHEVC = (codecId == AV_CODEC_ID_HEVC)
        guard let parameterSets = Self.extractParameterSets(extradata: extradata, isHEVC: isHEVC) else {
            emitError(PlaybackEngineError.parameterSetParseFailed)
            return
        }

        let formatDesc: CMFormatDescription
        do {
            formatDesc = try Self.makeFormatDescription(parameterSets: parameterSets, isHEVC: isHEVC)
        } catch {
            emitError(error)
            return
        }

        let session: VTDecompressionSession
        do {
            session = try makeDecompressionSession(formatDesc: formatDesc)
        } catch {
            emitError(error)
            return
        }
        defer {
            VTDecompressionSessionWaitForAsynchronousFrames(session)
            VTDecompressionSessionInvalidate(session)
        }

        // ----- Audio decoder setup (optional) -----
        var audioCodecCtx: UnsafeMutablePointer<AVCodecContext>? = nil
        var swrCtx: OpaquePointer? = nil
        var audioOutChannels: Int = 0
        var audioOutSampleRate: Int = 0
        var audioFrame: UnsafeMutablePointer<AVFrame>? = nil
        if audioStreamIndex >= 0,
           let astream = ctx.pointee.streams[Int(audioStreamIndex)],
           let acp = astream.pointee.codecpar {
            if let codec = avcodec_find_decoder(acp.pointee.codec_id),
               let actx = avcodec_alloc_context3(codec) {
                if avcodec_parameters_to_context(actx, acp) >= 0,
                   avcodec_open2(actx, codec, nil) >= 0 {
                    let srcSR = Int(cffmpeg_codec_ctx_sample_rate(actx))
                    let srcCh = Int(cffmpeg_codec_ctx_channels(actx))
                    if srcSR > 0 && srcCh > 0 {
                        let outCh = min(2, srcCh)
                        var swr: OpaquePointer? = nil
                        let setup = cffmpeg_swr_setup_for_decoder(&swr, actx, Int32(srcSR), Int32(outCh), Int32(cffmpeg_av_sample_fmt_fltp()))
                        if setup >= 0, swr != nil {
                            swrCtx = swr
                            audioCodecCtx = actx
                            audioOutChannels = outCh
                            audioOutSampleRate = srcSR
                            audioFrame = av_frame_alloc()
                            setupAudioOutput(sampleRate: Double(srcSR), channels: outCh)
                            logger.info("audio decoder ready: codec_id=\(acp.pointee.codec_id.rawValue, privacy: .public) sr=\(srcSR, privacy: .public) ch=\(srcCh, privacy: .public) outCh=\(outCh, privacy: .public)")
                        } else {
                            var p: UnsafeMutablePointer<AVCodecContext>? = actx
                            avcodec_free_context(&p)
                            audioStreamIndex = -1
                            logger.error("swr setup failed (\(setup, privacy: .public)); audio disabled")
                        }
                    } else {
                        var p: UnsafeMutablePointer<AVCodecContext>? = actx
                        avcodec_free_context(&p)
                        audioStreamIndex = -1
                    }
                } else {
                    var p: UnsafeMutablePointer<AVCodecContext>? = actx
                    avcodec_free_context(&p)
                    audioStreamIndex = -1
                    logger.error("audio decoder open failed; audio disabled")
                }
            } else {
                audioStreamIndex = -1
                logger.notice("no decoder for audio codec id \(acp.pointee.codec_id.rawValue, privacy: .public)")
            }
        }
        defer {
            if audioFrame != nil {
                var f: UnsafeMutablePointer<AVFrame>? = audioFrame
                av_frame_free(&f)
            }
            if swrCtx != nil {
                var s: OpaquePointer? = swrCtx
                swr_free(&s)
            }
            if audioCodecCtx != nil {
                avcodec_free_context(&audioCodecCtx)
            }
            teardownAudioOutput()
        }

        emitStatus(.playing)
        logger.info("VTDecompressionSession created; entering demux loop")

        guard let packet = av_packet_alloc() else {
            emitError(PlaybackEngineError.readFailed(-1))
            return
        }
        defer {
            var p: UnsafeMutablePointer<AVPacket>? = packet
            av_packet_free(&p)
        }

        let timeBase = videoStream.pointee.time_base
        let nopts = cffmpeg_av_nopts_value()
        let eagain = cffmpeg_averror_eagain()
        var videoPacketCount: UInt64 = 0

        while !isCancelled {
            let r = av_read_frame(ctx, packet)
            if r < 0 {
                if r == eagain {
                    av_packet_unref(packet)
                    continue
                }
                emitError(PlaybackEngineError.readFailed(r))
                break
            }
            if audioStreamIndex >= 0,
               packet.pointee.stream_index == audioStreamIndex,
               let actx = audioCodecCtx,
               let swr = swrCtx,
               let aframe = audioFrame {
                if avcodec_send_packet(actx, packet) >= 0 {
                    while true {
                        let r = avcodec_receive_frame(actx, aframe)
                        if r == eagain || r == cffmpeg_averror_eof() { break }
                        if r < 0 { break }
                        decodeAndScheduleAudio(frame: aframe,
                                               swr: swr,
                                               outChannels: audioOutChannels,
                                               outSampleRate: audioOutSampleRate)
                    }
                }
                av_packet_unref(packet)
                continue
            }
            if packet.pointee.stream_index == videoStreamIndex {
                videoPacketCount &+= 1
                if videoPacketCount == 1 || videoPacketCount % 120 == 0 {
                    logger.info("video packets received: \(videoPacketCount, privacy: .public)")
                }
                let payload = Data(bytes: packet.pointee.data, count: Int(packet.pointee.size))
                let avcc = Self.annexBToAvcc(payload)
                let pts = Self.cmTime(from: packet.pointee.pts, fallback: packet.pointee.dts, nopts: nopts, timeBase: timeBase)
                let dts = Self.cmTime(from: packet.pointee.dts, fallback: packet.pointee.pts, nopts: nopts, timeBase: timeBase)
                let duration = packet.pointee.duration > 0
                    ? CMTime(value: CMTimeValue(packet.pointee.duration) * CMTimeValue(timeBase.num), timescale: CMTimeScale(timeBase.den))
                    : CMTime.invalid
                if let sample = Self.makeSampleBuffer(avccData: avcc, formatDesc: formatDesc, pts: pts, dts: dts, duration: duration) {
                    var infoFlags = VTDecodeInfoFlags()
                    let decodeFlags: VTDecodeFrameFlags = [._EnableAsynchronousDecompression]
                    let s = VTDecompressionSessionDecodeFrame(session, sampleBuffer: sample, flags: decodeFlags, frameRefcon: nil, infoFlagsOut: &infoFlags)
                    if s != noErr {
                        logger.error("VTDecompressionSessionDecodeFrame returned \(s)")
                    }
                }
            }
            av_packet_unref(packet)
        }
    }

    private func makeDecompressionSession(formatDesc: CMFormatDescription) throws -> VTDecompressionSession {
        let attrs: [CFString: Any] = [
            kCVPixelBufferPixelFormatTypeKey: Int(kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange),
            kCVPixelBufferMetalCompatibilityKey: true
        ]
        let spec: [CFString: Any] = [
            kVTVideoDecoderSpecification_EnableHardwareAcceleratedVideoDecoder: true
        ]
        let refCon = Unmanaged.passUnretained(self).toOpaque()
        var record = VTDecompressionOutputCallbackRecord(
            decompressionOutputCallback: PlaybackEngine_decompressionOutputCallback,
            decompressionOutputRefCon: refCon
        )
        var session: VTDecompressionSession?
        let status = VTDecompressionSessionCreate(
            allocator: kCFAllocatorDefault,
            formatDescription: formatDesc,
            decoderSpecification: spec as CFDictionary,
            imageBufferAttributes: attrs as CFDictionary,
            outputCallback: &record,
            decompressionSessionOut: &session
        )
        guard status == noErr, let session else {
            throw PlaybackEngineError.decompressionSessionFailed(status)
        }
        return session
    }

    // MARK: - Helpers

    private static func cmTime(from value: Int64, fallback: Int64, nopts: Int64, timeBase: AVRational) -> CMTime {
        let raw: Int64 = (value != nopts) ? value : (fallback != nopts ? fallback : nopts)
        guard raw != nopts else { return .invalid }
        let num = Int64(timeBase.num == 0 ? 1 : timeBase.num)
        let den = Int32(timeBase.den == 0 ? 1 : timeBase.den)
        return CMTime(value: CMTimeValue(raw * num), timescale: CMTimeScale(den))
    }

    static func annexBToAvcc(_ data: Data) -> Data {
        if data.count >= 4 {
            // Already AVCC if the first 4 bytes look like a length prefix consistent with the buffer.
            let len = (Int(data[0]) << 24) | (Int(data[1]) << 16) | (Int(data[2]) << 8) | Int(data[3])
            if len > 0 && len + 4 == data.count {
                // Heuristic: if the prefix exactly equals the rest of the buffer, treat as AVCC.
                return data
            }
        }
        var out = Data()
        out.reserveCapacity(data.count)
        var i = 0
        let n = data.count
        while i < n {
            var startCodeLen = 0
            if i + 4 <= n && data[i] == 0 && data[i+1] == 0 && data[i+2] == 0 && data[i+3] == 1 {
                startCodeLen = 4
            } else if i + 3 <= n && data[i] == 0 && data[i+1] == 0 && data[i+2] == 1 {
                startCodeLen = 3
            } else {
                // Not Annex-B; assume already AVCC.
                return data
            }
            let nalStart = i + startCodeLen
            var nalEnd = n
            var j = nalStart
            while j + 2 < n {
                if data[j] == 0 && data[j+1] == 0 {
                    if data[j+2] == 1 {
                        nalEnd = j; break
                    }
                    if j + 3 < n && data[j+2] == 0 && data[j+3] == 1 {
                        nalEnd = j; break
                    }
                }
                j += 1
            }
            let nalLen = nalEnd - nalStart
            var lenBE = UInt32(nalLen).bigEndian
            withUnsafeBytes(of: &lenBE) { out.append(contentsOf: $0) }
            out.append(data.subdata(in: nalStart..<nalEnd))
            i = nalEnd
        }
        return out
    }

    static func extractParameterSets(extradata: Data, isHEVC: Bool) -> [Data]? {
        guard !extradata.isEmpty else { return nil }
        let firstByte = extradata[0]
        if firstByte == 0x00 {
            return scanAnnexBNalUnits(extradata)
        }
        if isHEVC {
            return parseHVCC(extradata)
        }
        return parseAVCC(extradata)
    }

    private static func scanAnnexBNalUnits(_ data: Data) -> [Data]? {
        var sets: [Data] = []
        var i = 0
        let n = data.count
        while i < n {
            var startCodeLen = 0
            if i + 4 <= n && data[i] == 0 && data[i+1] == 0 && data[i+2] == 0 && data[i+3] == 1 {
                startCodeLen = 4
            } else if i + 3 <= n && data[i] == 0 && data[i+1] == 0 && data[i+2] == 1 {
                startCodeLen = 3
            } else {
                break
            }
            let nalStart = i + startCodeLen
            var nalEnd = n
            var j = nalStart
            while j + 2 < n {
                if data[j] == 0 && data[j+1] == 0 {
                    if data[j+2] == 1 {
                        nalEnd = j; break
                    }
                    if j + 3 < n && data[j+2] == 0 && data[j+3] == 1 {
                        nalEnd = j; break
                    }
                }
                j += 1
            }
            if nalEnd > nalStart {
                sets.append(data.subdata(in: nalStart..<nalEnd))
            }
            i = nalEnd
        }
        return sets.isEmpty ? nil : sets
    }

    private static func parseAVCC(_ data: Data) -> [Data]? {
        guard data.count >= 7 else { return nil }
        var offset = 5
        let numSPS = Int(data[offset] & 0x1F)
        offset += 1
        var sets: [Data] = []
        for _ in 0..<numSPS {
            guard offset + 2 <= data.count else { return nil }
            let size = (Int(data[offset]) << 8) | Int(data[offset + 1])
            offset += 2
            guard offset + size <= data.count else { return nil }
            sets.append(data.subdata(in: offset..<offset + size))
            offset += size
        }
        guard offset < data.count else { return nil }
        let numPPS = Int(data[offset])
        offset += 1
        for _ in 0..<numPPS {
            guard offset + 2 <= data.count else { return nil }
            let size = (Int(data[offset]) << 8) | Int(data[offset + 1])
            offset += 2
            guard offset + size <= data.count else { return nil }
            sets.append(data.subdata(in: offset..<offset + size))
            offset += size
        }
        return sets.isEmpty ? nil : sets
    }

    private static func parseHVCC(_ data: Data) -> [Data]? {
        guard data.count > 23 else { return nil }
        let numArrays = Int(data[22])
        var offset = 23
        var sets: [Data] = []
        for _ in 0..<numArrays {
            guard offset + 3 <= data.count else { return nil }
            offset += 1
            let numNalus = (Int(data[offset]) << 8) | Int(data[offset + 1])
            offset += 2
            for _ in 0..<numNalus {
                guard offset + 2 <= data.count else { return nil }
                let size = (Int(data[offset]) << 8) | Int(data[offset + 1])
                offset += 2
                guard offset + size <= data.count else { return nil }
                sets.append(data.subdata(in: offset..<offset + size))
                offset += size
            }
        }
        return sets.isEmpty ? nil : sets
    }

    static func makeFormatDescription(parameterSets: [Data], isHEVC: Bool) throws -> CMFormatDescription {
        let bufs: [UnsafeMutablePointer<UInt8>] = parameterSets.map { d in
            let p = UnsafeMutablePointer<UInt8>.allocate(capacity: d.count)
            d.copyBytes(to: p, count: d.count)
            return p
        }
        defer { bufs.forEach { $0.deallocate() } }
        let immutablePtrs = bufs.map { UnsafePointer($0) }
        let sizes = parameterSets.map { $0.count }
        var formatDesc: CMFormatDescription?
        let status = immutablePtrs.withUnsafeBufferPointer { ptrs -> OSStatus in
            sizes.withUnsafeBufferPointer { szs -> OSStatus in
                if isHEVC {
                    return CMVideoFormatDescriptionCreateFromHEVCParameterSets(
                        allocator: kCFAllocatorDefault,
                        parameterSetCount: parameterSets.count,
                        parameterSetPointers: ptrs.baseAddress!,
                        parameterSetSizes: szs.baseAddress!,
                        nalUnitHeaderLength: 4,
                        extensions: nil,
                        formatDescriptionOut: &formatDesc
                    )
                } else {
                    return CMVideoFormatDescriptionCreateFromH264ParameterSets(
                        allocator: kCFAllocatorDefault,
                        parameterSetCount: parameterSets.count,
                        parameterSetPointers: ptrs.baseAddress!,
                        parameterSetSizes: szs.baseAddress!,
                        nalUnitHeaderLength: 4,
                        formatDescriptionOut: &formatDesc
                    )
                }
            }
        }
        guard status == noErr, let formatDesc else {
            throw PlaybackEngineError.formatDescriptionFailed(status)
        }
        return formatDesc
    }

    static func makeSampleBuffer(avccData: Data, formatDesc: CMFormatDescription, pts: CMTime, dts: CMTime, duration: CMTime) -> CMSampleBuffer? {
        var blockBuffer: CMBlockBuffer?
        let bbStatus = CMBlockBufferCreateWithMemoryBlock(
            allocator: kCFAllocatorDefault,
            memoryBlock: nil,
            blockLength: avccData.count,
            blockAllocator: kCFAllocatorDefault,
            customBlockSource: nil,
            offsetToData: 0,
            dataLength: avccData.count,
            flags: kCMBlockBufferAssureMemoryNowFlag,
            blockBufferOut: &blockBuffer
        )
        guard bbStatus == kCMBlockBufferNoErr, let bb = blockBuffer else { return nil }
        let copyStatus = avccData.withUnsafeBytes { raw -> OSStatus in
            guard let base = raw.baseAddress else { return -1 }
            return CMBlockBufferReplaceDataBytes(
                with: base,
                blockBuffer: bb,
                offsetIntoDestination: 0,
                dataLength: avccData.count
            )
        }
        guard copyStatus == kCMBlockBufferNoErr else { return nil }

        var timing = CMSampleTimingInfo(duration: duration, presentationTimeStamp: pts, decodeTimeStamp: dts)
        var size = avccData.count
        var sampleBuffer: CMSampleBuffer?
        let s = CMSampleBufferCreateReady(
            allocator: kCFAllocatorDefault,
            dataBuffer: bb,
            formatDescription: formatDesc,
            sampleCount: 1,
            sampleTimingEntryCount: 1,
            sampleTimingArray: &timing,
            sampleSizeEntryCount: 1,
            sampleSizeArray: &size,
            sampleBufferOut: &sampleBuffer
        )
        guard s == noErr else { return nil }
        return sampleBuffer
    }
}

// C-compatible VTDecompressionOutputCallback. Routes the decoded frame back to the engine.
private let PlaybackEngine_decompressionOutputCallback: VTDecompressionOutputCallback = { (refCon, _, status, _, imageBuffer, pts, _) in
    guard status == noErr, let imageBuffer, let refCon else { return }
    let engine = Unmanaged<PlaybackEngine>.fromOpaque(refCon).takeUnretainedValue()
    engine.handleDecodedFrame(imageBuffer, pts: pts)
}
