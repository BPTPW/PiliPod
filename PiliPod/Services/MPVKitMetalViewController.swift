//
//  MPVKitMetalViewController.swift
//  PiliPod
//
//  Created by co on 2026/5/22.
//

import Foundation
import Libmpv
import UIKit

final class MPVKitMetalViewController: UIViewController {
    private var metalLayer = MPVKitMetalLayer()
    private var mpv: OpaquePointer?
    private var pendingHeaders: [String: String] = [:]
    private var pendingPlaybackSettings = AudioVideoSettingsStore.load()
    private var pendingVideoURL: URL?
    private var pendingAudioURL: URL?
    private var audioAdded = false
    private var isShuttingDown = false
    private var isInBackground = false
    private let eventQueue = DispatchQueue(label: "mpv.event", qos: .userInitiated)
    private let eventQueueKey = DispatchSpecificKey<Void>()
    private var wakeupContextPtr: UnsafeMutableRawPointer?

    /// Wraps a weak reference to the controller so the wakeup callback
    /// can safely detect deallocation without crashing.
    private final class WakeupContext {
        weak var controller: MPVKitMetalViewController?
        init(controller: MPVKitMetalViewController) {
            self.controller = controller
        }
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        eventQueue.setSpecific(key: eventQueueKey, value: ())

        syncMetalLayerLayout()
        metalLayer.framebufferOnly = true
        metalLayer.backgroundColor = UIColor.black.cgColor
        applyDynamicRangeLayerPreferences()

        view.layer.addSublayer(metalLayer)
        setupMpv()
        setupNotification()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        syncMetalLayerLayout()
    }

    /// Called from SwiftUI update cycle to ensure frame changes are pushed to
    /// the CAMetalLayer even when the controller instance is reused.
    func invalidateVideoLayout() {
        syncMetalLayerLayout()
        metalLayer.setNeedsLayout()
        metalLayer.layoutIfNeeded()
        view.setNeedsLayout()
        view.layoutIfNeeded()
    }

    private func syncMetalLayerLayout() {
        let bounds = view.bounds
        guard bounds.width > 0, bounds.height > 0 else { return }

        let scale = view.window?.screen.scale ?? UIScreen.main.scale
        view.contentScaleFactor = scale
        metalLayer.contentsScale = scale

        // Keep Metal layer pinned to the view's own coordinate space.
        // Non-zero bounds origins after SwiftUI layout transitions can make
        // video appear stuck at top-left if we mirror that origin to the layer.
        let width = bounds.size.width
        let height = bounds.size.height
        metalLayer.frame = CGRect(origin: .zero, size: CGSize(width: width, height: height))
        metalLayer.drawableSize = CGSize(
            width: (width * scale).rounded(.toNearestOrAwayFromZero),
            height: (height * scale).rounded(.toNearestOrAwayFromZero)
        )
    }

    func applyHTTPHeaders(_ headers: [String: String]) {
        pendingHeaders = headers
        guard let mpv else { return }

        setHTTPHeaders(mpv, headers: headers)
    }

    func applyPlaybackSettings(_ settings: AudioVideoSettings) {
        pendingPlaybackSettings = settings.clamped()
        applyDynamicRangeLayerPreferences()
    }

    private func setHTTPHeaders(_ mpv: OpaquePointer, headers: [String: String]) {
        if let userAgent = headers["User-Agent"], !userAgent.isEmpty {
            mpv_set_option_string(mpv, "user-agent", userAgent)
        }

        if let referer = headers["Referer"], !referer.isEmpty {
            mpv_set_option_string(mpv, "referrer", referer)
        }

        let headerPairs = headers
            .filter { key, _ in key != "User-Agent" && key != "Referer" }
            .map { "\($0.key): \($0.value)" }
            .joined(separator: "\r\n")

        if !headerPairs.isEmpty {
            mpv_set_option_string(mpv, "http-header-fields", headerPairs)
        }
    }

    func loadFile(_ url: URL) {
        audioAdded = false
        pendingVideoURL = url
        guard mpv != nil else { return }
        print("[mpv] loadfile \(url.absoluteString)")
        command("loadfile", args: [url.absoluteString, "replace"])
    }

    func addAudio(_ url: URL) {
        pendingAudioURL = url
    }

