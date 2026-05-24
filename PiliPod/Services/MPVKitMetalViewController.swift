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
    private var pendingVideoURL: URL?
    private var pendingAudioURL: URL?
    private var audioAdded = false
    private var isShuttingDown = false
    private let eventQueue = DispatchQueue(label: "mpv.event", qos: .userInitiated)
    private let eventQueueKey = DispatchSpecificKey<Void>()

    override func viewDidLoad() {
        super.viewDidLoad()

        eventQueue.setSpecific(key: eventQueueKey, value: ())

        metalLayer.frame = view.frame
        metalLayer.contentsScale = UIScreen.main.nativeScale
        metalLayer.framebufferOnly = true
        metalLayer.backgroundColor = UIColor.black.cgColor

        view.layer.addSublayer(metalLayer)
        setupMpv()
        setupNotification()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        metalLayer.frame = view.frame
    }

    func applyHTTPHeaders(_ headers: [String: String]) {
        pendingHeaders = headers
        guard let mpv else { return }

        setHTTPHeaders(mpv, headers: headers)
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
        checkError(mpv_set_option_string(mpv, "hwdec", "videotoolbox"), context: "hwdec")
        checkError(mpv_set_option_string(mpv, "video-rotate", "no"), context: "video-rotate")
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

    private func setupWakeupCallback(_ mpv: OpaquePointer) {
        mpv_set_wakeup_callback(mpv, { ctx in
            guard let ctx = ctx else { return }

            let controller = Unmanaged<MPVKitMetalViewController>
                .fromOpaque(ctx)
                .takeUnretainedValue()

            DispatchQueue.main.async {
                controller.readEvents()
            }

        }, UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque()))
    }

    private func readEvents() {
        eventQueue.async { [weak self] in
            guard let self, !self.isShuttingDown, let mpv = self.mpv else { return }

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
        pause()
        if let mpv {
            checkError(mpv_set_option_string(mpv, "vid", "no"), context: "vid")
        }
    }

    @objc private func enterForeground() {
        if let mpv {
            checkError(mpv_set_option_string(mpv, "vid", "auto"), context: "vid")
        }
        play()
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

        // Ensure no more wakeups can call back into this instance.
        mpv_set_wakeup_callback(mpv, nil, nil)
        mpv_wakeup(mpv)

        // Drain any in-flight event processing before destroying the context.
        if DispatchQueue.getSpecific(key: eventQueueKey) == nil {
            eventQueue.sync {
                // Intentionally empty; `sync` waits for queued work to finish.
            }
        }

        self.mpv = nil
        mpv_terminate_destroy(mpv)
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
        shutdownMpvIfNeeded()
    }
}

private enum MPVKitProperty {
    static let pause = "pause"
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
