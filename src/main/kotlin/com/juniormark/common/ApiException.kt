package com.juniormark.common

/** Lỗi nghiệp vụ có thể hiển thị cho người dùng; không chứa SQL hay mật khẩu. */
class ApiException(val status: Int, override val message: String, val code: String = "request_failed") : RuntimeException(message)
