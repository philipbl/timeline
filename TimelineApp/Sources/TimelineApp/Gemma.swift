import CoreGraphics
import CryptoKit
import Foundation
import llama

/// The on-device Gemma 4 E4B model used for image import: the files on disk,
/// their download, and Settings-facing state. Inference lives in
/// `GemmaRunner`.
@MainActor
final class GemmaModel: NSObject, ObservableObject, URLSessionDownloadDelegate {
    static let shared = GemmaModel()

    enum State: Equatable {
        case missing
        case downloading(Double)  // 0...1 across both files
        case verifying
        case ready
        case failed(String)
    }

    @Published private(set) var state: State = .missing

    nonisolated struct File: Sendable {
        let name: String
        let size: Int64
        let sha256: String
    }

    // Pinned to one revision of the official ggml-org conversion so the
    // checksums stay valid.
    private static let revision = "a69f018d7678a2b9f5e705f8903d6fb29b9b25dc"
    nonisolated static let weights = File(
        name: "gemma-4-E4B-it-Q4_0.gguf", size: 4_590_807_392,
        sha256: "a555b900214b477d8880e7832e0b8925e139b0159640036b09fe472b6f2097f2")
    nonisolated static let projector = File(
        name: "mmproj-gemma-4-E4B-it-Q8_0.gguf", size: 559_874_816,
        sha256: "197f49a93027f9843772bd24a6a9e0be2a32a788de5a3def330e9c585d86edd1")
    private static let files = [projector, weights]
    static let downloadSize = files.reduce(0) { $0 + $1.size }

    /// Gemma runs on Apple silicon only; Intel Macs use the basic importer.
    static var isSupported: Bool {
        #if arch(arm64)
        return true
        #else
        return false
        #endif
    }

    /// The user declined the download prompt; later drops use the basic
    /// importer without asking again (Settings can still download).
    static let declinedKey = "gemmaDownloadDeclined"

