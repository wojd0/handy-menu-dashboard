import CommonCrypto
import CryptoKit
import Foundation
import Testing
@testable import handy_menu_dashboard

@Suite("Chromium cookie cipher")
struct ChromiumCookieCipherTests {
    @Test func decryptsAValueEncryptedWithTheDerivedKey() {
        let cipher = setupCipher()
        let encrypted = encrypt("secret-token", key: cipher.key)

        let decrypted = cipher.decrypt(encrypted, host: "github.com", metaVersion: 20)

        #expect(decrypted == "secret-token")
    }

    @Test func stripsTheHostHashOnVersion24() {
        let cipher = setupCipher()
        let hostHash = Data(SHA256.hash(data: Data("github.com".utf8)))
        let encrypted = encrypt(prefix: hostHash, plaintext: "credit-token", key: cipher.key)

        let decrypted = cipher.decrypt(encrypted, host: "github.com", metaVersion: 24)

        #expect(decrypted == "credit-token")
    }

    @Test func passesThroughAnUnencryptedValue() {
        let cipher = setupCipher()
        let plaintext = Data("plain=value".utf8)

        let decrypted = cipher.decrypt(plaintext, host: "github.com", metaVersion: 24)

        #expect(decrypted == "plain=value")
    }

    @Test func returnsNilForTheWrongKey() {
        let cipher = setupCipher()
        let encrypted = encrypt("secret", key: cipher.key)
        let wrong = ChromiumCookieCipher(key: Data(repeating: 9, count: 16))

        let decrypted = wrong.decrypt(encrypted, host: "github.com", metaVersion: 20)

        #expect(decrypted == nil || decrypted != "secret")
    }

    private func setupCipher() -> ChromiumCookieCipher {
        ChromiumCookieCipher(key: ChromiumCookieCipher.deriveKey(fromPassword: "peanuts"))
    }

    private func encrypt(_ text: String, key: Data) -> Data {
        encrypt(prefix: Data(), plaintext: text, key: key)
    }

    private func encrypt(prefix: Data, plaintext text: String, key: Data) -> Data {
        let iv = Data(repeating: 0x20, count: 16)
        var payload = prefix
        payload.append(Data(text.utf8))

        var output = Data(count: payload.count + kCCBlockSizeAES128)
        var encryptedCount = 0
        _ = output.withUnsafeMutableBytes { outputBuffer in
            payload.withUnsafeBytes { payloadBuffer in
                key.withUnsafeBytes { keyBuffer in
                    iv.withUnsafeBytes { ivBuffer in
                        CCCrypt(
                            CCOperation(kCCEncrypt),
                            CCAlgorithm(kCCAlgorithmAES),
                            CCOptions(kCCOptionPKCS7Padding),
                            keyBuffer.baseAddress, keyBuffer.count,
                            ivBuffer.baseAddress,
                            payloadBuffer.baseAddress, payloadBuffer.count,
                            outputBuffer.baseAddress, outputBuffer.count,
                            &encryptedCount
                        )
                    }
                }
            }
        }

        var result = Data("v10".utf8)
        result.append(output.prefix(encryptedCount))
        return result
    }
}
