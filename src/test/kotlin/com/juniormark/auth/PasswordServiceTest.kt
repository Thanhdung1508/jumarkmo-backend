package com.juniormark.auth

import org.junit.jupiter.api.Assertions.*
import org.junit.jupiter.api.Test

class PasswordServiceTest {
    private val passwords = PasswordService()

    @Test
    fun `doc duoc hash Node scrypt voi mat khau Unicode`() {
        // Fixture tạo bằng crypto.scryptSync của Node; salt là chuỗi UTF-8, không phải byte hex.
        val fixture = "scrypt:00112233445566778899aabbccddeeff:c3622ff2a0dada56b9eb80984c94153ad122e9671604c51dae59be1aeb525fa5eed3585bb9190fbfb0531119b1f74be4a61c2accef41df47898ac133d8b59cfc"
        assertTrue(passwords.verify("Mật khẩu-123!", fixture))
        assertFalse(passwords.verify("Mật khẩu-123?", fixture))
    }

    @Test
    fun `hash moi co salt rieng va xac thuc duoc`() {
        val first = passwords.hash("secret-123")
        val second = passwords.hash("secret-123")
        assertNotEquals(first, second)
        assertTrue(passwords.verify("secret-123", first))
        assertFalse(passwords.verify("wrong-123", first))
    }

    @Test
    fun `hash hong bi tu choi an toan`() {
        listOf("", "scrypt:abc:def", "other:" + "a".repeat(32) + ":" + "a".repeat(128))
            .forEach { assertFalse(passwords.verify("secret-123", it)) }
    }
}
