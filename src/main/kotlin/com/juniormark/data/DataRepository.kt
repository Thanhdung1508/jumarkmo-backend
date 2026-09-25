package com.juniormark.data

import com.juniormark.database.Database
import com.juniormark.common.ApiException
import org.springframework.stereotype.Repository

@Repository
class DataRepository(private val db: Database) {
 // Chỉ gọi với tên bảng/cột đã qua DataPolicy; giá trị luôn bind bằng dấu ?.
 private fun q(name: String) = "\"" + name + "\""
 fun query(userId: String?, r: DataRequest, p: TablePolicy, columns: List<String>): List<Map<String,Any?>> = db.asUser(userId) { c ->
  val params=mutableListOf<Any?>()
  val select=columns.joinToString(",") { q(it) }
  val table="public."+q(r.table)
  fun where(): String = if(r.filters.isEmpty()) "" else " where " + r.filters.joinToString(" and ") { params.add(it.value); q(it.column)+"=?" }
  val sql=when(r.operation) {
   "select" -> "select $select from $table"+where()+
    (if(r.order.isEmpty()) "" else " order by "+r.order.joinToString(",") { q(it.column)+if(it.ascending) " asc" else " desc" })+
    " limit ? offset ?".also { params.add(r.limit); params.add(r.offset) }
   "delete" -> "delete from $table"+where()+" returning $select"
   "update" -> "update $table set "+r.values.entries.joinToString(",") { params.add(it.value); q(it.key)+"=?" }+where()+" returning $select"
   else -> {
    params.addAll(r.values.values)
    "insert into $table ("+r.values.keys.joinToString(",") { q(it) }+") values ("+r.values.keys.joinToString(",") { "?" }+")"+
    (if(r.operation=="upsert") " on conflict ("+p.key.joinToString(",") { q(it) }+") do update set "+r.values.keys.joinToString(",") { q(it)+"=excluded."+q(it) } else "")+" returning $select"
   }
  }
  val rows=db.query(c,sql,*params.toTypedArray())
  // Kiểm tra trước COMMIT để yêu cầu single thất bại không lưu thay đổi nhiều dòng.
  if(r.cardinality=="single" && rows.size!=1) throw ApiException(404,"Không tìm thấy bản ghi.","not_found")
  if(r.cardinality=="maybeSingle" && rows.size>1) throw ApiException(409,"Có nhiều hơn một bản ghi.")
  rows
 }
 fun rpc(userId: String?, r: RpcRequest): Any? = db.asUser(userId) { c ->
  val args=r.args.keys.joinToString(",") { q(it)+" => ?" }
  val call="public."+q(r.name)+"("+args+")"
  if(r.name in listOf("my_archive_messages","get_message_feed")) db.query(c,"select * from $call",*r.args.values.toTypedArray())
  else db.query(c,"select $call as data",*r.args.values.toTypedArray()).first()["data"]
 }
}
