package com.juniormark.auth

import com.juniormark.database.Database
import org.springframework.stereotype.Repository
import java.sql.Connection
import java.util.UUID

/** Toàn bộ SQL xác thực nằm tại đây; các giá trị đầu vào luôn được truyền qua tham số. */
@Repository
class AuthRepository(private val database: Database) {
    fun <T> transaction(action: (Connection) -> T): T = database.transaction(action)

    fun session(hash: String): AuthSession? = database.query(SESSION_SQL, hash).firstOrNull()?.let(::toSession)

    fun session(connection: Connection, hash: String): AuthSession? =
        database.query(connection, SESSION_SQL, hash).firstOrNull()?.let(::toSession)

    fun accountByEmail(email: String): Map<String, Any?>? =
        database.query("select * from private.local_accounts where email=?", email).firstOrNull()

    /** Khóa tài khoản trước khi sửa phiên/reset để mọi thao tác thu hồi có cùng thứ tự khóa. */
    fun lockAccount(connection: Connection, id: String): Map<String, Any?>? = database.query(
        connection, "select * from private.local_accounts where user_id=? for update", UUID.fromString(id)
    ).firstOrNull()

    fun createAccount(connection: Connection, id: String, email: String, hash: String, metadataJson: String) {
        database.execute(connection, "insert into auth.users(id,raw_user_meta_data) values(?,?::jsonb)", UUID.fromString(id), metadataJson)
        database.execute(connection, "insert into private.local_accounts(user_id,email,password_hash) values(?,?,?)", UUID.fromString(id), email, hash)
    }

    fun createSession(connection: Connection, hash: String, id: String, recovery: Boolean) {
        database.execute(connection, "insert into private.local_sessions(token_hash,user_id,recovery) values(?,?,?)", hash, UUID.fromString(id), recovery)
    }

    fun deleteSession(connection: Connection, hash: String) {
        database.execute(connection, "delete from private.local_sessions where token_hash=?", hash)
    }

    fun deleteSessions(connection: Connection, id: String) {
        database.execute(connection, "delete from private.local_sessions where user_id=?", UUID.fromString(id))
    }

    fun deleteResets(connection: Connection, id: String) {
        database.execute(connection, "delete from private.local_password_resets where user_id=?", UUID.fromString(id))
    }

    fun createReset(connection: Connection, hash: String, id: String) {
        database.execute(connection, "insert into private.local_password_resets(token_hash,user_id) values(?,?)", hash, UUID.fromString(id))
    }

    fun resetUser(hash: String): String? = database.query(
        "select user_id from private.local_password_resets where token_hash=? and expires_at>now()", hash
    ).firstOrNull()?.get("user_id")?.toString()

    fun consumeReset(connection: Connection, hash: String): Boolean = database.query(
        connection, "delete from private.local_password_resets where token_hash=? and expires_at>now() returning user_id", hash
    ).isNotEmpty()

    fun changePassword(connection: Connection, id: String, hash: String) {
        database.execute(connection, "update private.local_accounts set password_hash=? where user_id=?", hash, UUID.fromString(id))
    }

    /** UPSERT nguyên tử và bền vững qua restart; key đã được băm, không lưu email/IP nguyên văn. */
    fun incrementLimit(key: String, seconds: Int): Int = (database.query(
        """insert into private.local_auth_limits(key,hits,expires_at)
           values(?,1,now()+make_interval(secs=>?))
           on conflict(key) do update set
           hits=case when local_auth_limits.expires_at<now() then 1 else local_auth_limits.hits+1 end,
           expires_at=case when local_auth_limits.expires_at<now() then excluded.expires_at else local_auth_limits.expires_at end
           returning hits""".trimIndent(), key, seconds
    ).first()["hits"] as Number).toInt()

    private fun toSession(row: Map<String, Any?>) = AuthSession(
        tokenHash = row["token_hash"].toString(), userId = row["user_id"].toString(),
        email = row["email"].toString(), metadata = row["raw_user_meta_data"] ?: emptyMap<String, Any?>(),
        recovery = row["recovery"] == true
    )

    companion object {
        private const val SESSION_SQL = """select s.token_hash,s.user_id,s.recovery,a.email,u.raw_user_meta_data
            from private.local_sessions s join private.local_accounts a using(user_id)
            join auth.users u on u.id=a.user_id where token_hash=? and expires_at>now()"""
    }
}

/** Mô hình nội bộ chứa hash phiên; publicData tuyệt đối không công khai hash này. */
data class AuthSession(val tokenHash: String, val userId: String, val email: String, val metadata: Any, val recovery: Boolean) {
    fun publicData(): Map<String, Any?> = mapOf(
        "user" to mapOf("id" to userId, "email" to email, "user_metadata" to metadata),
        "recovery" to recovery
    )
}
