public enum CrockfordBase32 {
  public static let alphabet = "0123456789ABCDEFGHJKMNPQRSTVWXYZ"

  private static let alphabetScalars = Set(alphabet.unicodeScalars)

  public static func generate(characters: Int) -> String {
    guard characters > 0 else {
      return ""
    }
    var generator = SystemRandomNumberGenerator()
    let alphabetArray = Array(alphabet)
    return String(
      (0..<characters).compactMap { _ in
        alphabetArray.randomElement(using: &generator)
      }
    )
  }

  /// Canonical order: uppercase, map confusables, then strip.
  public static func normalize(_ value: String) -> String {
    let uppercased = value.uppercased()
    var normalized = String()
    normalized.reserveCapacity(uppercased.count)

    for scalar in uppercased.unicodeScalars {
      let mapped: UnicodeScalar
      switch scalar.value {
      case 73, 76, 85:  // I, L, U
        mapped = "1"
      case 79:  // O
        mapped = "0"
      default:
        mapped = scalar
      }
      if alphabetScalars.contains(mapped) {
        normalized.unicodeScalars.append(mapped)
      }
    }
    return normalized
  }

  public static func sha256Hex(_ normalized: String) -> String {
    SHA256.hex(Array(normalized.utf8))
  }
}

public enum PairingCodeFormat {
  public static let length = 10

  public static func display(_ raw: String) -> String {
    guard raw.count == length else {
      return raw
    }
    let split = raw.index(raw.startIndex, offsetBy: 5)
    return "\(raw[..<split])-\(raw[split...])"
  }
}

public enum RecoveryPhraseFormat {
  public static let length = 26

  public static func display(_ raw: String) -> String {
    guard raw.count == length else {
      return raw
    }
    var result = String()
    for (index, character) in raw.enumerated() {
      if index > 0, index % 5 == 0 {
        result.append("-")
      }
      result.append(character)
    }
    return result
  }
}

private enum SHA256 {
  private static let constants: [UInt32] = [
    0x428a_2f98, 0x7137_4491, 0xb5c0_fbcf, 0xe9b5_dba5,
    0x3956_c25b, 0x59f1_11f1, 0x923f_82a4, 0xab1c_5ed5,
    0xd807_aa98, 0x1283_5b01, 0x2431_85be, 0x550c_7dc3,
    0x72be_5d74, 0x80de_b1fe, 0x9bdc_06a7, 0xc19b_f174,
    0xe49b_69c1, 0xefbe_4786, 0x0fc1_9dc6, 0x240c_a1cc,
    0x2de9_2c6f, 0x4a74_84aa, 0x5cb0_a9dc, 0x76f9_88da,
    0x983e_5152, 0xa831_c66d, 0xb003_27c8, 0xbf59_7fc7,
    0xc6e0_0bf3, 0xd5a7_9147, 0x06ca_6351, 0x1429_2967,
    0x27b7_0a85, 0x2e1b_2138, 0x4d2c_6dfc, 0x5338_0d13,
    0x650a_7354, 0x766a_0abb, 0x81c2_c92e, 0x9272_2c85,
    0xa2bf_e8a1, 0xa81a_664b, 0xc24b_8b70, 0xc76c_51a3,
    0xd192_e819, 0xd699_0624, 0xf40e_3585, 0x106a_a070,
    0x19a4_c116, 0x1e37_6c08, 0x2748_774c, 0x34b0_bcb5,
    0x391c_0cb3, 0x4ed8_aa4a, 0x5b9c_ca4f, 0x682e_6ff3,
    0x748f_82ee, 0x78a5_636f, 0x84c8_7814, 0x8cc7_0208,
    0x90be_fffa, 0xa450_6ceb, 0xbef9_a3f7, 0xc671_78f2,
  ]

  private static let initial: [UInt32] = [
    0x6a09_e667, 0xbb67_ae85, 0x3c6e_f372, 0xa54f_f53a,
    0x510e_527f, 0x9b05_688c, 0x1f83_d9ab, 0x5be0_cd19,
  ]

  static func hex(_ input: [UInt8]) -> String {
    var message = input
    let bitLength = UInt64(message.count) * 8
    message.append(0x80)
    while message.count % 64 != 56 {
      message.append(0)
    }
    message.append(contentsOf: withBigEndianBytes(bitLength))

    var hash = initial
    for chunkStart in stride(from: 0, to: message.count, by: 64) {
      var words = [UInt32](repeating: 0, count: 64)
      for index in 0..<16 {
        let offset = chunkStart + index * 4
        words[index] =
          UInt32(message[offset]) << 24
          | UInt32(message[offset + 1]) << 16
          | UInt32(message[offset + 2]) << 8
          | UInt32(message[offset + 3])
      }
      for index in 16..<64 {
        let s0 =
          rotateRight(words[index - 15], by: 7)
          ^ rotateRight(words[index - 15], by: 18)
          ^ (words[index - 15] >> 3)
        let s1 =
          rotateRight(words[index - 2], by: 17)
          ^ rotateRight(words[index - 2], by: 19)
          ^ (words[index - 2] >> 10)
        words[index] = words[index - 16] &+ s0 &+ words[index - 7] &+ s1
      }

      var working = hash
      for index in 0..<64 {
        let s1 =
          rotateRight(working[4], by: 6)
          ^ rotateRight(working[4], by: 11)
          ^ rotateRight(working[4], by: 25)
        let choice = (working[4] & working[5]) ^ (~working[4] & working[6])
        let temp1 = working[7] &+ s1 &+ choice &+ constants[index] &+ words[index]
        let s0 =
          rotateRight(working[0], by: 2)
          ^ rotateRight(working[0], by: 13)
          ^ rotateRight(working[0], by: 22)
        let majority =
          (working[0] & working[1])
          ^ (working[0] & working[2])
          ^ (working[1] & working[2])
        let temp2 = s0 &+ majority

        working = [
          temp1 &+ temp2,
          working[0],
          working[1],
          working[2],
          working[3] &+ temp1,
          working[4],
          working[5],
          working[6],
        ]
      }

      for index in 0..<8 {
        hash[index] = hash[index] &+ working[index]
      }
    }

    return
      hash
      .map { value in
        let part = String(value, radix: 16)
        return String(repeating: "0", count: 8 - part.count) + part
      }
      .joined()
  }

  private static func rotateRight(_ value: UInt32, by amount: UInt32) -> UInt32 {
    (value >> amount) | (value << (32 - amount))
  }

  private static func withBigEndianBytes(_ value: UInt64) -> [UInt8] {
    (0..<8).reversed().map { index in
      UInt8((value >> UInt64(index * 8)) & 0xff)
    }
  }
}
