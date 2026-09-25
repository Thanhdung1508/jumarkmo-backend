package com.juniormark.data

import com.juniormark.common.ApiException
import org.junit.jupiter.api.Assertions.*
import org.junit.jupiter.api.Test
import org.mockito.Mockito.*

class DataServiceTest {
 private val repository=mock(DataRepository::class.java)
 private val service=DataService(repository)
 @Test fun rejectsAnonymousPrivateData() {
  assertEquals(401,assertThrows(ApiException::class.java) { service.query(null,DataRequest("user_notes")) }.status)
  verifyNoInteractions(repository)
 }
 @Test fun rejectsSystemTablesAndUnfilteredDeletion() {
  assertEquals(400,assertThrows(ApiException::class.java) { service.query("user",DataRequest("local_accounts")) }.status)
  assertEquals(400,assertThrows(ApiException::class.java) { service.query("user",DataRequest("user_notes",operation="delete")) }.status)
  verifyNoInteractions(repository)
 }
 @Test fun rejectsForgedOwnerAndSqlIdentifier() {
  assertEquals(403,assertThrows(ApiException::class.java) { service.query("a",DataRequest("user_notes",operation="insert",values=mapOf("user_id" to "b","title" to "x"))) }.status)
  assertEquals(400,assertThrows(ApiException::class.java) { service.query("a",DataRequest("user_notes",columns="id; drop table auth.users")) }.status)
  verifyNoInteractions(repository)
 }
}
