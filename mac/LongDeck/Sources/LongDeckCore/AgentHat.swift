import Foundation

public enum AgentHat {
    public static func of(_ name: String) -> (hat: Int, tint: Int) {
        var h: UInt32 = 2_166_136_261
        for b in name.utf8 { h = (h ^ UInt32(b)) &* 16_777_619 }
        return (hat: Int(h % 8), tint: Int((h / 8) % 8))
    }
}
