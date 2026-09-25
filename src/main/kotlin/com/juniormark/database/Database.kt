package com.juniormark.database

import com.fasterxml.jackson.databind.ObjectMapper
import org.postgresql.util.PGobject
import org.springframework.stereotype.Component
import java.sql.Connection
import java.sql.PreparedStatement
import java.sql.ResultSet
import java.sql.Timestamp
import java.util.UUID
import javax.sql.DataSource

/** JDBC dùng tham số ?; tuyệt đối không nối giá trị do người dùng nhập vào SQL. */
@Component
class Database(private val source: DataSource, private val mapper: ObjectMapper) {
 fun <T> transaction(action: (Connection) -> T): T = source.connection.use { c ->
   c.autoCommit=false
   try { val result=action(c); c.commit(); result } catch(e: Exception) { c.rollback(); throw e }
 }
 /** SET LOCAL chỉ có hiệu lực trong transaction; connection tái sử dụng không giữ quyền user cũ. */
 fun <T> asUser(userId: String?, action: (Connection) -> T): T = transaction { c ->
   c.createStatement().use { it.execute("set local role " + if(userId == null) "anon" else "authenticated") }
   query(c, "select set_config('request.jwt.claim.sub', ?, true)", userId ?: "")
   action(c)
 }
 fun query(sql: String, vararg params: Any?): List<Map<String, Any?>> = source.connection.use { query(it,sql,*params) }
 fun query(c: Connection, sql: String, vararg params: Any?): List<Map<String, Any?>> = c.prepareStatement(sql).use { s ->
   bind(s,params); s.executeQuery().use { rows(it) }
 }
 fun execute(c: Connection, sql: String, vararg params: Any?): Int = c.prepareStatement(sql).use { s -> bind(s,params); s.executeUpdate() }
 private fun bind(s: PreparedStatement, params: Array<out Any?>) {
   params.forEachIndexed { i,v -> s.setObject(i+1, when(v) {
     is Map<*,*>, is List<*> -> PGobject().apply { type="jsonb"; value=mapper.writeValueAsString(v) }
     else -> v
   }) }
 }
 private fun rows(r: ResultSet): List<Map<String,Any?>> = buildList {
   while(r.next()) add((1..r.metaData.columnCount).associate { i -> r.metaData.getColumnLabel(i) to when(val v=r.getObject(i)) {
     is PGobject -> if(v.type in listOf("json","jsonb")) mapper.readValue(v.value,Any::class.java) else v.value
     is UUID -> v.toString()
     is Timestamp -> v.toInstant().toString()
     is java.sql.Date -> v.toLocalDate().toString()
     is java.sql.Array -> (v.array as Array<*>).toList()
     else -> v
   } })
 }
}
