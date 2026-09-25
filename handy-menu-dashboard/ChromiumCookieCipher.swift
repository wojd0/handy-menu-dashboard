import CommonCrypto
import CryptoKit
import Foundation

nonisolated struct ChromiumCookieCipher {
    let key: Data

    static func deriveKey(fromPassword password: String) -> Data {
        var derived = Data(count: 16)
        let passwordBytes = Array(password.utf8)
        let salt = Array("saltysalt".utf8)

        _ = derived.withUnsafeMutableBytes { derivedBuffer in
            passwordBytes.withUnsafeBufferPointer { passwordBuffer in
                salt.withUnsafeBufferPointer { saltBuffer in
                    CCKeyDerivationPBKDF(
                        CCPBKDFAlgorithm(kCCPBKDF2),
                        passwordBuffer.baseAddress, passwordBuffer.count,
                        saltBuffer.baseAddress, saltBuffer.count,
                        CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA1),
                        1003,
                        derivedBuffer.bindMemory(to: UInt8.self).baseAddress, 16
                    )
                }
            }
        }
        return derived
    }

    func decrypt(_ encrypted: Data, host: String, metaVersion: Int) -> String? {
        guard encrypted.count > 3 else { return nil }
        let prefix = encrypted.prefix(3)
        guard prefix == Data("v10".utf8) || prefix == Data("v11".utf8) else {
            return String(data: encrypted, encoding: .utf8)
        }

        let ciphertext = encrypted.dropFirst(3)
        guard let plaintext = Self.aesCBCDecrypt(ciphertext: Data(ciphertext), key: key) else {
            return nil
        }

        if metaVersion >= 24 {
            guard plaintext.count > 32 else { return nil }
            return String(data: plaintext.dropFirst(32), encoding: .utf8)
        }
        return String(data: plaintext, encoding: .utf8)
    }

    private static func aesCBCDecrypt(ciphertext: Data, key: Data) -> Data? {
        let iv = Data(repeating: 0x20, count: 16)
        var output = Data(count: ciphertext.count + kCCBlockSizeAES128)
        var decryptedCount = 0

        let status = output.withUnsafeMutableBytes { outputBuffer in
            ciphertext.withUnsafeBytes { cipherBuffer in
                key.withUnsafeBytes { keyBuffer in
                    iv.withUnsafeBytes { ivBuffer in
                        CCCrypt(
                            CCOperation(kCCDecrypt),
                            CCAlgorithm(kCCAlgorithmAES),
                            CCOptions(kCCOptionPKCS7Padding),
                            keyBuffer.baseAddress, keyBuffer.count,
                            ivBuffer.baseAddress,
                            cipherBuffer.baseAddress, cipherBuffer.count,
                            outputBuffer.baseAddress, outputBuffer.count,
                            &decryptedCount
                        )
                    }
                }
            }
        }

        guard status == kCCSuccess else { return nil }
        return output.prefix(decryptedCount)
    }
}