    private func addAudioIfLoaded(_ url: URL) {
        guard mpv != nil, !audioAdded else { return }
        audioAdded = true
        print("[mpv] audio-add \(url.absoluteString)")
        command("audio-add", args: [url.absoluteString])
    }

    func play() {
        setFlag(MPVKitProperty.pause, false)
    }

    func pause() {
        setFlag(MPVKitProperty.pause, true)
    }

    func setPlaybackRate(_ rate: Double) {
        setDouble(MPVKitProperty.playbackRate, rate)
    }

    func setKeepAspect(_ enabled: Bool) {
        guard let mpv else { return }
        let value = enabled ? "yes" : "no"
        checkError(
            mpv_set_property_string(mpv, "keepaspect", value),
            context: "set keepaspect=\(value)"
        )
    }

    /// Force mpv VO to rebind the current rendering surface size without
    /// recreating player instance or reloading stream.
    func refreshVideoOutput() {
        guard let mpv, !isShuttingDown else { return }
        checkError(mpv_set_property_string(mpv, "vid", "no"), context: "refresh vid=no")
        checkError(mpv_set_property_string(mpv, "vid", "auto"), context: "refresh vid=auto")
    }

    func stop() {
        command("stop")
    }

    func seek(to time: TimeInterval) {
        command("seek", args: [String(format: "%.1f", time), "absolute"])
    }

    func timePosition() -> TimeInterval {
        getDouble("time-pos")
    }

    func durationValue() -> TimeInterval {
        getDouble("duration")
    }

    func demuxerCacheTime() -> TimeInterval {
        getDouble("demuxer-cache-time")
    }

    func isPaused() -> Bool {
        getFlag(MPVKitProperty.pause)
    }

    private func setupMpv() {
        mpv = mpv_create()
        guard let mpv else {
            print("MPVKit: failed creating context")
            return
        }

#if DEBUG
        checkError(mpv_request_log_messages(mpv, "debug"), context: "mpv_request_log_messages")
#else
        checkError(mpv_request_log_messages(mpv, "no"), context: "mpv_request_log_messages")
#endif

        var wid = Int64(bitPattern: UInt64(UInt(bitPattern: Unmanaged.passUnretained(metalLayer).toOpaque())))
        checkError(mpv_set_option(mpv, "wid", MPV_FORMAT_INT64, &wid), context: "wid")
        checkError(mpv_set_option_string(mpv, "subs-match-os-language", "yes"), context: "subs-match-os-language")
        checkError(mpv_set_option_string(mpv, "subs-fallback", "yes"), context: "subs-fallback")
        checkError(mpv_set_option_string(mpv, "vo", "gpu-next"), context: "vo")
        checkError(mpv_set_option_string(mpv, "gpu-api", "vulkan"), context: "gpu-api")
        checkError(mpv_set_option_string(mpv, "gpu-context", "moltenvk"), context: "gpu-context")
        let hwdecValue = pendingPlaybackSettings.hardwareDecodingEnabled ? "videotoolbox" : "no"
        checkError(mpv_set_option_string(mpv, "hwdec", hwdecValue), context: "hwdec")
        applyHDRRenderingOptions(to: mpv, settings: pendingPlaybackSettings)
        checkError(mpv_set_option_string(mpv, "cache", "auto"), context: "cache")
        checkError(
            mpv_set_option_string(mpv, "autosync", "\(pendingPlaybackSettings.autosync)"),
            context: "autosync"
        )
        checkError(
            mpv_set_option_string(mpv, "video-sync", pendingPlaybackSettings.videoSync.rawValue),
            context: "video-sync"
        )
        if let bufferValue = pendingPlaybackSettings.bufferSize.mpvByteString {
            checkError(
                mpv_set_option_string(mpv, "demuxer-max-bytes", bufferValue),
                context: "demuxer-max-bytes"
            )
            checkError(
                mpv_set_option_string(mpv, "demuxer-max-back-bytes", bufferValue),
                context: "demuxer-max-back-bytes"
            )
        }
        checkError(mpv_set_option_string(mpv, "video-rotate", "no"), context: "video-rotate")
        checkError(mpv_set_option_string(mpv, "keep-open", "yes"), context: "keep-open")
        if !pendingHeaders.isEmpty {
            setHTTPHeaders(mpv, headers: pendingHeaders)
        }
        let lavfOptions = "protocol_whitelist=file,http,https,tcp,tls,crypto"
        let lavfStatus = mpv_set_option_string(mpv, "demuxer-lavf-o-append", lavfOptions)
        if lavfStatus < 0 {
            print("MPV API warn [demuxer-lavf-o-append]: \(String(cString: mpv_error_string(lavfStatus)))")
        }

        checkError(mpv_initialize(mpv), context: "mpv_initialize")

        mpv_observe_property(mpv, 0, "time-pos", MPV_FORMAT_DOUBLE)
        mpv_observe_property(mpv, 0, "duration", MPV_FORMAT_DOUBLE)
        mpv_observe_property(mpv, 0, "video-params/w", MPV_FORMAT_INT64)
        mpv_observe_property(mpv, 0, "video-params/h", MPV_FORMAT_INT64)
        mpv_observe_property(mpv, 0, "video-params/codec", MPV_FORMAT_STRING)
        mpv_observe_property(mpv, 0, "audio-params/codec", MPV_FORMAT_STRING)
        mpv_observe_property(mpv, 0, "paused-for-cache", MPV_FORMAT_FLAG)

        setupWakeupCallback(mpv)

        if let video = pendingVideoURL {
            loadFile(video)
        }
        if let audio = pendingAudioURL {
            addAudio(audio)
        }
    }

