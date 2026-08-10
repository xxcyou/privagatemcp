package com.sukishell.root_mcp

import android.app.usage.UsageStatsManager
import android.content.ContentProviderOperation
import android.content.ContentUris
import android.content.ContentValues
import android.content.Context
import android.provider.CallLog
import android.provider.CalendarContract
import android.provider.ContactsContract
import android.provider.Telephony
import android.telephony.SmsManager
import java.util.TimeZone

/** 数据工具：短信 / 通讯录 / 通话记录 / 日历 / 使用统计 */
object DataTools {

    fun smsList(context: Context, limit: Int): List<Map<String, Any?>>? {
        if (!(PermHelper.checkAll(context)["sms"] as Boolean)) return null
        return try {
            val out = mutableListOf<Map<String, Any?>>()
            val cursor = context.contentResolver.query(
                Telephony.Sms.Inbox.CONTENT_URI,
                arrayOf(Telephony.Sms._ID, Telephony.Sms.Inbox.ADDRESS, Telephony.Sms.Inbox.BODY, Telephony.Sms.Inbox.DATE, Telephony.Sms.Inbox.READ),
                null, null, "${Telephony.Sms.Inbox.DATE} DESC LIMIT ${limit.coerceIn(1, 200)}"
            )
            cursor?.use { c ->
                val iId = c.getColumnIndexOrThrow(Telephony.Sms._ID)
                val iAddr = c.getColumnIndexOrThrow(Telephony.Sms.Inbox.ADDRESS)
                val iBody = c.getColumnIndexOrThrow(Telephony.Sms.Inbox.BODY)
                val iDate = c.getColumnIndexOrThrow(Telephony.Sms.Inbox.DATE)
                val iRead = c.getColumnIndexOrThrow(Telephony.Sms.Inbox.READ)
                while (c.moveToNext()) {
                    out.add(mapOf(
                        "id" to c.getLong(iId),
                        "from" to c.getString(iAddr),
                        "body" to c.getString(iBody),
                        "time" to c.getLong(iDate),
                        "read" to (c.getInt(iRead) == 1),
                    ))
                }
            }
            out
        } catch (_: Throwable) {
            null
        }
    }

    fun smsSend(number: String, text: String): Boolean {
        return try {
            SmsManager.getDefault().sendTextMessage(number, null, text, null, null)
            true
        } catch (_: Throwable) {
            false
        }
    }

    fun contacts(context: Context, limit: Int): List<Map<String, Any?>>? {
        if (!(PermHelper.checkAll(context)["contacts"] as Boolean)) return null
        return try {
            val out = mutableListOf<Map<String, Any?>>()
            val cursor = context.contentResolver.query(
                ContactsContract.CommonDataKinds.Phone.CONTENT_URI,
                arrayOf(
                    ContactsContract.CommonDataKinds.Phone.CONTACT_ID,
                    ContactsContract.CommonDataKinds.Phone.DISPLAY_NAME,
                    ContactsContract.CommonDataKinds.Phone.NUMBER,
                ),
                null, null, "${ContactsContract.CommonDataKinds.Phone.DISPLAY_NAME} LIMIT ${limit.coerceIn(1, 500)}"
            )
            cursor?.use { c ->
                val iCid = c.getColumnIndexOrThrow(ContactsContract.CommonDataKinds.Phone.CONTACT_ID)
                val iName = c.getColumnIndexOrThrow(ContactsContract.CommonDataKinds.Phone.DISPLAY_NAME)
                val iNum = c.getColumnIndexOrThrow(ContactsContract.CommonDataKinds.Phone.NUMBER)
                while (c.moveToNext()) {
                    out.add(mapOf(
                        "id" to c.getLong(iCid),
                        "name" to c.getString(iName),
                        "number" to c.getString(iNum),
                    ))
                }
            }
            out
        } catch (_: Throwable) {
            null
        }
    }

