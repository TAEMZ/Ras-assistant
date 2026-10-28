package com.voice.amharic.amharic_assistant

import android.content.ContentUris
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.database.Cursor
import android.net.Uri
import android.os.Build
import android.os.Environment
import android.os.StatFs
import android.provider.ContactsContract
import android.provider.MediaStore
import android.util.Log
import android.webkit.MimeTypeMap
import androidx.core.content.FileProvider
import java.io.File

object DeviceSearchService {

    private const val TAG = "DeviceSearchService"

    /**
     * Search files across device storage using MediaStore + direct filesystem fallback.
     * Returns full real paths so users can see exactly where each file lives.
     */
    fun searchFiles(context: Context, query: String?, category: String? = "all", limit: Int = 20): List<Map<String, Any>> {
        Log.d(TAG, "=== searchFiles START === query='$query', category='$category', limit=$limit")

        // Check if we have storage permission
        val hasFullAccess = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            Environment.isExternalStorageManager()
        } else {
            true
        }
        Log.d(TAG, "Full storage access (MANAGE_EXTERNAL_STORAGE): $hasFullAccess")

        // Try MediaStore first
        val mediaStoreResults = searchViaMediaStore(context, query, category, limit)
        Log.d(TAG, "MediaStore returned ${mediaStoreResults.size} results")

        if (mediaStoreResults.isNotEmpty()) {
            return mediaStoreResults
        }

        // If MediaStore returned nothing and we have full access, fallback to direct filesystem scan
        if (hasFullAccess) {
            Log.d(TAG, "MediaStore empty — falling back to direct filesystem scan")
            val fsResults = searchViaFilesystem(query, category, limit)
            Log.d(TAG, "Filesystem scan returned ${fsResults.size} results")
            return fsResults
        }