    private func applyHDRRenderingOptions(to mpv: OpaquePointer, settings: AudioVideoSettings) {
        let toneMapping = settings.hdrToneMapping == .auto ? "auto" : settings.hdrToneMapping.rawValue
        checkError(
            mpv_set_option_string(mpv, "tone-mapping", toneMapping),
            context: "tone-mapping"
        )
        checkError(
            mpv_set_option_string(
                mpv,
                "target-colorspace-hint",
                settings.highDynamicRangeEnabled ? "yes" : "no"
            ),
            context: "target-colorspace-hint"
        )
        checkError(
            mpv_set_option_string(
                mpv,
                "hdr-compute-peak",
                settings.highDynamicRangeEnabled ? "yes" : "no"
            ),
            context: "hdr-compute-peak"
        )
    }

    private func applyDynamicRangeLayerPreferences() {
        let enableExtendedRange = pendingPlaybackSettings.highDynamicRangeEnabled
            && pendingPlaybackSettings.prefersEDROutput
            && screenPotentialEDRHeadroom() > 1.0

        metalLayer.wantsExtendedDynamicRangeContent = enableExtendedRange
        metalLayer.colorspace = preferredDisplayColorSpace(useExtendedRange: enableExtendedRange)
    }

    private func preferredDisplayColorSpace(useExtendedRange: Bool) -> CGColorSpace? {
        if useExtendedRange {
            return CGColorSpace(name: CGColorSpace.extendedLinearDisplayP3)
                ?? CGColorSpace(name: CGColorSpace.extendedLinearSRGB)
        }
        return CGColorSpace(name: CGColorSpace.sRGB)
    }

    private func activeScreen() -> UIScreen? {
        view.window?.screen ?? view.window?.windowScene?.screen ?? UIScreen.main
    }

