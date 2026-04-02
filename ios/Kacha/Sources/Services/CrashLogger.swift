import Foundation

private let crashFileURL: URL = {
    FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("last_crash.txt")
}()

private func crashSignalHandler(_ signal: Int32) {
    let msg = "Signal \(signal) at \(Date())\n"
    try? msg.write(to: crashFileURL, atomically: true, encoding: .utf8)
}

/// Simple crash logger — saves crash info to disk for display on next launch.
enum CrashLogger {

    static func install() {
        NSSetUncaughtExceptionHandler { exception in
            let info = """
            === KAGI CRASH ===
            Date: \(Date())
            Name: \(exception.name.rawValue)
            Reason: \(exception.reason ?? "unknown")
            Stack:
            \(exception.callStackSymbols.joined(separator: "\n"))
            """
            try? info.write(to: crashFileURL, atomically: true, encoding: .utf8)
        }
        signal(SIGABRT, crashSignalHandler)
        signal(SIGSEGV, crashSignalHandler)
    }

    static func lastCrash() -> String? {
        guard let data = try? String(contentsOf: crashFileURL, encoding: .utf8), !data.isEmpty else {
            return nil
        }
        return data
    }

    static func clearCrash() {
        try? FileManager.default.removeItem(at: crashFileURL)
    }
}