    fun callLog(context: Context, limit: Int): List<Map<String, Any?>>? {
        if (!(PermHelper.checkAll(context)["call_log"] as Boolean)) return null
        return try {
            val out = mutableListOf<Map<String, Any?>>()
            // CallLog provider 不支持 SQL LIMIT 子句 → 用标准 limit 参数（API 24+）
            val uri = CallLog.Calls.CONTENT_URI.buildUpon()
                .appendQueryParameter(CallLog.Calls.LIMIT_PARAM_KEY, limit.coerceIn(1, 200).toString())
                .build()
            val cursor = context.contentResolver.query(
                uri,
                arrayOf(CallLog.Calls._ID, CallLog.Calls.NUMBER, CallLog.Calls.TYPE, CallLog.Calls.DURATION, CallLog.Calls.DATE),
                null, null, "${CallLog.Calls.DATE} DESC"
            )
            cursor?.use { c ->
                val iId = c.getColumnIndexOrThrow(CallLog.Calls._ID)
                val iNum = c.getColumnIndexOrThrow(CallLog.Calls.NUMBER)
                val iType = c.getColumnIndexOrThrow(CallLog.Calls.TYPE)
                val iDur = c.getColumnIndexOrThrow(CallLog.Calls.DURATION)
                val iDate = c.getColumnIndexOrThrow(CallLog.Calls.DATE)
                while (c.moveToNext()) {
                    val type = when (c.getInt(iType)) {
                        CallLog.Calls.INCOMING_TYPE -> "incoming"
                        CallLog.Calls.OUTGOING_TYPE -> "outgoing"
                        CallLog.Calls.MISSED_TYPE -> "missed"
                        else -> "other"
                    }
                    out.add(mapOf(
                        "id" to c.getLong(iId),
                        "number" to c.getString(iNum),
                        "type" to type,
                        "duration_s" to c.getLong(iDur),
                        "time" to c.getLong(iDate),
                    ))
                }
            }
            out
        } catch (_: Throwable) {
            null
        }
    }

    fun calendar(context: Context, limit: Int): List<Map<String, Any?>>? {
        if (!(PermHelper.checkAll(context)["calendar"] as Boolean)) return null
        return try {
            val out = mutableListOf<Map<String, Any?>>()
            val now = System.currentTimeMillis()
            val cursor = context.contentResolver.query(
                CalendarContract.Events.CONTENT_URI,
                arrayOf(
                    CalendarContract.Events._ID,
                    CalendarContract.Events.TITLE,
                    CalendarContract.Events.DTSTART,
                    CalendarContract.Events.DTEND,
                    CalendarContract.Events.DESCRIPTION,
                ),
                "${CalendarContract.Events.DTSTART} >= ?",
                arrayOf((now - 86400000L).toString()),
                "${CalendarContract.Events.DTSTART} ASC LIMIT ${limit.coerceIn(1, 100)}"
            )
            cursor?.use { c ->
                val iId = c.getColumnIndexOrThrow(CalendarContract.Events._ID)
                val iTitle = c.getColumnIndexOrThrow(CalendarContract.Events.TITLE)
                val iStart = c.getColumnIndexOrThrow(CalendarContract.Events.DTSTART)
                val iEnd = c.getColumnIndexOrThrow(CalendarContract.Events.DTEND)
                val iDesc = c.getColumnIndexOrThrow(CalendarContract.Events.DESCRIPTION)
                while (c.moveToNext()) {
                    out.add(mapOf(
                        "id" to c.getLong(iId),
                        "title" to c.getString(iTitle),
                        "start" to c.getLong(iStart),
                        "end" to c.getLong(iEnd),
                        "description" to c.getString(iDesc),
                    ))
                }
            }
            out
        } catch (_: Throwable) {
            null
        }
    }

    fun usage(context: Context, days: Int): List<Map<String, Any?>>? {
        if (!(PermHelper.checkAll(context)["usage_stats"] as Boolean)) return null
        return try {
            val usm = context.getSystemService(Context.USAGE_STATS_SERVICE) as UsageStatsManager
            val end = System.currentTimeMillis()
            val start = end - days.coerceIn(1, 30) * 86400000L
            val stats = usm.queryUsageStats(UsageStatsManager.INTERVAL_DAILY, start, end)
            val aggregated = HashMap<String, Long>()
            for (s in stats) {
                aggregated.merge(s.packageName, s.totalTimeInForeground, Long::plus)
            }
            aggregated.entries
                .sortedByDescending { it.value }
                .take(30)
                .map { mapOf("package" to it.key, "foreground_ms" to it.value) }
        } catch (_: Throwable) {
            null
        }
    }