    private func screenCurrentEDRHeadroom() -> CGFloat {
        guard let screen = activeScreen() else { return 1.0 }
        if #available(iOS 16.0, *) {
            return screen.currentEDRHeadroom
        }
        return 1.0
    }

    private func screenPotentialEDRHeadroom() -> CGFloat {
        guard let screen = activeScreen() else { return 1.0 }
        if #available(iOS 16.0, *) {
            return screen.potentialEDRHeadroom
        }
        return 1.0
    }

    private func displayGamutDescription() -> String {
        switch traitCollection.displayGamut {
        case .P3:
            return "P3"
        case .SRGB:
            return "sRGB"
        default:
            return "unspecified"
        }
    }

    private func setupWakeupCallback(_ mpv: OpaquePointer) {
        let ctx = WakeupContext(controller: self)
        let ptr = Unmanaged.passRetained(ctx).toOpaque()
        wakeupContextPtr = ptr

        mpv_set_wakeup_callback(mpv, { rawPtr in
            guard let rawPtr = rawPtr else { return }
            let ctx = Unmanaged<WakeupContext>.fromOpaque(rawPtr).takeUnretainedValue()
            guard let controller = ctx.controller else { return }
            DispatchQueue.main.async {
                controller.readEvents()
            }
        }, ptr)
    }

    private func readEvents() {
        guard !isShuttingDown else { return }
        eventQueue.async { [weak self] in
            guard let self, !self.isShuttingDown, !self.isInBackground, let mpv = self.mpv else { return }

            while true {
                guard let event = mpv_wait_event(mpv, 0) else { break }
                let eventId = event.pointee.event_id

                if eventId == MPV_EVENT_NONE { break }

                switch eventId {
                case MPV_EVENT_LOG_MESSAGE:
                    let msg = UnsafeMutablePointer<mpv_event_log_message>(OpaquePointer(event.pointee.data))
                    if let msg {
                        print("[mpv][\(String(cString: msg.pointee.level))] \(String(cString: msg.pointee.text))", terminator: "")
                    }
                case MPV_EVENT_START_FILE:
                    print("[mpv] start file")
                case MPV_EVENT_FILE_LOADED:
                    print("[mpv] file loaded")
                    DispatchQueue.main.async { self.dumpState() }
                    if let audio = self.pendingAudioURL {
                        DispatchQueue.main.async { self.addAudioIfLoaded(audio) }
                    }
                case MPV_EVENT_VIDEO_RECONFIG:
                    print("[mpv] video reconfig")
                case MPV_EVENT_AUDIO_RECONFIG:
                    print("[mpv] audio reconfig")
                case MPV_EVENT_END_FILE:
                    let end = UnsafeMutablePointer<mpv_event_end_file>(OpaquePointer(event.pointee.data))
                    if let end {
                        print("[mpv] end file reason=\(end.pointee.reason) error=\(end.pointee.error)")
                    }
                default:
                    break
                }
            }
        }
    }

    private func dumpState() {
        guard let mpv else { return }
        let path = mpv_get_property_string(mpv, "path").flatMap { String(cString: $0) } ?? "(nil)"
        let vo = mpv_get_property_string(mpv, "vo").flatMap { String(cString: $0) } ?? "(nil)"
        let hwdec = mpv_get_property_string(mpv, "hwdec-current").flatMap { String(cString: $0) } ?? "(nil)"
        let vid = mpv_get_property_string(mpv, "vid").flatMap { String(cString: $0) } ?? "(nil)"
        let aid = mpv_get_property_string(mpv, "aid").flatMap { String(cString: $0) } ?? "(nil)"
        print("[mpv] state path=\(path) vo=\(vo) hwdec=\(hwdec) vid=\(vid) aid=\(aid)")
    }

    private func setupNotification() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(enterBackground),
            name: UIApplication.didEnterBackgroundNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(enterForeground),
            name: UIApplication.willEnterForegroundNotification,
            object: nil
        )
    }

    @objc private func enterBackground() {
        guard !isShuttingDown, let mpv else { return }
        isInBackground = true
        print("[mpv] entering background, disabling video output")

        // Disable the video track in background to avoid touching invalid GPU resources,
        // but keep the playback state decision in the higher-level view logic.
        checkError(mpv_set_option_string(mpv, "vid", "no"), context: "vid")
    }

    @objc private func enterForeground() {
        guard !isShuttingDown, let mpv else { return }
        print("[mpv] entering foreground, restoring video")

        // Re-enable video output and preserve whichever play/pause state the app decided on.
        checkError(mpv_set_option_string(mpv, "vid", "auto"), context: "vid")

        isInBackground = false
    }

    private func getDouble(_ name: String) -> Double {
        guard let mpv else { return 0.0 }
        var data = Double()
        mpv_get_property(mpv, name, MPV_FORMAT_DOUBLE, &data)
        return data
    }

    private func getString(_ name: String) -> String {
        guard let mpv else { return "" }
        return mpv_get_property_string(mpv, name).flatMap { String(cString: $0) } ?? ""
    }

    func videoCodec() -> String { getString("video-codec") }
    func audioCodec() -> String { getString("audio-codec") }
    func hwdecCurrent() -> String { getString("hwdec-current") }
    func videoPixelFormat() -> String { getString("video-params/pixelformat") }
    func videoHardwarePixelFormat() -> String { getString("video-out-params/hw-pixelformat") }
    func videoPrimaries() -> String { getString("video-params/primaries") }
    func videoGamma() -> String { getString("video-params/gamma") }
    func videoSignalPeak() -> String { getString("video-params/sig-peak") }
    func videoColorLevels() -> String { getString("video-params/colorlevels") }
    func videoColorMatrix() -> String { getString("video-params/colormatrix") }
    func currentToneMapping() -> String { getString("tone-mapping") }
    func isExtendedDynamicRangeRequested() -> Bool { metalLayer.wantsExtendedDynamicRangeContent }
    func displayColorSpaceName() -> String { metalLayer.colorspace?.name as String? ?? "" }
    func currentEDRHeadroom() -> CGFloat { screenCurrentEDRHeadroom() }
    func potentialEDRHeadroom() -> CGFloat { screenPotentialEDRHeadroom() }
    func displayGamut() -> String { displayGamutDescription() }

    private func getFlag(_ name: String) -> Bool {
        guard let mpv else { return false }
        var data = Int64()
        mpv_get_property(mpv, name, MPV_FORMAT_FLAG, &data)
        return data > 0
    }

    private func setFlag(_ name: String, _ flag: Bool) {
        guard let mpv else { return }
        var data: Int = flag ? 1 : 0
        mpv_set_property(mpv, name, MPV_FORMAT_FLAG, &data)
    }

    private func setDouble(_ name: String, _ value: Double) {
        guard let mpv else { return }
        var data = value
        mpv_set_property(mpv, name, MPV_FORMAT_DOUBLE, &data)
    }

    private func command(_ command: String, args: [String?] = []) {
        guard let mpv else { return }
        var cargs = makeCArgs(command, args).map { $0.flatMap { UnsafePointer<CChar>(strdup($0)) } }
        defer {
            for ptr in cargs where ptr != nil {
                free(UnsafeMutablePointer(mutating: ptr))
            }
        }
        checkError(mpv_command(mpv, &cargs), context: "mpv_command(\(command))")
    }

    private func makeCArgs(_ command: String, _ args: [String?]) -> [String?] {
        if !args.isEmpty, args.last == nil {
            fatalError("Command does not need a nil suffix")
        }

        var strArgs = args
        strArgs.insert(command, at: 0)
        strArgs.append(nil)

        return strArgs
    }

    private func checkError(_ status: CInt, context: String) {
        if status < 0 {
            print("MPV API error [\(context)]: \(String(cString: mpv_error_string(status)))")
        }
    }

    private func shutdownMpvIfNeeded() {
        guard let mpv else { return }

        isShuttingDown = true
        isInBackground = true

        // 1) Stop playback immediately — this tells the VO to stop rendering.
        mpv_command_string(mpv, "stop")

        // 2) Drain any queued event processing before touching the context.
        eventQueue.sync {}

        // 3) Detach wakeup callback so no future callbacks can fire.
        //    In-flight callbacks are safe because WakeupContext.controller is weak.
        mpv_set_wakeup_callback(mpv, nil, nil)

        // 4) Drain again — a wakeup might already be in-flight on the main
        //    dispatch queue, so this gives it a chance to land harmlessly.
        eventQueue.sync {}

        // 5) One more sync on main to ensure any DispatchQueue.main.async
        //    from readEvents() or setupWakeupCallback has finished.
        if !Thread.isMainThread {
            DispatchQueue.main.sync {}
        }

        self.mpv = nil
        mpv_terminate_destroy(mpv)

        // 6) Release retained WakeupContext — safe now because
        //    mpv_terminate_destroy blocks until all internal threads exit.
        if let ptr = wakeupContextPtr {
            Unmanaged<WakeupContext>.fromOpaque(ptr).release()
            wakeupContextPtr = nil
        }
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
        shutdownMpvIfNeeded()
    }
}

private enum MPVKitProperty {
    static let pause = "pause"
    static let playbackRate = "speed"
}

final class MPVKitMetalLayer: CAMetalLayer {
    override var drawableSize: CGSize {
        get { super.drawableSize }
        set {
            if Int(newValue.width) > 1 && Int(newValue.height) > 1 {
                super.drawableSize = newValue
            }
        }
    }

    override var wantsExtendedDynamicRangeContent: Bool {
        get { super.wantsExtendedDynamicRangeContent }
        set {
            if Thread.isMainThread {
                super.wantsExtendedDynamicRangeContent = newValue
            } else {
                DispatchQueue.main.sync {
                    super.wantsExtendedDynamicRangeContent = newValue
                }
            }
        }
    }
}
