package com.juniormark.data

import com.juniormark.auth.SessionService
import com.juniormark.database.Database
import jakarta.servlet.http.HttpServletRequest
import org.springframework.web.bind.annotation.*

/** Controller chỉ nhận JSON và trả JSON; nghiệp vụ nằm trong Service. */
@RestController
@RequestMapping("/api")
class DataController(private val service: DataService, private val sessions: SessionService, private val db: Database) {
 @PostMapping("/data") fun query(@RequestBody input: DataRequest, request: HttpServletRequest) = mapOf("data" to service.query(sessions.userId(request),input))
 @PostMapping("/rpc") fun rpc(@RequestBody input: RpcRequest, request: HttpServletRequest) = mapOf("data" to service.rpc(sessions.userId(request),input))
 @GetMapping("/health") fun health(): Map<String,Any> { db.query("select 1"); return mapOf("ok" to true, "backend" to "kotlin") }
}
