package com.juniormark.config

import com.fasterxml.jackson.databind.ObjectMapper
import jakarta.servlet.FilterChain
import jakarta.servlet.ReadListener
import jakarta.servlet.ServletInputStream
import jakarta.servlet.http.HttpServletRequest
import jakarta.servlet.http.HttpServletRequestWrapper
import jakarta.servlet.http.HttpServletResponse
import org.springframework.beans.factory.annotation.Value
import org.springframework.stereotype.Component
import org.springframework.web.filter.OncePerRequestFilter
import java.io.ByteArrayInputStream
import java.io.BufferedReader
import java.io.InputStreamReader

/** Cookie chỉ nhận qua cùng origin. Mọi POST bắt buộc JSON, tối đa 64 KiB. */
@Component
class ApiRequestFilter(@Value("\${app.origin}") private val origin: String, private val mapper: ObjectMapper): OncePerRequestFilter() {
 override fun shouldNotFilter(request: HttpServletRequest) = !request.requestURI.startsWith("/api/")
 override fun doFilterInternal(req: HttpServletRequest,res: HttpServletResponse,chain: FilterChain) {
  res.setHeader("Cache-Control","no-store")
  res.setHeader("X-Content-Type-Options","nosniff")
  fun reject(status: Int,message: String) {
   res.status=status; res.contentType="application/json"; res.characterEncoding="UTF-8"
   mapper.writeValue(res.writer,mapOf("error" to mapOf("code" to "request_failed","message" to message)))
  }
  val from=req.getHeader("Origin")
  if(from!=null && from!=origin) { reject(403,"Origin không hợp lệ."); return }
  if(req.method=="POST") {
   if(from!=origin || req.contentType?.substringBefore(';')?.trim()!="application/json") { reject(403,"Yêu cầu không hợp lệ."); return }
   val body=req.inputStream.readNBytes(65537)
   if(body.size>65536) { reject(413,"Dữ liệu quá lớn."); return }
   // Đọc trước để giới hạn kích thước, sau đó cung cấp lại body cho Jackson.
   val wrapped=object: HttpServletRequestWrapper(req) {
    override fun getInputStream(): ServletInputStream {
     val stream=ByteArrayInputStream(body)
     return object: ServletInputStream() {
      override fun read()=stream.read()
      override fun isFinished()=stream.available()==0
      override fun isReady()=true
      override fun setReadListener(listener: ReadListener) { throw UnsupportedOperationException("Synchronous JSON only") }
     }
    }
    override fun getReader()=BufferedReader(InputStreamReader(inputStream,Charsets.UTF_8))
   }
   chain.doFilter(wrapped,res)
  } else chain.doFilter(req,res)
 }
}
