import AppKit
import Foundation

// Independent, read-only OS observer: no activation, window, click, or input APIs.
let args = Array(CommandLine.arguments.dropFirst())
let duration = args.first.flatMap(Double.init) ?? 0
let end = Date().addingTimeInterval(duration)
repeat {
    let before = DispatchTime.now().uptimeNanoseconds
    let front = NSWorkspace.shared.frontmostApplication
    let row: [String: Any] = ["sampleStart": String(before),
        "sampleEnd": String(DispatchTime.now().uptimeNanoseconds),
        "bundleID": front?.bundleIdentifier ?? "", "pid": front?.processIdentifier ?? -1]
    let data = try JSONSerialization.data(withJSONObject: row, options: [.sortedKeys])
    FileHandle.standardOutput.write(data)
    FileHandle.standardOutput.write(Data([10]))
    if duration <= 0 { break }
    RunLoop.current.run(until: Date().addingTimeInterval(0.025))
} while Date() < end