    // ---------- 短信写操作 ----------

    /** 短信会话分组：按 thread_id 聚合，取每会话最新一条 */
    fun smsThreads(context: Context, limit: Int): List<Map<String, Any?>>? {
        if (!(PermHelper.checkAll(context)["sms"] as Boolean)) return null
        return try {
            val out = mutableListOf<Map<String, Any?>>()
            val cursor = context.contentResolver.query(
                Telephony.Sms.CONTENT_URI,
                arrayOf(
                    Telephony.Sms.THREAD_ID,
                    Telephony.Sms.ADDRESS,
                    Telephony.Sms.BODY,
                    Telephony.Sms.DATE,
                    Telephony.Sms.READ,
                ),
                null, null, "${Telephony.Sms.DATE} DESC"
            )
            val seen = HashSet<Long>()
            cursor?.use { c ->
                val iThread = c.getColumnIndexOrThrow(Telephony.Sms.THREAD_ID)
                val iAddr = c.getColumnIndexOrThrow(Telephony.Sms.ADDRESS)
                val iBody = c.getColumnIndexOrThrow(Telephony.Sms.BODY)
                val iDate = c.getColumnIndexOrThrow(Telephony.Sms.DATE)
                val iRead = c.getColumnIndexOrThrow(Telephony.Sms.READ)
                while (c.moveToNext() && out.size < limit.coerceIn(1, 100)) {
                    val tid = c.getLong(iThread)
                    if (!seen.add(tid)) continue
                    out.add(mapOf(
                        "thread_id" to tid,
                        "address" to c.getString(iAddr),
                        "last_body" to c.getString(iBody),
                        "last_time" to c.getLong(iDate),
                        "unread" to (c.getInt(iRead) == 0),
                    ))
                }
            }
            out
        } catch (_: Throwable) {
            null
        }
    }

    /** 删除短信：按 id 或号码；number 模式删除该号码全部短信 */
    fun smsDelete(context: Context, id: Long?, number: String?): Boolean {
        if (!(PermHelper.checkAll(context)["sms"] as Boolean)) return false
        return try {
            val (where, args) = when {
                id != null -> "${Telephony.Sms._ID} = ?" to arrayOf(id.toString())
                !number.isNullOrEmpty() -> "${Telephony.Sms.ADDRESS} = ?" to arrayOf(number)
                else -> return false
            }
            context.contentResolver.delete(Telephony.Sms.CONTENT_URI, where, args) > 0
        } catch (_: Throwable) {
            false
        }
    }

    /** 标记短信已读：id 为空则全部标记 */
    fun smsMarkRead(context: Context, id: Long?): Boolean {
        if (!(PermHelper.checkAll(context)["sms"] as Boolean)) return false
        return try {
            val values = ContentValues().apply { put(Telephony.Sms.READ, 1) }
            val where = if (id != null) "${Telephony.Sms._ID} = ?" else "${Telephony.Sms.READ} = 0"
            val args = if (id != null) arrayOf(id.toString()) else null
            context.contentResolver.update(Telephony.Sms.CONTENT_URI, values, where, args) >= 0
        } catch (_: Throwable) {
            false
        }
    }

    // ---------- 通讯录写操作 ----------