    nonisolated static var directory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Timeline/Models", isDirectory: true)
    }

    nonisolated static func url(_ file: File) -> URL {
        directory.appendingPathComponent(file.name)
    }

    private var session: URLSession?
    private var resumeData: Data?
    private var continuation: CheckedContinuation<URL, Error>?
    private var completedBytes: Int64 = 0

    override init() {
        super.init()
        state = Self.filesPresent ? .ready : .missing
    }

    /// Both files on disk at the expected size (hashes are checked once, at
    /// download time).
    private static var filesPresent: Bool {
        files.allSatisfy {
            let size = (try? FileManager.default.attributesOfItem(
                atPath: url($0).path)[.size] as? Int64) ?? nil
            return size == $0.size
        }
    }

    var isBusy: Bool {
        switch state {
        case .downloading, .verifying: return true
        default: return false
        }
    }

    /// Download and verify both files. Safe to call when already ready or
    /// in progress (returns once the current attempt settles).
    func download() async {
        guard !isBusy else {
            while isBusy { try? await Task.sleep(for: .milliseconds(250)) }
            return
        }
        guard state != .ready else { return }
        UserDefaults.standard.removeObject(forKey: Self.declinedKey)
        do {
            try FileManager.default.createDirectory(
                at: Self.directory, withIntermediateDirectories: true)
            completedBytes = 0
            for file in Self.files {
                let destination = Self.url(file)
                if Self.fileSize(destination) != file.size {
                    state = .downloading(progress(0))
                    let temp = try await fetch(file)
                    state = .verifying
                    guard await Self.sha256(of: temp) == file.sha256 else {
                        try? FileManager.default.removeItem(at: temp)
                        throw GemmaError.message("The download was corrupted. Try again.")
                    }
                    try? FileManager.default.removeItem(at: destination)
                    try FileManager.default.moveItem(at: temp, to: destination)
                }
                completedBytes += file.size
            }
            state = .ready
        } catch let error as URLError where error.code == .cancelled {
            state = .missing
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    func cancelDownload() {
        session?.getAllTasks { tasks in
            for case let task as URLSessionDownloadTask in tasks {
                task.cancel(byProducingResumeData: { _ in })
            }
        }
    }

    func delete() {
        cancelDownload()
        for file in Self.files { try? FileManager.default.removeItem(at: Self.url(file)) }
        resumeData = nil
        state = .missing
    }

    private func progress(_ bytes: Int64) -> Double {
        Double(completedBytes + bytes) / Double(Self.downloadSize)
    }

    private static func fileSize(_ url: URL) -> Int64? {
        (try? FileManager.default.attributesOfItem(atPath: url.path)[.size]) as? Int64
    }

    /// One file to a temp location, resuming a previous attempt if possible
    /// (resume data is kept in memory, so it survives a failure or cancel
    /// but not a relaunch).
    private func fetch(_ file: File) async throws -> URL {
        let session = self.session ?? URLSession(
            configuration: .default, delegate: self, delegateQueue: .main)
        self.session = session
        let url = URL(string:
            "https://huggingface.co/ggml-org/gemma-4-E4B-it-GGUF/resolve/\(Self.revision)/\(file.name)")!
        return try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            let task = resumeData.map { session.downloadTask(withResumeData: $0) }
                ?? session.downloadTask(with: url)
            resumeData = nil
            task.resume()
        }
    }

    nonisolated func urlSession(
        _ session: URLSession, downloadTask: URLSessionDownloadTask,
        didWriteData bytesWritten: Int64, totalBytesWritten: Int64,
        totalBytesExpectedToWrite: Int64
    ) {
        MainActor.assumeIsolated {
            if case .downloading = state { state = .downloading(progress(totalBytesWritten)) }
        }
    }

    nonisolated func urlSession(
        _ session: URLSession, downloadTask: URLSessionDownloadTask,
        didFinishDownloadingTo location: URL
    ) {
        // The file at `location` is deleted when this returns; move it now.
        let keep = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        let status = (downloadTask.response as? HTTPURLResponse)?.statusCode ?? 0
        let result: Result<URL, Error> =
            (200..<300).contains(status)
            ? Result { try FileManager.default.moveItem(at: location, to: keep); return keep }
            : .failure(GemmaError.message("Download failed (HTTP \(status))."))
        MainActor.assumeIsolated {
            continuation?.resume(with: result)
            continuation = nil
        }
    }

    nonisolated func urlSession(
        _ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?
    ) {
        guard let error else { return }
        let data = (error as NSError).userInfo[NSURLSessionDownloadTaskResumeData] as? Data
        MainActor.assumeIsolated {
            resumeData = data
            continuation?.resume(throwing: error)
            continuation = nil
        }
    }

    /// Streamed SHA-256, off the main thread (a 4.6 GB file takes seconds).
    private nonisolated static func sha256(of url: URL) async -> String {
        await Task.detached(priority: .utility) {
            guard let handle = try? FileHandle(forReadingFrom: url) else { return "" }
            defer { try? handle.close() }
            var hasher = SHA256()
            while let chunk = try? handle.read(upToCount: 8 << 20), !chunk.isEmpty {
                hasher.update(data: chunk)
            }
            return hasher.finalize().map { String(format: "%02x", $0) }.joined()
        }.value
    }
}

enum GemmaError: LocalizedError {
    case message(String)
    var errorDescription: String? {
        if case .message(let text) = self { return text }
        return nil
    }
}

