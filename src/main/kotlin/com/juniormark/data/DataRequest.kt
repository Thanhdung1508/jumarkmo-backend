package com.juniormark.data

/** Hợp đồng JSON đang dùng bởi frontend; tên cột được kiểm tra qua danh sách cho phép. */
data class DataRequest(
 val table: String, val operation: String = "select", val columns: String? = null,
 val filters: List<DataFilter> = emptyList(), val order: List<DataOrder> = emptyList(),
 val offset: Int = 0, val limit: Int = 1000, val cardinality: String? = null,
 val values: Map<String, Any?> = emptyMap()
)
data class DataFilter(val column: String, val value: Any?)
data class DataOrder(val column: String, val ascending: Boolean = true)
data class RpcRequest(val name: String, val args: Map<String,Any?> = emptyMap())