    /** 新增联系人（匿名账号 RawContact + 姓名/号码） */
    fun contactAdd(context: Context, name: String, number: String): Boolean {
        if (!(PermHelper.checkAll(context)["contacts"] as Boolean)) return false
        return try {
            val rawUri = context.contentResolver.insert(
                ContactsContract.RawContacts.CONTENT_URI, ContentValues()
            ) ?: return false
            val rawId = ContentUris.parseId(rawUri)
            val ops = ArrayList<ContentProviderOperation>()
            if (name.isNotBlank()) {
                ops.add(ContentProviderOperation.newInsert(ContactsContract.Data.CONTENT_URI)
                    .withValue(ContactsContract.Data.RAW_CONTACT_ID, rawId)
                    .withValue(ContactsContract.Data.MIMETYPE, ContactsContract.CommonDataKinds.StructuredName.CONTENT_ITEM_TYPE)
                    .withValue(ContactsContract.CommonDataKinds.StructuredName.DISPLAY_NAME, name)
                    .build())
            }
            if (number.isNotBlank()) {
                ops.add(ContentProviderOperation.newInsert(ContactsContract.Data.CONTENT_URI)
                    .withValue(ContactsContract.Data.RAW_CONTACT_ID, rawId)
                    .withValue(ContactsContract.Data.MIMETYPE, ContactsContract.CommonDataKinds.Phone.CONTENT_ITEM_TYPE)
                    .withValue(ContactsContract.CommonDataKinds.Phone.NUMBER, number)
                    .withValue(ContactsContract.CommonDataKinds.Phone.TYPE, ContactsContract.CommonDataKinds.Phone.TYPE_MOBILE)
                    .build())
            }
            if (ops.isNotEmpty()) {
                context.contentResolver.applyBatch(ContactsContract.AUTHORITY, ops)
            }
            true
        } catch (_: Throwable) {
            false
        }
    }

    /** 更新联系人：按 contact_id 更新姓名/号码（只更新非空字段） */
    fun contactUpdate(context: Context, contactId: Long, name: String?, number: String?): Boolean {
        if (!(PermHelper.checkAll(context)["contacts"] as Boolean)) return false
        return try {
            val ops = ArrayList<ContentProviderOperation>()
            if (!name.isNullOrEmpty()) {
                ops.add(ContentProviderOperation.newUpdate(ContactsContract.Data.CONTENT_URI)
                    .withSelection(
                        "${ContactsContract.Data.CONTACT_ID} = ? AND ${ContactsContract.Data.MIMETYPE} = ?",
                        arrayOf(contactId.toString(), ContactsContract.CommonDataKinds.StructuredName.CONTENT_ITEM_TYPE)
                    )
                    .withValue(ContactsContract.CommonDataKinds.StructuredName.DISPLAY_NAME, name)
                    .build())
            }
            if (!number.isNullOrEmpty()) {
                ops.add(ContentProviderOperation.newUpdate(ContactsContract.Data.CONTENT_URI)
                    .withSelection(
                        "${ContactsContract.Data.CONTACT_ID} = ? AND ${ContactsContract.Data.MIMETYPE} = ?",
                        arrayOf(contactId.toString(), ContactsContract.CommonDataKinds.Phone.CONTENT_ITEM_TYPE)
                    )
                    .withValue(ContactsContract.CommonDataKinds.Phone.NUMBER, number)
                    .build())
            }
            if (ops.isEmpty()) return false
            context.contentResolver.applyBatch(ContactsContract.AUTHORITY, ops)
            true
        } catch (_: Throwable) {
            false
        }
    }

    /** 删除联系人：按 contact_id。Provider 路径（Contacts 表 → RawContacts 表）→ root su 兜底（MIUI 等 ROM 拒绝 app uid 删除） */
    fun contactDelete(context: Context, contactId: Long): Boolean {
        if (!(PermHelper.checkAll(context)["contacts"] as Boolean)) return false
        return try {
            var deleted = 0
            // 路径 1：聚合表 Contacts（AOSP 推荐）
            try {
                deleted = context.contentResolver.delete(
                    ContactsContract.Contacts.CONTENT_URI,
                    "${ContactsContract.Contacts._ID} = ?", arrayOf(contactId.toString())
                )
            } catch (_: Throwable) {}
            // 路径 2：RawContacts
            if (deleted == 0) {
                try {
                    deleted = context.contentResolver.delete(
                        ContactsContract.RawContacts.CONTENT_URI,
                        "${ContactsContract.RawContacts.CONTACT_ID} = ?", arrayOf(contactId.toString())
                    )
                } catch (_: Throwable) {
                }
            }
            // 路径 3：root su 执行 content delete（MIUI 拒绝 app uid 删除时兜底）
            if (deleted == 0) {
                deleted = contactDeleteViaRoot(contactId)
            }
            deleted > 0
        } catch (_: Throwable) {
            false
        }
    }

