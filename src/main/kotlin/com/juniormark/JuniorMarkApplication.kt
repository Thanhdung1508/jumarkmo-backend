package com.juniormark

import org.springframework.boot.autoconfigure.SpringBootApplication
import org.springframework.boot.runApplication

/** Điểm bắt đầu: chạy main này trong IntelliJ để bật API Kotlin. */
@SpringBootApplication
class JuniorMarkApplication

fun main(args: Array<String>) { runApplication<JuniorMarkApplication>(*args) }
