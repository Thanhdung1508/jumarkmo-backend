package com.juniormark.auth

import jakarta.servlet.http.HttpServletRequest
import jakarta.servlet.http.HttpServletResponse
import org.springframework.beans.factory.annotation.Value
import org.springframework.http.ResponseCookie
import org.springframework.stereotype.Service
import java.sql.Connection
import java.time.Duration

/** Quản lý cookie HttpOnly và phiên phía máy chủ; CSDL chỉ giữ SHA-256 của token ngẫu nhiên. */
@Service
class SessionService(
    private val repository: AuthRepository,
    private val passwords: PasswordService,
    @Value("\${app.origin}") private val origin: String
) {
    fun current(request: HttpServletRequest): AuthSession? {
        val raw = request.cookies?.firstOrNull { it.name == "jm_session" }?.value ?: return null
        return if (TOKEN_PATTERN.matches(raw)) repository.session(passwords.digest(raw)) else null
    }

    fun userId(request: HttpServletRequest): String? = current(request)?.userId

    /** Ghi phiên trong transaction; chỉ gửi cookie sau khi transaction đã commit thành công. */
    fun create(connection: Connection, userId: String, recovery: Boolean = false): String {
        val raw = passwords.token()
        repository.createSession(connection, passwords.digest(raw), userId, recovery)
        return raw
    }

    fun setCookie(response: HttpServletResponse, raw: String) {
        val cookie = ResponseCookie.from("jm_session", raw)
            .path("/api").httpOnly(true).sameSite("Strict").secure(origin.startsWith("https:"))
            .maxAge(if (raw.isEmpty()) Duration.ZERO else Duration.ofDays(7)).build()
        response.addHeader("Set-Cookie", cookie.toString())
    }

    companion object { val TOKEN_PATTERN = Regex("[a-f0-9]{64}") }
}
