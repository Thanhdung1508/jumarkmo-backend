package com.juniormark.config

import com.zaxxer.hikari.HikariConfig
import com.zaxxer.hikari.HikariDataSource
import org.springframework.beans.factory.annotation.Value
import org.springframework.context.annotation.Bean
import org.springframework.context.annotation.Configuration
import java.nio.file.Files
import java.nio.file.Path
import javax.sql.DataSource

@Configuration
class DatabaseConfig {
 /** Cấu hình chỉ ở server. Không đưa password vào biến VITE_* hoặc Git. */
 @Bean
 fun dataSource(@Value("\${app.database.url}") url: String,
                @Value("\${app.database.username}") username: String,
                @Value("\${app.database.password}") password: String,
                @Value("\${app.database.password-file}") passwordFile: String): DataSource {
   val secret = password.ifBlank { Files.readString(Path.of(passwordFile)).trim() }
   return HikariDataSource(HikariConfig().apply {
     jdbcUrl=url; this.username=username; this.password=secret
     maximumPoolSize=10; minimumIdle=1; connectionTimeout=10000
     addDataSourceProperty("stringtype", "unspecified")
   })
 }
}
