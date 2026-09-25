package com.juniormark.auth

import com.fasterxml.jackson.databind.ObjectMapper
import com.juniormark.common.ApiException
import org.springframework.beans.factory.annotation.Value
import org.springframework.stereotype.Service
import java.nio.file.Files
import java.nio.file.Path
import java.nio.file.StandardOpenOption
import java.nio.file.attribute.PosixFilePermissions
import java.util.Locale
import java.util.UUID

/** Điều phối nghiệp vụ tài khoản; controller không biết SQL, thuật toán băm hay nơi lưu thư local. */
@Service
class AuthService(
    private val repository: AuthRepository,
    private val passwords: PasswordService,
    private val sessions: SessionService,
    private val limits: AuthRateLimiter,
    private val mapper: ObjectMapper,
    @Value("\${app.origin}") private val origin: String,
    @Value("\${app.mail-directory:.local/mail}") private val mailDirectory: String
) {
    // Tài khoản không tồn tại vẫn phải chạy scrypt, tránh phân biệt qua thời gian xử lý.
    private val dummyHash = passwords.hash(passwords.token())

    fun signup(body: Map<String, Any?>, ip: String): AuthResult {
        val email = email(body["email"])
        val password = body["password"] as? String
        val displayName = (body["displayName"] as? String)?.trim()
        if (email == null || !validPassword(password) || displayName == null || displayName.length !in 2..50)
            throw ApiException(400, "Thông tin đăng ký không hợp lệ.")
        limits.check("signup:$ip", 15, 3600)
        val id = UUID.randomUUID().toString()
        val hash = passwords.hash(password!!)
        val metadata = mapOf("display_name" to displayName)
        val raw = repository.transaction { connection ->
            repository.createAccount(connection, id, email, hash, mapper.writeValueAsString(metadata))
            sessions.create(connection, id)
        }
        return AuthResult(mapOf("session" to AuthSession("", id, email, metadata, false).publicData()), raw)
    }

    fun signin(body: Map<String, Any?>, current: AuthSession?): AuthResult {
        val email = email(body["email"])
        val password = body["password"] as? String
        if (email == null || password == null || password.length > 128)
            throw ApiException(400, "Thông tin đăng nhập không hợp lệ.")
        limits.check("signin:$email", 20, 600)
        val candidate = repository.accountByEmail(email)
        if (candidate == null) {
            passwords.verify(password, dummyHash)
            throw invalidCredentials()
        }
        val id = candidate["user_id"].toString()
        // Khóa trước khi kiểm tra hash để đăng nhập đồng thời không bỏ qua việc đổi mật khẩu.
        return repository.transaction { connection ->
            val account = repository.lockAccount(connection, id) ?: throw invalidCredentials()
            if (!passwords.verify(password, account["password_hash"].toString())) throw invalidCredentials()
            current?.let { repository.deleteSession(connection, it.tokenHash) }
            val raw = sessions.create(connection, id)
            val session = repository.session(connection, passwords.digest(raw))!!
            AuthResult(mapOf("session" to session.publicData()), raw)
        }
    }

    fun signout(body: Map<String, Any?>, current: AuthSession?): AuthResult {
        if (current != null) repository.transaction { connection ->
            repository.lockAccount(connection, current.userId)
            val active = repository.session(connection, current.tokenHash)
            if (active != null) {
                if (body["scope"] == "global") repository.deleteSessions(connection, current.userId)
                else repository.deleteSession(connection, current.tokenHash)
            }
        }
        return AuthResult(cookie = "")
    }

    fun reset(body: Map<String, Any?>): AuthResult {
        val email = email(body["email"]) ?: throw ApiException(400, "Email không hợp lệ.")
        limits.check("reset:$email", 4, 1800)
        val candidate = repository.accountByEmail(email)
        if (candidate != null) repository.transaction { connection ->
            val id = candidate["user_id"].toString()
            if (repository.lockAccount(connection, id) != null) {
                val raw = passwords.token()
                repository.deleteResets(connection, id)
                repository.createReset(connection, passwords.digest(raw), id)
                writeLocalMail(email, raw)
            }
        }
        // Phản hồi giống nhau dù email có tồn tại hay không; không trả token qua API.
        return AuthResult()
    }

    fun recover(body: Map<String, Any?>): AuthResult {
        val raw = body["token"] as? String
        if (raw == null || !SessionService.TOKEN_PATTERN.matches(raw))
            throw ApiException(400, "Liên kết không hợp lệ.")
        val hash = passwords.digest(raw)
        val id = repository.resetUser(hash) ?: throw invalidReset()
        return repository.transaction { connection ->
            repository.lockAccount(connection, id) ?: throw invalidReset()
            // DELETE RETURNING bảo đảm token một lần; chờ khóa tài khoản rồi kiểm tra lại hạn dùng.
            if (!repository.consumeReset(connection, hash)) throw invalidReset()
            val newToken = sessions.create(connection, id, recovery = true)
            val session = repository.session(connection, passwords.digest(newToken))!!
            AuthResult(mapOf("session" to session.publicData()), newToken)
        }
    }

    fun changePassword(body: Map<String, Any?>, current: AuthSession?): AuthResult {
        if (current == null) throw expiredSession()
        val password = body["password"] as? String
        if (!validPassword(password)) throw ApiException(400, "Mật khẩu cần 8–128 ký tự.")
        val newHash = passwords.hash(password!!)
        return repository.transaction { connection ->
            val account = repository.lockAccount(connection, current.userId) ?: throw expiredSession()
            // Không tin snapshot trước transaction: phiên có thể vừa bị yêu cầu khác thu hồi.
            val active = repository.session(connection, current.tokenHash) ?: throw expiredSession()
            val oldPassword = body["oldPassword"] as? String
            if (!active.recovery && (oldPassword == null || oldPassword.length > 128 ||
                    !passwords.verify(oldPassword, account["password_hash"].toString()))) {
                throw ApiException(401, "Mật khẩu hiện tại chưa đúng.", "invalid_credentials")
            }
            repository.changePassword(connection, active.userId, newHash)
            repository.deleteSessions(connection, active.userId)
            repository.deleteResets(connection, active.userId)
            AuthResult(cookie = sessions.create(connection, active.userId))
        }
    }

    /** Hộp thư chỉ dùng cho môi trường local; không ghi token/mật khẩu vào log ứng dụng. */
    private fun writeLocalMail(email: String, token: String) {
        val directory = Path.of(mailDirectory).toAbsolutePath().normalize()
        Files.createDirectories(directory)
        val path = directory.resolve("${System.currentTimeMillis()}-${UUID.randomUUID()}.json")
        val content = mapper.writerWithDefaultPrettyPrinter().writeValueAsBytes(mapOf(
            "to" to email, "subject" to "Đặt lại mật khẩu JuniorMark (local)",
            "url" to origin.trimEnd('/') + "/#/account?recovery=" + token
        ))
        if (Files.getFileStore(directory).supportsFileAttributeView("posix")) {
            Files.createFile(path, PosixFilePermissions.asFileAttribute(PosixFilePermissions.fromString("rw-------")))
            Files.write(path, content, StandardOpenOption.WRITE)
        } else {
            Files.write(path, content, StandardOpenOption.CREATE_NEW, StandardOpenOption.WRITE)
        }
    }

    private fun email(value: Any?): String? {
        if (value !is String || value.length > 254) return null
        val normalized = value.trim().lowercase(Locale.ROOT)
        return normalized.takeIf { EMAIL_PATTERN.matches(it) }
    }

    private fun validPassword(value: String?): Boolean = value != null && value.length in 8..128
    private fun invalidCredentials() = ApiException(401, "Email hoặc mật khẩu chưa đúng.", "invalid_credentials")
    private fun expiredSession() = ApiException(401, "Vui lòng đăng nhập.", "session_expired")
    private fun invalidReset() = ApiException(400, "Liên kết đã dùng hoặc hết hạn.")

    companion object { private val EMAIL_PATTERN = Regex("(?U)[^\\s@]+@[^\\s@]+\\.[^\\s@]+") }
}

/** cookie=null giữ nguyên cookie hiện tại; chuỗi rỗng yêu cầu trình duyệt xóa cookie. */
data class AuthResult(val data: Map<String, Any?> = emptyMap(), val cookie: String? = null)
