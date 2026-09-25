package com.juniormark.auth

import org.bouncycastle.crypto.generators.SCrypt
import org.springframework.stereotype.Service
import java.security.MessageDigest
import java.security.SecureRandom
import java.util.HexFormat

/** Băm mật khẩu bằng scrypt, giữ tương thích với tài khoản đã tạo bởi backend Node. */
@Service
class PasswordService {
    private val random = SecureRandom()
    private val hex = HexFormat.of()

    fun hash(password: String): String {
        val salt = randomHex(16)
        return "scrypt:$salt:${hex.formatHex(derive(password, salt))}"
    }

    fun verify(password: String, stored: String): Boolean {
        // Chỉ nhận đúng định dạng cố định; dữ liệu hỏng không được gây lỗi hoặc tăng chi phí scrypt.
        if (!HASH_PATTERN.matches(stored)) return false
        val parts = stored.split(':')
        return MessageDigest.isEqual(hex.parseHex(parts[2]), derive(password, parts[1]))
    }

    fun token(): String = randomHex(32)

    fun digest(value: String): String = hex.formatHex(
        MessageDigest.getInstance("SHA-256").digest(value.toByteArray(Charsets.UTF_8))
    )

    private fun randomHex(bytes: Int): String = hex.formatHex(ByteArray(bytes).also(random::nextBytes))

    private fun derive(password: String, salt: String): ByteArray = SCrypt.generate(
        password.toByteArray(Charsets.UTF_8), salt.toByteArray(Charsets.UTF_8), 32768, 8, 1, 64
    )

    companion object {
        private val HASH_PATTERN = Regex("scrypt:[a-f0-9]{32}:[a-f0-9]{128}")
    }
}
