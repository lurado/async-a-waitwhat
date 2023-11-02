//
//  Logger.swift
//  AsyncAwait
//
//  Created by Sebastian Ludwig on 21.10.23.
//

import Foundation

struct Logger {
    private static let threadPersonalities = [
        "🐶", "🐱", "🐰", "🦊", "🐼", "🐨", "🐷", "🐸", "🐵", "🐔", "🦆", "🦉", "🦄", "🐝", "🐛", "🦋", "🐌", "🐞", "🐜", "🪰", "🦖", "🐙", "🦞", "🐠", "🦚", "🦩", "🦫", "🦨"
    ]
    private static let symbols = [
        "🟧", "🟨", "🟦", "🟪", "⬛️", "⬜️", "🟫", "🔶", "🔷", "💔", "🧡", "💛", "💚", "💙", "💜", "🖤", "🤍", "🤎", "🟠", "🟡", "🔵", "🟣", "⚫️", "⚪️", "🟤"
    ]
    
    private let id: Int
    private let symbol: String
    
    init(id: Int) {
        self.id = id
        symbol = Self.symbols[abs(id) % Self.symbols.count]
    }
    
    private static let threadDetailsRegex: NSRegularExpression = {
        // <NSThread: 0x6000008a8000>{number = 10, name = (null)}
        let pattern = #".+(?<address>0x[0-9a-f]+)>\{number = (?<number>\d+), name = (?<name>[^\s}]+)"#
        return try! NSRegularExpression(pattern: pattern)
    }()
    
    private func threadDetails() -> String {
        func extract(_ component: String, from match: NSTextCheckingResult, in message: String) -> String? {
            let nsrange = match.range(withName: component)
            guard nsrange.location != NSNotFound, let range = Range(nsrange, in: message) else {
                return nil
            }
            return String(message[range])
        }
        
        let currentThread = Thread.current
        let threadDescription = "\(currentThread)"
        
        guard let match = Self.threadDetailsRegex.firstMatch(
            in: threadDescription,
            options: [],
            range: NSRange(threadDescription.startIndex..<threadDescription.endIndex, in: threadDescription)
        ),
              let rawNumber = extract("number", from: match, in: threadDescription),
              let number = Int(rawNumber)
        else {
            return "??"
        }
        
        let qos: String
        switch currentThread.qualityOfService {
        case .userInteractive: qos = ".userInteractive"
        case .userInitiated: qos = ".userInitiated"
        case .utility: qos = ".utility"
        case .background: qos = ".background"
        case .default: qos = ".default"
        @unknown default: qos = "??"
        }

        let personality = number == 1 ? "🚨" : Self.threadPersonalities[(number - 1) % Self.threadPersonalities.count]
        var result = String(format: "%2d %@ %@", number, personality, qos)
        if currentThread.isMainThread {
            result += " main"
        }
        return result
    }
    
    private static let dateFormatter: DateFormatter = {
        let dateFormatter = DateFormatter()
        dateFormatter.locale = Locale.current
        dateFormatter.dateFormat = ":ss:SSS"
        return dateFormatter
    }()
    
    private func now() -> String {
        Self.dateFormatter.string(from: Date())
    }
    
    func log(_ message: String) {
        let lineFormat = "%@  %@    %2d: %@ - Thread: %@"
        // %@ does not support width attributes in format strings, so we pad manually
        let paddedMessage = message.padding(toLength: 40, withPad: " ", startingAt: 0)
        let line = String(format: lineFormat, symbol, now(), id, paddedMessage, threadDetails())
        print(line)
    }
}
