import Foundation

struct DurationFormatter {
    static func format(_ duration: TimeInterval) -> String {
        let hours = Int(duration) / 3600
        let minutes = (Int(duration) % 3600) / 60
        let seconds = Int(duration) % 60

        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        }
        return String(format: "%d:%02d", minutes, seconds)
    }

    static func formatWithMilliseconds(_ duration: TimeInterval) -> String {
        let hours = Int(duration) / 3600
        let minutes = (Int(duration) % 3600) / 60
        let seconds = Int(duration) % 60
        let ms = Int((duration.truncatingRemainder(dividingBy: 1)) * 10)

        if hours > 0 {
            return String(format: "%d:%02d:%02d.%d", hours, minutes, seconds, ms)
        }
        return String(format: "%d:%02d.%d", minutes, seconds, ms)
    }
}

struct FileSizeFormatter {
    static func format(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }
}

extension Date {
    var screenRecorderFileName: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd 'at' HH.mm.ss"
        return formatter.string(from: self)
    }
}