    private fun contactDeleteViaRoot(contactId: Long): Int {
        val suCandidates = listOf(
            "/data/adb/ksu/bin/su", "/data/adb/ap/bin/su",
            "/data/adb/sui/su", "/system/bin/su", "/sbin/su"
        )
        for (su in suCandidates) {
            if (!java.io.File(su).exists()) continue
            try {
                val p = ProcessBuilder(
                    su, "-c",
                    "content delete --uri content://com.android.contacts/raw_contacts --where \"contact_id=$contactId\""
                ).redirectErrorStream(true).start()
                if (!p.waitFor(10, java.util.concurrent.TimeUnit.SECONDS)) {
                    p.destroy(); continue
                }
                if (p.exitValue() == 0) return 1
            } catch (_: Throwable) {}
        }
        return 0
    }

    // ---------- 通话记录写操作 ----------

    /** 删除通话记录：all=true 清空；否则按 id 或号码 */
    fun callLogDelete(context: Context, id: Long?, number: String?, all: Boolean): Boolean {
        if (!(PermHelper.checkAll(context)["call_log"] as Boolean)) return false
        return try {
            val (where, args) = when {
                all -> null to null
                id != null -> "${CallLog.Calls._ID} = ?" to arrayOf(id.toString())
                !number.isNullOrEmpty() -> "${CallLog.Calls.NUMBER} = ?" to arrayOf(number)
                else -> return false
            }
            context.contentResolver.delete(CallLog.Calls.CONTENT_URI, where, args) >= 0
        } catch (_: Throwable) {
            false
        }
    }

    // ---------- 日历写操作 ----------

    private fun firstWritableCalendarId(context: Context): Long? {
        return try {
            val cursor = context.contentResolver.query(
                CalendarContract.Calendars.CONTENT_URI,
                arrayOf(CalendarContract.Calendars._ID),
                "${CalendarContract.Calendars.CALENDAR_ACCESS_LEVEL} >= ${CalendarContract.Calendars.CAL_ACCESS_CONTRIBUTOR}",
                null, null
            )
            cursor?.use { if (it.moveToFirst()) return it.getLong(0) }
            null
        } catch (_: Throwable) {
            null
        }
    }

    /** 新增日历事件（自动选第一个可写日历） */
    fun calendarAdd(context: Context, title: String, startMs: Long, endMs: Long, description: String?): Boolean {
        if (!(PermHelper.checkAll(context)["calendar"] as Boolean)) return false
        return try {
            val calId = firstWritableCalendarId(context) ?: return false
            val cv = ContentValues().apply {
                put(CalendarContract.Events.CALENDAR_ID, calId)
                put(CalendarContract.Events.TITLE, title)
                put(CalendarContract.Events.DTSTART, startMs)
                put(CalendarContract.Events.DTEND, endMs)
                if (!description.isNullOrEmpty()) put(CalendarContract.Events.DESCRIPTION, description)
                put(CalendarContract.Events.EVENT_TIMEZONE, TimeZone.getDefault().id)
            }
            context.contentResolver.insert(CalendarContract.Events.CONTENT_URI, cv) != null
        } catch (_: Throwable) {
            false
        }
    }

    /** 删除日历事件：按事件 id */
    fun calendarDelete(context: Context, id: Long): Boolean {
        if (!(PermHelper.checkAll(context)["calendar"] as Boolean)) return false
        return try {
            context.contentResolver.delete(
                CalendarContract.Events.CONTENT_URI,
                "${CalendarContract.Events._ID} = ?", arrayOf(id.toString())
            ) >= 0
        } catch (_: Throwable) {
            false
        }
    }
}
