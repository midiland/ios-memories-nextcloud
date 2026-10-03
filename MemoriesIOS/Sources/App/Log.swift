import os

/// App logs (Console.app or `log stream --predicate 'subsystem == "fr.midiland.memories"'`).
enum Log {
    static let localServer = Logger(subsystem: "fr.midiland.memories", category: "local-server")
    static let offline = Logger(subsystem: "fr.midiland.memories", category: "offline")
    static let web = Logger(subsystem: "fr.midiland.memories", category: "web")
    static let nativex = Logger(subsystem: "fr.midiland.memories", category: "nativex")
    static let photos = Logger(subsystem: "fr.midiland.memories", category: "photos")
}
