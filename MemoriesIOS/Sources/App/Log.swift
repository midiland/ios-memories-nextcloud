import os

/// App logs (Console.app or `log stream --predicate 'subsystem == "gallery.memories.ios"'`).
enum Log {
    static let localServer = Logger(subsystem: "gallery.memories.ios", category: "local-server")
    static let offline = Logger(subsystem: "gallery.memories.ios", category: "offline")
}
