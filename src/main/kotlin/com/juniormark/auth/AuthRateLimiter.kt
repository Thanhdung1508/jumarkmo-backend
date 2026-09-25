package com.juniormark.auth

import com.juniormark.common.ApiException
import org.springframework.stereotype.Service

/** Giới hạn yêu cầu theo IP/email, chia sẻ bộ đếm giữa các tiến trình dùng chung CSDL. */
@Service
class AuthRateLimiter(private val repository: AuthRepository, private val passwords: PasswordService) {
    fun check(key: String, maximum: Int, seconds: Int) {
        if (repository.incrementLimit(passwords.digest(key), seconds) > maximum) {
            throw ApiException(429, "Bạn thao tác quá nhanh. Vui lòng thử lại sau.", "over_request_rate_limit")
        }
    }
}
