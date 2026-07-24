//
//  MPVKitOpenGLViewController.swift
//  PiliPod
//
//  Live streams use libmpv's render API instead of the `wid` embedder. This
//  makes a UIKit size change a normal redraw and avoids rebuilding FLV tracks.
//

import Foundation
import GLKit
import Libmpv
import UIKit

final class MPVKitOpenGLViewController: GLKViewController, MPVPlaybackController {
    private var mpv: OpaquePointer?
    private var renderContext: OpaquePointer?
    private var pendingHeaders: [String: String] = [:]
    private var pendingPlaybackSettings = AudioVideoSettingsStore.load()
    private var pendingVideoURL: URL?
    private var isShuttingDown = false
    private var defaultFBO: GLint = 0
    private var renderInvalidationScheduled = false
    private let renderInvalidationLock = NSLock()
    private let eventQueue = DispatchQueue(label: "mpv.live.event", qos: .utility)

    override func loadView() {
        view = GLKView(frame: .zero)
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        guard let context = EAGLContext(api: .openGLES2), let glView = view as? GLKView else {
            assertionFailure("Unable to create the OpenGL ES context for live playback")
            return
        }

        glView.context = context
        glView.drawableColorFormat = .RGBA8888
        glView.drawableDepthFormat = .formatNone
        glView.enableSetNeedsDisplay = true
        isPaused = true
        EAGLContext.setCurrent(context)
        setupMpv()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        (view as? GLKView)?.setNeedsDisplay()
    }

    func applyHTTPHeaders(_ headers: [String: String]) {
        pendingHeaders = headers
        guard let mpv else { return }
        setHTTPHeaders(mpv, headers: headers)
    }

    func applyPlaybackSettings(_ settings: AudioVideoSettings) {
        // The OpenGL render API is intentionally SDR for live playback. It is
        // reliable for ordinary 8-bit FLV/H.264 streams but unsuitable for HDR.
        pendingPlaybackSettings = settings.clamped()
    }

    func setAllowsViewportVideoRebind(_ enabled: Bool) {
        // Render API redraws directly into GLKView's current viewport.
        _ = enabled
    }

    func loadFile(_ url: URL) {
        pendingVideoURL = url
        guard mpv != nil else { return }
        command("loadfile", args: [url.absoluteString, "replace"])
    }

    func addAudio(_ url: URL) { _ = url }
    func play() { setFlag("pause", false) }
    func pause() { setFlag("pause", true) }
    func setPlaybackRate(_ rate: Double) { setDouble("speed", rate) }
    func stop() { command("stop") }
    func seek(to time: TimeInterval) { command("seek", args: [String(format: "%.1f", time), "absolute"]) }
    func timePosition() -> TimeInterval { getDouble("time-pos") }
    func durationValue() -> TimeInterval { getDouble("duration") }
    func demuxerCacheTime() -> TimeInterval { getDouble("demuxer-cache-time") }
    func cacheSpeedBytesPerSecond() -> Double { getDouble("cache-speed") }
    func downloadSpeedBytesPerSecond() -> Double { getDouble("download-speed") }
    func isPaused() -> Bool { getFlag("pause") }
    func isPausedForCache() -> Bool { getFlag("paused-for-cache") }

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
    func currentToneMapping() -> String { "SDR (live render API)" }
    func isExtendedDynamicRangeRequested() -> Bool { false }
    func displayColorSpaceName() -> String { "sRGB" }
    func currentEDRHeadroom() -> CGFloat { 1.0 }
    func potentialEDRHeadroom() -> CGFloat { 1.0 }
    func displayGamut() -> String { "sRGB" }

