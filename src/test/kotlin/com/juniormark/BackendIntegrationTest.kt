package com.juniormark

import com.fasterxml.jackson.databind.JsonNode
import com.fasterxml.jackson.databind.ObjectMapper
import com.juniormark.database.Database
import org.junit.jupiter.api.Assertions.*
import org.junit.jupiter.api.Test
import org.junit.jupiter.api.condition.EnabledIfEnvironmentVariable
import org.springframework.beans.factory.annotation.Autowired
import org.springframework.boot.test.context.SpringBootTest
import org.springframework.boot.test.web.server.LocalServerPort
import org.springframework.test.context.DynamicPropertyRegistry
import org.springframework.test.context.DynamicPropertySource
import java.net.URI
import java.net.http.HttpClient
import java.net.http.HttpRequest
import java.net.http.HttpResponse
import java.nio.file.Files
import java.nio.file.Path
import java.util.UUID

/** Test thật qua HTTP + PostgreSQL. Chỉ xoá các user UUID mà chính test vừa tạo. */
@SpringBootTest(webEnvironment=SpringBootTest.WebEnvironment.RANDOM_PORT)
@EnabledIfEnvironmentVariable(named="RUN_DATABASE_TESTS",matches="true")
class BackendIntegrationTest {
 @LocalServerPort private var port: Int=0
 @Autowired private lateinit var mapper: ObjectMapper
 @Autowired private lateinit var db: Database
 private val client=HttpClient.newHttpClient()
 data class Result(val data: JsonNode,val cookie: String)
 private fun post(path: String,body: Any=emptyMap<String,Any>(),cookie: String="",status: Int=200,origin: String="http://127.0.0.1:5173"): Result {
  val request=HttpRequest.newBuilder(URI("http://127.0.0.1:$port/api/$path"))
   .header("Origin",origin).header("Content-Type","application/json").header("Cookie",cookie)
   .POST(HttpRequest.BodyPublishers.ofString(mapper.writeValueAsString(body))).build()
  val response=client.send(request,HttpResponse.BodyHandlers.ofString())
  assertEquals(status,response.statusCode(),"$path: "+response.body())
  return Result(mapper.readTree(response.body()),response.headers().firstValue("set-cookie").orElse("").substringBefore(';'))
 }
 @Test fun accountDataPrivacyAndPasswordRecovery() {
  val ids=mutableListOf<String>(); val email=("test-"+UUID.randomUUID()+"@example.invalid"); val password="Test-password-394!"
  try {
   val a=post("auth/signup",mapOf("email" to email,"password" to password,"displayName" to "Alpha"))
   ids.add(a.data.at("/data/session/user/id").asText())
   val b=post("auth/signup",mapOf("email" to "b-$email","password" to password,"displayName" to "Beta"))
   ids.add(b.data.at("/data/session/user/id").asText())
   val hash=db.query("select password_hash from private.local_accounts where user_id=?",UUID.fromString(ids[0]))[0]["password_hash"].toString()
   assertTrue(hash.startsWith("scrypt:"));assertFalse(hash.contains(password))
   post("auth/signin",mapOf("email" to email,"password" to "wrong"),status=401)
   val note=post("data",mapOf("table" to "user_notes","operation" to "insert","values" to mapOf("user_id" to ids[0],"title" to "Riêng tư","body" to "Only Alpha")),a.cookie)
   val noteId=note.data.at("/data/0/id").asText()
   assertEquals(0,post("data",mapOf("table" to "user_notes"),b.cookie).data["data"].size())
   assertEquals(0,post("data",mapOf("table" to "user_notes","operation" to "update","filters" to listOf(mapOf("column" to "id","value" to noteId)),"values" to mapOf("body" to "Hacked")),b.cookie).data["data"].size())
   post("data",mapOf("table" to "user_notes","operation" to "insert","values" to mapOf("user_id" to ids[0],"title" to "Forbidden")),b.cookie,403)
   post("data",mapOf("table" to "local_accounts"),a.cookie,400)
   post("data",mapOf("table" to "fan_profiles","operation" to "update","filters" to listOf(mapOf("column" to "id","value" to ids[0])),"values" to mapOf("display_name" to "Updated Alpha","bio" to "Hello")),a.cookie)
   post("data",mapOf("table" to "user_settings","operation" to "upsert","values" to mapOf("user_id" to ids[0],"show_country" to false)),a.cookie)
   post("data",mapOf("table" to "archive_items","operation" to "upsert","values" to mapOf("user_id" to ids[0],"kind" to "page","item_id" to "profiles","payload" to mapOf("title" to "Profiles","url" to "#/profiles"))),a.cookie)
   assertFalse(post("rpc",mapOf("name" to "export_my_data"),a.cookie).data["data"].isNull)
   assertTrue(post("rpc",mapOf("name" to "get_catalog")).data.at("/data/artists").size()>=3)
   post("auth/signout",cookie=a.cookie,status=403,origin="https://wrong.invalid")
   post("auth/password",mapOf("password" to "New-pass-298!","oldPassword" to "wrong"),a.cookie,401)
   post("auth/reset",mapOf("email" to email))
   val mail=Files.list(mailDirectory).use { it.findFirst().orElseThrow() }
   val token=mapper.readTree(Files.readString(mail))["url"].asText().substringAfter("recovery=")
   val recovered=post("auth/recover",mapOf("token" to token))
   post("auth/recover",mapOf("token" to token),status=400)
   post("auth/password",mapOf("password" to "Changed-password-89!"),recovered.cookie)
   post("data",mapOf("table" to "user_notes"),a.cookie,401)
   post("auth/signin",mapOf("email" to email,"password" to password),status=401)
   val renewed=post("auth/signin",mapOf("email" to email,"password" to "Changed-password-89!"))
   assertEquals("Only Alpha",post("data",mapOf("table" to "user_notes"),renewed.cookie).data.at("/data/0/body").asText())
   post("auth/signout",mapOf("scope" to "global"),renewed.cookie)
   post("data",mapOf("table" to "user_notes"),renewed.cookie,401)
  } finally {
   db.transaction { c -> ids.forEach { db.execute(c,"delete from auth.users where id=?",UUID.fromString(it)) } }
   Files.list(mailDirectory).use { files -> files.forEach { Files.deleteIfExists(it) } };Files.deleteIfExists(mailDirectory)
  }
 }
 companion object {
  private val mailDirectory: Path=Files.createTempDirectory("juniormark-http-test-")
  @JvmStatic @DynamicPropertySource fun config(registry: DynamicPropertyRegistry) {
   registry.add("app.mail-directory") { mailDirectory.toString() }
  }
 }
}
