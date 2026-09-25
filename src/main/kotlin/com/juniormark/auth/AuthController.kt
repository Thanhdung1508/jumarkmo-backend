package com.juniormark.auth

import jakarta.servlet.http.HttpServletRequest
import jakarta.servlet.http.HttpServletResponse
import org.springframework.web.bind.annotation.*

/** Lớp HTTP mỏng, giữ nguyên hợp đồng {data:{session:...}} mà frontend đang sử dụng. */
@RestController
@RequestMapping("/api/auth")
class AuthController(
    private val service: AuthService,
    private val sessions: SessionService,
    private val limits: AuthRateLimiter
) {
    @GetMapping("/session")
    fun session(request: HttpServletRequest): Map<String, Any?> =
        mapOf("data" to mapOf("session" to sessions.current(request)?.publicData()))

    @PostMapping("/signup")
    fun signup(@RequestBody body: Map<String, Any?>, request: HttpServletRequest, response: HttpServletResponse): Map<String, Any?> {
        limit(request)
        return respond(service.signup(body, request.remoteAddr), response)
    }

    @PostMapping("/signin")
    fun signin(@RequestBody body: Map<String, Any?>, request: HttpServletRequest, response: HttpServletResponse): Map<String, Any?> {
        limit(request)
        return respond(service.signin(body, sessions.current(request)), response)
    }

    @PostMapping("/signout")
    fun signout(@RequestBody body: Map<String, Any?>, request: HttpServletRequest, response: HttpServletResponse): Map<String, Any?> {
        limit(request)
        return respond(service.signout(body, sessions.current(request)), response)
    }

    @PostMapping("/reset")
    fun reset(@RequestBody body: Map<String, Any?>, request: HttpServletRequest, response: HttpServletResponse): Map<String, Any?> {
        limit(request)
        return respond(service.reset(body), response)
    }

    @PostMapping("/recover")
    fun recover(@RequestBody body: Map<String, Any?>, request: HttpServletRequest, response: HttpServletResponse): Map<String, Any?> {
        limit(request)
        return respond(service.recover(body), response)
    }

    @PostMapping("/password")
    fun password(@RequestBody body: Map<String, Any?>, request: HttpServletRequest, response: HttpServletResponse): Map<String, Any?> {
        limit(request)
        return respond(service.changePassword(body, sessions.current(request)), response)
    }

    private fun limit(request: HttpServletRequest) = limits.check("ip:${request.remoteAddr}", 120, 600)

    private fun respond(result: AuthResult, response: HttpServletResponse): Map<String, Any?> {
        result.cookie?.let { sessions.setCookie(response, it) }
        return mapOf("data" to result.data)
    }
}
