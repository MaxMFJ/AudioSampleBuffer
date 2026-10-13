import CommonCrypto
import Foundation
import Security

// WEAPI implementation adapted from NeteaseCloudMusicApi 4.32.0's
// util/crypto.js (MIT License, https://github.com/Binaryify/NeteaseCloudMusicApi).

internal struct NetEaseWEAPIParameters {
    let params: String
    let encSecKey: String
}

internal enum NetEaseCryptoError: Error {
    case invalidJSON
    case encryptionFailed(CCCryptorStatus)
    case invalidPublicKey
    case rsaEncryptionFailed
}

/// Produces the form fields expected by a Netease Cloud Music WEAPI request.
internal func neteaseWEAPIParameters(jsonData: Data) throws -> NetEaseWEAPIParameters {
    guard let object = try? JSONSerialization.jsonObject(with: jsonData),
          JSONSerialization.isValidJSONObject(object) else {
        throw NetEaseCryptoError.invalidJSON
    }

    let presetKey = Array("0CoJUm6Qyw8W8jud".utf8)
    let iv = Array("0102030405060708".utf8)
    let secretKey = randomSecretKey()

    let first = try aesCBCPKCS7(jsonData, key: presetKey, iv: iv)
    // CryptoJS's first AES call returns a Base64 string. The original
    // implementation encrypts that string in round two, not the raw bytes.
    let firstBase64 = Data(first.base64EncodedString().utf8)
    let second = try aesCBCPKCS7(firstBase64, key: Array(secretKey.utf8), iv: iv)
    guard let params = second.base64EncodedString(options: []).nilIfEmpty else {
        throw NetEaseCryptoError.encryptionFailed(CCCryptorStatus(kCCParamError))
    }

    let reversedSecret = Array(secretKey.utf8.reversed())
    let encryptedSecret = try rsaRaw(reversedSecret)
    return NetEaseWEAPIParameters(params: params, encSecKey: encryptedSecret.map { String(format: "%02x", $0) }.joined())
}

internal struct NetEaseEAPIParameters {
    let params: String
}

/// Produces the uppercase-hex `params` field used by Netease EAPI requests.
internal func neteaseEAPIParameters(url: String, jsonData: Data) throws -> NetEaseEAPIParameters {
    guard let object = try? JSONSerialization.jsonObject(with: jsonData),
          JSONSerialization.isValidJSONObject(object) else {
        throw NetEaseCryptoError.invalidJSON
    }
    let text = String(decoding: jsonData, as: UTF8.self)
    let message = "nobody\(url)use\(text)md5forencrypt"
    let digest = md5Hex(message)
    let payload = "\(url)-36cd479b6b5-\(text)-36cd479b6b5-\(digest)"
    let encrypted = try aesECBPKCS7(Data(payload.utf8), key: Array("e82ckenh8dichen8".utf8))
    return NetEaseEAPIParameters(params: encrypted.map { String(format: "%02X", $0) }.joined())
}

/// Decrypts a normal EAPI response. Compressed response handling remains the caller's job.
internal func neteaseEAPIDecrypt(hex: String) throws -> Data {
    guard let encrypted = Data(hexString: hex) else { throw NetEaseCryptoError.invalidJSON }
    return try aesECBPKCS7(encrypted, key: Array("e82ckenh8dichen8".utf8), decrypt: true)
}

private func randomSecretKey() -> String {
    let alphabet = Array("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789")
    var generator = SystemRandomNumberGenerator()
    return String((0..<16).map { _ in alphabet[Int.random(in: alphabet.indices, using: &generator)] })
}