    override func glkView(_ view: GLKView, drawIn rect: CGRect) {
        guard let renderContext else { return }

        glClearColor(0, 0, 0, 1)
        glClear(UInt32(GL_COLOR_BUFFER_BIT))
        glGetIntegerv(GLenum(GL_FRAMEBUFFER_BINDING), &defaultFBO)

        var viewport = [GLint](repeating: 0, count: 4)
        glGetIntegerv(GLenum(GL_VIEWPORT), &viewport)
        guard viewport[2] > 0, viewport[3] > 0 else { return }

        var fbo = mpv_opengl_fbo(
            fbo: Int32(defaultFBO),
            w: Int32(viewport[2]),
            h: Int32(viewport[3]),
            internal_format: 0
        )
        var flipY: CInt = 1
        withUnsafeMutablePointer(to: &fbo) { fboPointer in
            withUnsafeMutablePointer(to: &flipY) { flipPointer in
                var params = [
                    mpv_render_param(type: MPV_RENDER_PARAM_OPENGL_FBO, data: fboPointer),
                    mpv_render_param(type: MPV_RENDER_PARAM_FLIP_Y, data: flipPointer),
                    mpv_render_param()
                ]
                mpv_render_context_render(renderContext, &params)
            }
        }
    }

    private func setupMpv() {
        guard let glView = view as? GLKView else { return }
        let glContext = glView.context
        EAGLContext.setCurrent(glContext)
        guard let mpv = mpv_create() else {
            print("MPVKit: failed creating live render context")
            return
        }
        self.mpv = mpv

        // Live streams can produce a high volume of decoder/render messages.
        // Keeping this quiet prevents console I/O from competing with gestures.
        checkError(mpv_request_log_messages(mpv, "no"), context: "mpv_request_log_messages")
        checkError(mpv_set_option_string(mpv, "vo", "libmpv"), context: "vo")
#if targetEnvironment(simulator)
        checkError(mpv_set_option_string(mpv, "hwdec", "no"), context: "hwdec")
#else
        let hwdec = pendingPlaybackSettings.hardwareDecodingEnabled ? "videotoolbox" : "no"
        checkError(mpv_set_option_string(mpv, "hwdec", hwdec), context: "hwdec")
#endif
        checkError(mpv_set_option_string(mpv, "cache", "auto"), context: "cache")
        checkError(mpv_set_option_string(mpv, "video-rotate", "no"), context: "video-rotate")
        checkError(mpv_set_option_string(mpv, "keep-open", "yes"), context: "keep-open")
        checkError(mpv_set_option_string(mpv, "network-timeout", "10"), context: "network-timeout")
        setHTTPHeaders(mpv, headers: pendingHeaders)
        let lavfOptions = [
            "protocol_whitelist=file,http,https,tcp,tls,crypto",
            "reconnect=1",
            "reconnect_streamed=1",
            "reconnect_on_network_error=1",
            "reconnect_delay_max=2"
        ].joined(separator: ",")
        checkError(mpv_set_option_string(mpv, "demuxer-lavf-o-append", lavfOptions), context: "demuxer-lavf-o-append")
        checkError(mpv_initialize(mpv), context: "mpv_initialize")

        let api = UnsafeMutableRawPointer(mutating: (MPV_RENDER_API_TYPE_OPENGL as NSString).utf8String)
        var initParams = mpv_opengl_init_params(
            get_proc_address: mpvLiveGetProcAddress,
            get_proc_address_ctx: nil
        )
        withUnsafeMutablePointer(to: &initParams) { initParamsPointer in
            var params = [
                mpv_render_param(type: MPV_RENDER_PARAM_API_TYPE, data: api),
                mpv_render_param(type: MPV_RENDER_PARAM_OPENGL_INIT_PARAMS, data: initParamsPointer),
                mpv_render_param()
            ]
            let status = mpv_render_context_create(&renderContext, mpv, &params)
            checkError(status, context: "mpv_render_context_create")
        }
        guard let renderContext else { return }
        mpv_render_context_set_update_callback(renderContext, { context in
            guard let context else { return }
            let controller = Unmanaged<MPVKitOpenGLViewController>.fromOpaque(context).takeUnretainedValue()
            controller.scheduleRenderInvalidation()
        }, Unmanaged.passUnretained(self).toOpaque())

        mpv_set_wakeup_callback(mpv, { context in
            guard let context else { return }
            let controller = Unmanaged<MPVKitOpenGLViewController>.fromOpaque(context).takeUnretainedValue()
            controller.eventQueue.async { [weak controller] in controller?.drainEvents() }
        }, Unmanaged.passUnretained(self).toOpaque())

        if let pendingVideoURL { loadFile(pendingVideoURL) }
    }

    private func drainEvents() {
        guard !isShuttingDown, let mpv else { return }
        while let event = mpv_wait_event(mpv, 0), event.pointee.event_id != MPV_EVENT_NONE {
            if event.pointee.event_id == MPV_EVENT_LOG_MESSAGE {
                continue
            }
        }
    }

