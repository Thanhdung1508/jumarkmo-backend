package com.juniormark.common

import org.springframework.http.ResponseEntity
import org.springframework.http.converter.HttpMessageNotReadableException
import org.springframework.web.bind.annotation.ExceptionHandler
import org.springframework.web.bind.annotation.RestControllerAdvice
import java.sql.SQLException

@RestControllerAdvice
class ApiErrorHandler {
 @ExceptionHandler(ApiException::class)
 fun known(e: ApiException) = response(e.status,e.message,e.code)
 @ExceptionHandler(HttpMessageNotReadableException::class)
 fun badJson() = response(400,"JSON hoặc kiểu dữ liệu không hợp lệ.")
 @ExceptionHandler(SQLException::class)
 fun database(e: SQLException) = when(e.sqlState) {
  "23505" -> response(409,"Thông tin đã tồn tại.")
  "23514","22P02","23503","22001" -> response(400,"Dữ liệu không hợp lệ.")
  "42501" -> response(403,"Không có quyền thực hiện.")
  else -> response(500,"Chưa xử lý được yêu cầu.")
 }
 @ExceptionHandler(Exception::class)
 fun unexpected() = response(500,"Chưa xử lý được yêu cầu. Vui lòng thử lại.")
 private fun response(status: Int,message: String,code: String="request_failed") = ResponseEntity.status(status).body(mapOf("error" to mapOf("code" to code,"message" to message)))
}