private func aesCBCPKCS7(_ data: Data, key: [UInt8], iv: [UInt8]) throws -> Data {
    var output = Data(count: data.count + kCCBlockSizeAES128)
    var outputLength = 0
    let status = output.withUnsafeMutableBytes { outputBuffer in
        data.withUnsafeBytes { dataBuffer in
            CCCrypt(
                CCOperation(kCCEncrypt),
                CCAlgorithm(kCCAlgorithmAES),
                CCOptions(kCCOptionPKCS7Padding),
                key, key.count,
                iv,
                dataBuffer.baseAddress, data.count,
                outputBuffer.baseAddress, outputBuffer.count,
                &outputLength
            )
        }
    }
    guard status == kCCSuccess else { throw NetEaseCryptoError.encryptionFailed(status) }
    output.removeSubrange(outputLength..<output.count)
    return output
}

private func aesECBPKCS7(_ data: Data, key: [UInt8], decrypt: Bool = false) throws -> Data {
    var output = Data(count: data.count + kCCBlockSizeAES128)
    var outputLength = 0
    let status = output.withUnsafeMutableBytes { outputBuffer in
        data.withUnsafeBytes { dataBuffer in
            CCCrypt(
                decrypt ? CCOperation(kCCDecrypt) : CCOperation(kCCEncrypt),
                CCAlgorithm(kCCAlgorithmAES),
                CCOptions(kCCOptionPKCS7Padding | kCCOptionECBMode),
                key, key.count,
                nil,
                dataBuffer.baseAddress, data.count,
                outputBuffer.baseAddress, outputBuffer.count,
                &outputLength
            )
        }
    }
    guard status == kCCSuccess else { throw NetEaseCryptoError.encryptionFailed(status) }
    output.removeSubrange(outputLength..<output.count)
    return output
}

private func md5Hex(_ string: String) -> String {
    let digest = string.data(using: .utf8)!.withUnsafeBytes { buffer in
        var result = [UInt8](repeating: 0, count: Int(CC_MD5_DIGEST_LENGTH))
        CC_MD5(buffer.baseAddress, CC_LONG(buffer.count), &result)
        return result
    }
    return digest.map { String(format: "%02x", $0) }.joined()
}

private func rsaRaw(_ data: [UInt8]) throws -> [UInt8] {
    let pemBody = """
    MIGfMA0GCSqGSIb3DQEBAQUAA4GNADCBiQKBgQDgtQn2JZ34ZC28NWYpAUd98iZ37BUrX/aKzmFbt7clFSs6sXqHauqKWqdtLkF2KexO40H1YTX8z2lSgBBOAxLsvaklV8k4cBFK9snQXE9/DDaFt6Rr7iVZMldczhC0JNgTz+SHXT6CBHuX3e9SdB1Ua44oncaTWz7OBGLbCiK45wIDAQAB
    """
    guard let der = Data(base64Encoded: pemBody, options: [.ignoreUnknownCharacters]) else {
        throw NetEaseCryptoError.invalidPublicKey
    }
    let attributes: [CFString: Any] = [
        kSecAttrKeyType: kSecAttrKeyTypeRSA,
        kSecAttrKeyClass: kSecAttrKeyClassPublic,
        kSecAttrKeySizeInBits: 1024
    ]
    guard let key = SecKeyCreateWithData(der as CFData, attributes as CFDictionary, nil),
          SecKeyIsAlgorithmSupported(key, .encrypt, .rsaEncryptionRaw) else {
        throw NetEaseCryptoError.invalidPublicKey
    }
    var error: Unmanaged<CFError>?
    guard let encrypted = SecKeyCreateEncryptedData(key, .rsaEncryptionRaw, Data(data) as CFData, &error) else {
        throw NetEaseCryptoError.rsaEncryptionFailed
    }
    return (encrypted as Data).map { $0 }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}

private extension Data {
    init?(hexString: String) {
        guard hexString.count.isMultiple(of: 2) else { return nil }
        var bytes = [UInt8](); bytes.reserveCapacity(hexString.count / 2)
        var index = hexString.startIndex
        while index < hexString.endIndex {
            let next = hexString.index(index, offsetBy: 2)
            guard let byte = UInt8(hexString[index..<next], radix: 16) else { return nil }
            bytes.append(byte); index = next
        }
        self.init(bytes)
    }
}
