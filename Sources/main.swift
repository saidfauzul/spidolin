// Copyright (C) 2026 Said Fauzul
// SPDX-License-Identifier: GPL-2.0-or-later

import AppKit

// Remote control of a running instance, like `gromit-mpx --toggle` etc.
let commands = [
    "--toggle": "toggle", "-t": "toggle",
    "--clear": "clear", "-c": "clear",
    "--undo": "undo", "-z": "undo",
    "--redo": "redo", "-y": "redo",
    "--visibility": "visibility", "-v": "visibility",
    "--quit": "quit", "-q": "quit",
]

if let arg = CommandLine.arguments.dropFirst().first {
    if let command = commands[arg] {
        DistributedNotificationCenter.default().postNotificationName(commandNotification, object: command,
                                                                     userInfo: nil, deliverImmediately: true)
        exit(0)
    }
    if !arg.hasPrefix("-psn") { // Finder may pass a process serial number
        print("""
        Usage: Spidolin [--toggle|-t] [--clear|-c] [--undo|-z] [--redo|-y] [--visibility|-v] [--quit|-q]
        With no arguments: start Spidolin.
        """)
        exit(arg == "--help" || arg == "-h" ? 0 : 1)
    }
}

let bundleID = Bundle.main.bundleIdentifier ?? "id.spidolin.Spidolin"
if NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).count > 1 {
    print("Spidolin is already running.")
    exit(0)
}

// Top-level code runs on the main thread; AppController is @MainActor.
MainActor.assumeIsolated {
    let app = NSApplication.shared
    let controller = AppController()
    app.delegate = controller
    app.setActivationPolicy(.accessory)
    app.run()
}