        Log.d(TAG, "No results and no full storage access. User needs to grant MANAGE_EXTERNAL_STORAGE.")
        return emptyList()
    }

    /**
     * Search via Android MediaStore (works with scoped storage permissions)
     */
    private fun searchViaMediaStore(context: Context, query: String?, category: String?, limit: Int): List<Map<String, Any>> {
        val results = mutableListOf<Map<String, Any>>()
        val cleanQuery = query?.trim()?.lowercase() ?: ""

        val collectionUri = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            MediaStore.Files.getContentUri(MediaStore.VOLUME_EXTERNAL)
        } else {
            MediaStore.Files.getContentUri("external")
        }
        Log.d(TAG, "MediaStore collection URI: $collectionUri")

        val projection = arrayOf(
            MediaStore.Files.FileColumns._ID,
            MediaStore.Files.FileColumns.DISPLAY_NAME,
            MediaStore.Files.FileColumns.DATA,
            MediaStore.Files.FileColumns.SIZE,
            MediaStore.Files.FileColumns.DATE_MODIFIED,
            MediaStore.Files.FileColumns.MIME_TYPE
        )

        val selectionClauses = mutableListOf<String>()
        val selectionArgs = mutableListOf<String>()

        when (category?.lowercase()) {
            "pdf" -> {
                selectionClauses.add("(${MediaStore.Files.FileColumns.MIME_TYPE} = ? OR ${MediaStore.Files.FileColumns.DISPLAY_NAME} LIKE ?)")
                selectionArgs.add("application/pdf")
                selectionArgs.add("%.pdf")
            }
            "png" -> {
                selectionClauses.add("(${MediaStore.Files.FileColumns.MIME_TYPE} = ? OR ${MediaStore.Files.FileColumns.DISPLAY_NAME} LIKE ?)")
                selectionArgs.add("image/png")
                selectionArgs.add("%.png")
            }
            "image", "images" -> {
                selectionClauses.add("(${MediaStore.Files.FileColumns.MIME_TYPE} LIKE ? OR ${MediaStore.Files.FileColumns.DISPLAY_NAME} LIKE ? OR ${MediaStore.Files.FileColumns.DISPLAY_NAME} LIKE ? OR ${MediaStore.Files.FileColumns.DISPLAY_NAME} LIKE ? OR ${MediaStore.Files.FileColumns.DISPLAY_NAME} LIKE ?)")
                selectionArgs.addAll(listOf("image/%", "%.jpg", "%.jpeg", "%.png", "%.webp"))
            }
            "audio" -> {
                selectionClauses.add("(${MediaStore.Files.FileColumns.MIME_TYPE} LIKE ? OR ${MediaStore.Files.FileColumns.DISPLAY_NAME} LIKE ? OR ${MediaStore.Files.FileColumns.DISPLAY_NAME} LIKE ? OR ${MediaStore.Files.FileColumns.DISPLAY_NAME} LIKE ?)")
                selectionArgs.addAll(listOf("audio/%", "%.mp3", "%.m4a", "%.wav"))
            }
            "video", "videos" -> {
                selectionClauses.add("(${MediaStore.Files.FileColumns.MIME_TYPE} LIKE ? OR ${MediaStore.Files.FileColumns.DISPLAY_NAME} LIKE ? OR ${MediaStore.Files.FileColumns.DISPLAY_NAME} LIKE ? OR ${MediaStore.Files.FileColumns.DISPLAY_NAME} LIKE ?)")
                selectionArgs.addAll(listOf("video/%", "%.mp4", "%.mkv", "%.3gp"))
            }
            "document", "documents" -> {
                selectionClauses.add("(${MediaStore.Files.FileColumns.DISPLAY_NAME} LIKE ? OR ${MediaStore.Files.FileColumns.DISPLAY_NAME} LIKE ? OR ${MediaStore.Files.FileColumns.DISPLAY_NAME} LIKE ? OR ${MediaStore.Files.FileColumns.DISPLAY_NAME} LIKE ?)")
                selectionArgs.addAll(listOf("%.pdf", "%.doc%", "%.txt", "%.xlsx"))
            }
        }

        // Only add display name filter if query contains specific non-generic tokens
        val genericTerms = setOf(
            "pdf", "png", "jpg", "jpeg", "webp", "image", "photo", "audio", "video", "doc", "document", "file", "files",
            "photos", "images", "videos", "music", "documents", "all", "receipt", "picture", "pictures",
            "device", "phone", "storage", "in", "on", "are", "is", "my", "the", "me", "show", "find",
            "download", "downloads", "stored", "saved", "size", "their", "many", "how"
        )
        val queryTokens = cleanQuery.split(Regex("\\s+")).filter { it.isNotEmpty() && !genericTerms.contains(it) }
        if (queryTokens.isNotEmpty()) {
            val tokenClauses = queryTokens.map { "${MediaStore.Files.FileColumns.DISPLAY_NAME} LIKE ?" }
            selectionClauses.add("(${tokenClauses.joinToString(" OR ")})")
            selectionArgs.addAll(queryTokens.map { "%$it%" })
        }

        val selection = if (selectionClauses.isNotEmpty()) selectionClauses.joinToString(" AND ") else null
        // Android 10+ forbids SQL clauses like 'LIMIT' in sortOrder; sort by date modified and limit in cursor loop
        val sortOrder = "${MediaStore.Files.FileColumns.DATE_MODIFIED} DESC"

        Log.d(TAG, "MediaStore selection: $selection")
        Log.d(TAG, "MediaStore selectionArgs: $selectionArgs")

        try {
            val cursor: Cursor? = context.contentResolver.query(
                collectionUri,
                projection,
                selection,
                if (selectionArgs.isNotEmpty()) selectionArgs.toTypedArray() else null,
                sortOrder
            )

            if (cursor == null) {
                Log.e(TAG, "MediaStore cursor is NULL — likely permission denied")
                return results
            }

            Log.d(TAG, "MediaStore cursor count: ${cursor.count}")

            cursor.use {
                val idCol = it.getColumnIndexOrThrow(MediaStore.Files.FileColumns._ID)
                val nameCol = it.getColumnIndexOrThrow(MediaStore.Files.FileColumns.DISPLAY_NAME)
                val dataCol = it.getColumnIndexOrThrow(MediaStore.Files.FileColumns.DATA)
                val sizeCol = it.getColumnIndexOrThrow(MediaStore.Files.FileColumns.SIZE)
                val dateCol = it.getColumnIndexOrThrow(MediaStore.Files.FileColumns.DATE_MODIFIED)
                val mimeCol = it.getColumnIndexOrThrow(MediaStore.Files.FileColumns.MIME_TYPE)

                while (it.moveToNext() && results.size < limit) {
                    val id = it.getLong(idCol)
                    val name = it.getString(nameCol) ?: "Unknown"
                    val path = it.getString(dataCol) ?: ""
                    val size = it.getLong(sizeCol)
                    val dateModified = it.getLong(dateCol)
                    val mime = it.getString(mimeCol) ?: ""
                    val contentUri = ContentUris.withAppendedId(collectionUri, id).toString()
                    val ext = name.substringAfterLast('.', "").lowercase()

                    // Extract folder path for display
                    val folder = if (path.isNotEmpty()) {
                        path.substringBeforeLast('/', "Unknown folder")
                    } else {
                        "Unknown folder"
                    }

                    Log.d(TAG, "  Found: $name | path=$path | size=$size | mime=$mime")

                    results.add(
                        mapOf(
                            "id" to id,
                            "name" to name,
                            "path" to path,
                            "folder" to folder,
                            "uri" to contentUri,
                            "size" to size,
                            "extension" to ext,
                            "mimeType" to mime,
                            "dateModified" to dateModified
                        )
                    )
                }
            }
        } catch (e: Exception) {
            Log.e(TAG, "MediaStore query EXCEPTION: ${e.message}", e)
        }

        return results
    }

    /**
     * Direct filesystem scan — walks common directories recursively.
     * This is the fallback when MediaStore returns nothing.
     * Gives FULL real paths like /storage/emulated/0/DCIM/Camera/IMG_xxx.jpg
     */
    private fun searchViaFilesystem(query: String?, category: String?, limit: Int): List<Map<String, Any>> {
        val results = mutableListOf<Map<String, Any>>()
        val cleanQuery = query?.trim()?.lowercase() ?: ""

        // All common directories where files live on Android
        val searchRoots = mutableListOf<File>()
        val externalStorage = Environment.getExternalStorageDirectory()

        // Add all known directories
        val commonDirs = listOf(
            "Download", "Downloads", "Documents", "DCIM", "DCIM/Camera",
            "Pictures", "Music", "Movies", "Podcasts", "Ringtones",
            "Alarms", "Notifications", "Audiobooks",
            "WhatsApp/Media", "Telegram/Telegram Documents", "Telegram/Telegram Images",
            "Telegram/Telegram Video", "Telegram/Telegram Audio"
        )

        for (dir in commonDirs) {
            val f = File(externalStorage, dir)
            if (f.exists() && f.isDirectory) {
                searchRoots.add(f)
            }
        }

        // Also add the root of external storage itself for shallow scan
        if (externalStorage.exists()) {
            searchRoots.add(externalStorage)
        }

        Log.d(TAG, "Filesystem scan roots: ${searchRoots.map { it.absolutePath }}")

        // Build extension filter based on category
        val extensionFilter: Set<String>? = when (category?.lowercase()) {
            "pdf" -> setOf("pdf")
            "image" -> setOf("jpg", "jpeg", "png", "webp", "gif", "bmp", "heic", "heif")
            "audio" -> setOf("mp3", "m4a", "wav", "ogg", "flac", "aac", "wma")
            "video" -> setOf("mp4", "mkv", "avi", "3gp", "mov", "wmv", "webm")
            "document" -> setOf("pdf", "doc", "docx", "txt", "xlsx", "xls", "pptx", "ppt", "csv", "rtf")
            else -> null // all files
        }

        val visited = mutableSetOf<String>()

        for (root in searchRoots) {
            if (results.size >= limit) break
            scanDirectory(root, cleanQuery, extensionFilter, results, limit, visited, maxDepth = 5, currentDepth = 0)
        }

        // Sort by last modified descending
        return results.sortedByDescending { it["dateModified"] as? Long ?: 0L }
    }

    /**
     * Recursively scan a directory for matching files
     */
    private fun scanDirectory(
        dir: File,
        query: String,
        extensionFilter: Set<String>?,
        results: MutableList<Map<String, Any>>,
        limit: Int,
        visited: MutableSet<String>,
        maxDepth: Int,
        currentDepth: Int
    ) {
        if (results.size >= limit) return
        if (currentDepth > maxDepth) return

        val canonicalPath = try { dir.canonicalPath } catch (e: Exception) { dir.absolutePath }
        if (visited.contains(canonicalPath)) return
        visited.add(canonicalPath)

        val files = try { dir.listFiles() } catch (e: Exception) {
            Log.w(TAG, "Cannot list directory: ${dir.absolutePath} — ${e.message}")
            return
        } ?: return

        for (file in files) {
            if (results.size >= limit) return

            if (file.isDirectory) {
                // Skip hidden and system directories
                if (file.name.startsWith(".") || file.name == "Android" || file.name == "cache") continue
                scanDirectory(file, query, extensionFilter, results, limit, visited, maxDepth, currentDepth + 1)
            } else if (file.isFile && file.length() > 0) {
                val name = file.name
                val ext = name.substringAfterLast('.', "").lowercase()

                // Skip hidden files and files with no extension
                if (name.startsWith(".")) continue

                // Apply extension filter if set
                if (extensionFilter != null && ext !in extensionFilter) continue

                // Apply query filter if set (match against filename using non-generic tokens)
                val genericTerms = setOf(
                    "pdf", "image", "photo", "audio", "video", "doc", "document",
                    "file", "files", "photos", "images", "videos", "music", "documents", "all",
                    "receipt", "picture", "pictures", "device", "phone", "storage",
                    "in", "on", "are", "is", "my", "the", "me", "show", "find",
                    "download", "downloads", "stored", "saved"
                )
                val queryTokens = query.split(Regex("\\s+")).filter { it.isNotEmpty() && !genericTerms.contains(it) }
                if (queryTokens.isNotEmpty()) {
                    val matchesAny = queryTokens.any { token -> name.lowercase().contains(token) }
                    if (!matchesAny) continue
                }

                val mime = MimeTypeMap.getSingleton().getMimeTypeFromExtension(ext) ?: ""
                val folder = file.parent ?: "Unknown folder"

                results.add(
                    mapOf(
                        "id" to file.absolutePath.hashCode().toLong(),
                        "name" to name,
                        "path" to file.absolutePath,
                        "folder" to folder,
                        "uri" to Uri.fromFile(file).toString(),
                        "size" to file.length(),
                        "extension" to ext,
                        "mimeType" to mime,
                        "dateModified" to (file.lastModified() / 1000)
                    )
                )
            }
        }
    }

    /**
     * Open a file with default system viewer using content URI or FileProvider
     */
    fun openFile(context: Context, filePath: String): Boolean {
        try {
            val file = File(filePath)
            if (!file.exists()) return false

            val ext = MimeTypeMap.getFileExtensionFromUrl(file.absolutePath).lowercase()
            var mime = MimeTypeMap.getSingleton().getMimeTypeFromExtension(ext)
            if (mime == null) {
                mime = when (ext) {
                    "pdf" -> "application/pdf"
                    "doc", "docx" -> "application/msword"
                    "txt" -> "text/plain"
                    "jpg", "jpeg", "png", "webp" -> "image/*"
                    "mp3", "wav", "m4a" -> "audio/*"
                    "mp4", "mkv" -> "video/*"
                    else -> "*/*"
                }
            }

            val uri: Uri = try {
                FileProvider.getUriForFile(context, "${context.packageName}.fileprovider", file)
            } catch (e: Exception) {
                Uri.fromFile(file)
            }

            val intent = Intent(Intent.ACTION_VIEW).apply {
                setDataAndType(uri, mime)
                addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            }

            context.startActivity(intent)
            return true
        } catch (e: Exception) {
            e.printStackTrace()
            return false
        }
    }

    /**
     * Search contacts matching query
     */
    fun searchContacts(context: Context, query: String): List<Map<String, String>> {
        val results = mutableListOf<Map<String, String>>()
        val clean = query.trim().lowercase()

        try {
            val uri = ContactsContract.CommonDataKinds.Phone.CONTENT_URI
            val projection = arrayOf(
                ContactsContract.CommonDataKinds.Phone.DISPLAY_NAME,
                ContactsContract.CommonDataKinds.Phone.NUMBER
            )
            val cursor = context.contentResolver.query(
                uri,
                projection,
                null,
                null,
                "${ContactsContract.CommonDataKinds.Phone.DISPLAY_NAME} ASC"
            )

            cursor?.use {
                val nameCol = it.getColumnIndex(ContactsContract.CommonDataKinds.Phone.DISPLAY_NAME)
                val numCol = it.getColumnIndex(ContactsContract.CommonDataKinds.Phone.NUMBER)

                while (it.moveToNext()) {
                    val name = it.getString(nameCol) ?: ""
                    val number = it.getString(numCol) ?: ""
                    if (name.lowercase().contains(clean) || number.contains(clean)) {
                        results.add(mapOf("name" to name, "number" to number))
                        if (results.size >= 10) break
                    }
                }
            }
        } catch (e: Exception) {
            e.printStackTrace()
        }

        return results
    }

    /**
     * Get device storage diagnostic info (free, total, used)
     */
    fun getStorageDiagnostics(): Map<String, Any> {
        return try {
            val stat = StatFs(Environment.getDataDirectory().path)
            val blockSize = stat.blockSizeLong
            val totalBlocks = stat.blockCountLong
            val availableBlocks = stat.availableBlocksLong

            val totalBytes = totalBlocks * blockSize
            val freeBytes = availableBlocks * blockSize
            val usedBytes = totalBytes - freeBytes

            val totalGB = totalBytes.toDouble() / (1024 * 1024 * 1024)
            val freeGB = freeBytes.toDouble() / (1024 * 1024 * 1024)
            val usedGB = usedBytes.toDouble() / (1024 * 1024 * 1024)

            mapOf(
                "totalGB" to String.format("%.1f", totalGB),
                "freeGB" to String.format("%.1f", freeGB),
                "usedGB" to String.format("%.1f", usedGB),
                "freeBytes" to freeBytes,
                "totalBytes" to totalBytes
            )
        } catch (e: Exception) {
            mapOf("error" to (e.message ?: "Failed to read storage"))
        }
    }
}
