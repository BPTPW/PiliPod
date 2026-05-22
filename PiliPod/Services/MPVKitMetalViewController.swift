//
//  MPVKitMetalViewController.swift
//  PiliPod
//
//  Created by co on 2026/5/22.
//

import Foundation
import UIKit
import Libmpv

final class MPVKitMetalViewController: UIViewController {
    private var metalLayer = MPVKitMetalLayer()
    private var mpv: OpaquePointer?
    private var pendingHeaders: [String: String] = [:]

    override func viewDidLoad() {
        super.viewDidLoad()

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

        let headerPairs = headers
            .filter { key, _ in key != "User-Agent" }
            .map { "\($0.key): \($0.value)" }
            .joined(separator: "|")

        if !headerPairs.isEmpty {
            mpv_set_option_string(mpv, "http-header-fields", headerPairs)
        }
    }

    func loadFile(_ url: URL) {
        command("loadfile", args: [url.absoluteString, "replace"])
    }

    func addAudio(_ url: URL) {
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

    deinit {
        NotificationCenter.default.removeObserver(self)
        if let mpv {
            mpv_terminate_destroy(mpv)
        }
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
