package com.juniormark.data

/** Mỗi bảng khai báo rõ cột đọc, cột ghi và thao tác. Client không được tự chọn bảng hệ thống. */
data class TablePolicy(val read: List<String>, val write: List<String>, val operations: Set<String>, val key: List<String> = emptyList())
object DataPolicy {
 val tables = mapOf(
  "fan_profiles" to TablePolicy(listOf("id","display_name","bio","avatar_url","created_at"),listOf("display_name","bio","avatar_url"),setOf("select","update")),
  "user_notes" to TablePolicy(listOf("id","user_id","title","body","created_at","updated_at"),listOf("user_id","title","body"),setOf("select","insert","update","delete")),
  "user_settings" to TablePolicy(listOf("user_id","show_country","updated_at"),listOf("user_id","show_country"),setOf("select","upsert"),listOf("user_id")),
  "archive_items" to TablePolicy(listOf("user_id","kind","item_id","payload"),listOf("user_id","kind","item_id","payload"),setOf("select","upsert","delete"),listOf("user_id","kind","item_id")),
  "fan_messages" to TablePolicy(listOf("id","kind","name","country","body","spectrum","status","created_at","country_code","position_x","position_y"),listOf("user_id","kind","name","country","body","spectrum","country_code"),setOf("select","insert","delete"))
 )
 val functions = mapOf(
  "get_catalog" to emptySet<String>(), "export_my_data" to emptySet(), "my_archive_messages" to emptySet(),
  "claim_daily_fortune" to emptySet(), "get_community_stats" to setOf("p_kind"),
  "get_message_feed" to setOf("p_kind","p_before","p_before_id","p_limit"),
  "moderate_message" to setOf("p_id","p_status")
 )
 val publicFunctions = setOf("get_catalog","get_community_stats","get_message_feed")
}