/// Runs Gemma 4 on one image + prompt via llama.cpp. An actor so windows
/// importing at once take turns (the model is ~5 GB in memory). The model
/// loads on first use and stays until `unload()` (end of an import).
actor GemmaRunner {
    static let shared = GemmaRunner()

    private var model: OpaquePointer?
    private var vision: OpaquePointer?

    private static let backendReady: Void = {
        // llama.cpp logs every layer; keep the console quiet (before init,
        // which logs too).
        llama_log_set({ _, _, _ in }, nil)
        mtmd_helper_log_set({ _, _, _ in }, nil)
        // Metal residency sets assert at process exit if a model is still
        // loaded — i.e. quitting mid-import would crash. They're a small
        // latency optimization; not worth that.
        setenv("GGML_METAL_NO_RESIDENCY", "1", 1)
        llama_backend_init()
    }()

    /// Generate a reply for `prompt` about `image`. `prompt` goes in the user
    /// turn after the image. Thinking is on (it's what made the bake-off
    /// accurate); only the final answer after the thought channel is
    /// returned.
    func reply(image: CGImage, prompt: String, maxTokens: Int = 4096) throws -> String {
        try load()
        guard let model, let vision else { throw GemmaError.message("Model not loaded.") }

        var cparams = llama_context_default_params()
        cparams.n_ctx = 8192
        cparams.n_batch = 2048
        cparams.n_ubatch = 2048  // an image's tokens must fit one ubatch
        guard let ctx = llama_init_from_model(model, cparams) else {
            throw GemmaError.message("Couldn't create a model context.")
        }
        defer { llama_free(ctx) }

        // Gemma 4 chat format, from the GGUF's template. <|think|> in the
        // system turn switches thinking on. The C API can't run the Jinja
        // template, so it's spelled out here.
        let marker = String(cString: mtmd_default_marker())
        let text = "<|turn>system\n<|think|>\n<turn|>\n<|turn>user\n\(marker)\n\(prompt)<turn|>\n<|turn>model\n"

        let (rgb, width, height) = Self.rgbBytes(image)
        guard let bitmap = rgb.withUnsafeBufferPointer({
            mtmd_bitmap_init(UInt32(width), UInt32(height), $0.baseAddress)
        }) else { throw GemmaError.message("Couldn't read the image.") }
        defer { mtmd_bitmap_free(bitmap) }

        let chunks = mtmd_input_chunks_init()
        defer { mtmd_input_chunks_free(chunks) }
        let tokenized: Int32 = text.withCString { cText in
            var input = mtmd_input_text(
                text: cText, text_len: strlen(cText), add_special: true, parse_special: true)
            var bitmaps: [OpaquePointer?] = [bitmap]
            return bitmaps.withUnsafeMutableBufferPointer {
                mtmd_tokenize(vision, chunks, &input, $0.baseAddress, 1)
            }
        }
        guard tokenized == 0 else { throw GemmaError.message("Couldn't prepare the image.") }

        var nPast: llama_pos = 0
        guard mtmd_helper_eval_chunks(
            vision, ctx, chunks, 0, 0, Int32(cparams.n_batch), true, &nPast) == 0
        else { throw GemmaError.message("The model couldn't read the image.") }

        // Greedy: same image → same answer.
        let sampler = llama_sampler_chain_init(llama_sampler_chain_default_params())
        defer { llama_sampler_free(sampler) }
        llama_sampler_chain_add(sampler, llama_sampler_init_greedy())

        let vocab = llama_model_get_vocab(model)
        var bytes: [UInt8] = []
        var piece = [CChar](repeating: 0, count: 256)
        for _ in 0..<maxTokens {
            try Task.checkCancellation()
            var token = llama_sampler_sample(sampler, ctx, -1)
            if llama_vocab_is_eog(vocab, token) { break }
            // special: true keeps the <channel|> marker that ends the thought
            let n = llama_token_to_piece(vocab, token, &piece, Int32(piece.count), 0, true)
            if n > 0 { bytes += piece[0..<Int(n)].map { UInt8(bitPattern: $0) } }
            guard llama_decode(ctx, llama_batch_get_one(&token, 1)) == 0 else { break }
        }
        let output = String(decoding: bytes, as: UTF8.self)
        // "<|channel>thought\n…<channel|>answer" → answer
        return output.components(separatedBy: "<channel|>").last ?? output
    }

    func unload() {
        if let vision { mtmd_free(vision) }
        if let model { llama_model_free(model) }
        vision = nil
        model = nil
    }

    private func load() throws {
        guard model == nil else { return }
        _ = Self.backendReady
        var mparams = llama_model_default_params()
        mparams.n_gpu_layers = 999  // all layers on the GPU (Metal)
        guard let model = llama_model_load_from_file(
            GemmaModel.url(GemmaModel.weights).path, mparams)
        else { throw GemmaError.message("Couldn't load the Gemma model.") }
        var vparams = mtmd_context_params_default()
        vparams.use_gpu = true
        vparams.print_timings = false
        vparams.warmup = false
        guard let vision = mtmd_init_from_file(
            GemmaModel.url(GemmaModel.projector).path, model, vparams)
        else {
            llama_model_free(model)
            throw GemmaError.message("Couldn't load Gemma's image reader.")
        }
        self.model = model
        self.vision = vision
    }

    /// Packed 8-bit RGB, the layout mtmd_bitmap_init expects.
    private static func rgbBytes(_ image: CGImage) -> ([UInt8], Int, Int) {
        let width = image.width, height = image.height
        var rgba = [UInt8](repeating: 0, count: width * height * 4)
        rgba.withUnsafeMutableBytes { buffer in
            let context = CGContext(
                data: buffer.baseAddress, width: width, height: height,
                bitsPerComponent: 8, bytesPerRow: width * 4,
                space: CGColorSpace(name: CGColorSpace.sRGB)!,
                bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)
            context?.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        }
        var rgb = [UInt8](repeating: 0, count: width * height * 3)
        for i in 0..<(width * height) {
            rgb[i * 3] = rgba[i * 4]
            rgb[i * 3 + 1] = rgba[i * 4 + 1]
            rgb[i * 3 + 2] = rgba[i * 4 + 2]
        }
        return (rgb, width, height)
    }
}
