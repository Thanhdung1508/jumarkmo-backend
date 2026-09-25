package com.juniormark.data

import com.juniormark.common.ApiException
import org.springframework.stereotype.Service

@Service
class DataService(private val repository: DataRepository) {
 /** Kiểm tra yêu cầu trước khi tạo SQL. RLS trong PostgreSQL là lớp bảo vệ tiếp theo. */
 fun query(userId: String?, request: DataRequest): Any? {
  val policy=DataPolicy.tables[request.table] ?: throw ApiException(400,"Bảng dữ liệu không hợp lệ.")
  if(request.operation !in policy.operations) throw ApiException(400,"Thao tác không hợp lệ.")
  if(userId==null && !(request.table=="fan_messages" && request.operation=="select")) throw ApiException(401,"Vui lòng đăng nhập.","session_expired")
  val columns=request.columns?.split(',')?.map { it.trim() } ?: policy.read
  if(columns.isEmpty() || columns.any { it !in policy.read }) throw ApiException(400,"Cột dữ liệu không hợp lệ.")
  if(request.limit !in 1..1000 || request.offset !in 0..100000 || request.filters.size>12 || request.order.size>4 || request.cardinality !in listOf(null,"single","maybeSingle")) throw ApiException(400,"Phân trang không hợp lệ.")
  request.filters.forEach { f ->
   if(f.column !in policy.read || f.value !is String && f.value !is Number && f.value !is Boolean) throw ApiException(400,"Bộ lọc không hợp lệ.")
  }
  if(request.order.any { it.column !in policy.read }) throw ApiException(400,"Sắp xếp không hợp lệ.")
  if(request.operation in listOf("update","delete") && request.filters.isEmpty()) throw ApiException(400,"Cần chọn bản ghi.")
  if(request.operation in listOf("insert","update","upsert")) {
   if(request.values.isEmpty() || request.values.keys.any { it !in policy.write }) throw ApiException(400,"Trường cập nhật không hợp lệ.")
   if(request.values.containsKey("user_id") && request.values["user_id"] != userId) throw ApiException(403,"Không thể sửa dữ liệu tài khoản khác.")
  }
  val rows=repository.query(userId,request,policy,columns)
  return if(request.cardinality==null) rows else rows.firstOrNull()
 }
 fun rpc(userId: String?, request: RpcRequest): Any? {
  val allowed=DataPolicy.functions[request.name] ?: throw ApiException(400,"Hàm dữ liệu không hợp lệ.")
  if(request.args.keys.any { it !in allowed }) throw ApiException(400,"Tham số không hợp lệ.")
  if(userId==null && request.name !in DataPolicy.publicFunctions) throw ApiException(401,"Vui lòng đăng nhập.","session_expired")
  return repository.rpc(userId,request)
 }
}