    private func scheduleRenderInvalidation() {
        renderInvalidationLock.lock()
        defer { renderInvalidationLock.unlock() }
        guard !isShuttingDown, !renderInvalidationScheduled else { return }
        renderInvalidationScheduled = true
        DispatchQueue.main.async { [weak self] in
            guard let self, !self.isShuttingDown else { return }
            self.renderInvalidationLock.lock()
            self.renderInvalidationScheduled = false
            self.renderInvalidationLock.unlock()
            (self.view as? GLKView)?.setNeedsDisplay()
        }
    }

    private func setHTTPHeaders(_ mpv: OpaquePointer, headers: [String: String]) {
        if let userAgent = headers["User-Agent"], !userAgent.isEmpty {
            checkError(mpv_set_option_string(mpv, "user-agent", userAgent), context: "user-agent")
        }
        if let referer = headers["Referer"], !referer.isEmpty {
            checkError(mpv_set_option_string(mpv, "referrer", referer), context: "referrer")
        }
        let fields = headers
            .filter { $0.key != "User-Agent" && $0.key != "Referer" }
            .map { "\($0.key): \($0.value)" }
            .joined(separator: "\r\n")
        if !fields.isEmpty {
            checkError(mpv_set_option_string(mpv, "http-header-fields", fields), context: "http-header-fields")
        }
    }

    private func getDouble(_ name: String) -> Double {
        guard let mpv else { return 0 }
        var value = Double()
        mpv_get_property(mpv, name, MPV_FORMAT_DOUBLE, &value)
        return value
    }

    private func getString(_ name: String) -> String {
        guard let mpv else { return "" }
        return mpv_get_property_string(mpv, name).flatMap { String(cString: $0) } ?? ""
    }

    private func getFlag(_ name: String) -> Bool {
        guard let mpv else { return false }
        var value = Int64()
        mpv_get_property(mpv, name, MPV_FORMAT_FLAG, &value)
        return value > 0
    }

    private func setFlag(_ name: String, _ value: Bool) {
        guard let mpv else { return }
        var flag: CInt = value ? 1 : 0
        mpv_set_property(mpv, name, MPV_FORMAT_FLAG, &flag)
    }

    private func setDouble(_ name: String, _ value: Double) {
        guard let mpv else { return }
        var value = value
        mpv_set_property(mpv, name, MPV_FORMAT_DOUBLE, &value)
    }

    private func command(_ command: String, args: [String] = []) {
        guard let mpv else { return }
        var stringArguments: [String?] = [command] + args
        stringArguments.append(nil)
        var values = stringArguments.map { value in
            value.flatMap { UnsafePointer<CChar>(strdup($0)) }
        }
        defer { values.compactMap { $0 }.forEach { free(UnsafeMutablePointer(mutating: $0)) } }
        checkError(mpv_command(mpv, &values), context: "mpv_command(\(command))")
    }

    private func checkError(_ status: CInt, context: String) {
        if status < 0 {
            print("MPV API error [\(context)]: \(String(cString: mpv_error_string(status)))")
        }
    }

    private func shutdownMpvIfNeeded() {
        guard let mpv else { return }
        isShuttingDown = true
        mpv_set_wakeup_callback(mpv, nil, nil)
        eventQueue.sync {}
        if let renderContext {
            mpv_render_context_set_update_callback(renderContext, nil, nil)
            mpv_render_context_free(renderContext)
            self.renderContext = nil
        }
        self.mpv = nil
        mpv_terminate_destroy(mpv)
    }

    deinit { shutdownMpvIfNeeded() }
}

private func mpvLiveGetProcAddress(
    _: UnsafeMutableRawPointer?,
    _ name: UnsafePointer<CChar>?
) -> UnsafeMutableRawPointer? {
    guard let name else { return nil }
    let symbol = CFStringCreateWithCString(kCFAllocatorDefault, name, CFStringBuiltInEncodings.ASCII.rawValue)
    let bundle = CFBundleGetBundleWithIdentifier("com.apple.opengles" as CFString)
    return CFBundleGetFunctionPointerForName(bundle, symbol)
}
