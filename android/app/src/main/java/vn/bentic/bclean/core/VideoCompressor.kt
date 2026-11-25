package vn.bentic.bclean.core

import android.content.ContentValues
import android.content.Context
import android.net.Uri
import android.os.Environment
import android.os.Handler
import android.os.Looper
import android.provider.MediaStore
import androidx.annotation.OptIn
import androidx.media3.common.MediaItem
import androidx.media3.common.MimeTypes
import androidx.media3.common.util.UnstableApi
import androidx.media3.effect.Presentation
import androidx.media3.transformer.Composition
import androidx.media3.transformer.DefaultEncoderFactory
import androidx.media3.transformer.EditedMediaItem
import androidx.media3.transformer.Effects
import androidx.media3.transformer.ExportException
import androidx.media3.transformer.ExportResult
import androidx.media3.transformer.ProgressHolder
import androidx.media3.transformer.Transformer
import androidx.media3.transformer.VideoEncoderSettings
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.suspendCancellableCoroutine
import kotlinx.coroutines.withContext
import java.io.File
import kotlin.coroutines.resume
import kotlin.coroutines.resumeWithException

/** Nén video bằng Media3 Transformer (H.264), lưu vào thư mục Movies/Bclean. */
class VideoCompressor(private val context: Context) {

    @OptIn(UnstableApi::class)
    suspend fun compress(entry: MediaEntry, level: CompressionLevel, onProgress: (Float) -> Unit): File =
        withContext(Dispatchers.Main) {
            val out = File(context.cacheDir, "bclean_${System.currentTimeMillis()}.mp4")
            suspendCancellableCoroutine<File> { cont ->
                val encoder = DefaultEncoderFactory.Builder(context)
                    .setRequestedVideoEncoderSettings(
                        VideoEncoderSettings.Builder().setBitrate(level.bitrate).build()
                    )
                    .build()
                val transformer = Transformer.Builder(context)
                    .setVideoMimeType(MimeTypes.VIDEO_H264)
                    .setEncoderFactory(encoder)
                    .addListener(object : Transformer.Listener {
                        override fun onCompleted(composition: Composition, exportResult: ExportResult) {
                            if (cont.isActive) cont.resume(out)
                        }

                        override fun onError(
                            composition: Composition,
                            exportResult: ExportResult,
                            exportException: ExportException,
                        ) {
                            out.delete()
                            if (cont.isActive) cont.resumeWithException(exportException)
                        }
                    })
                    .build()

                // Kích thước hiển thị (đã tính xoay) để giữ đúng tỉ lệ
                val rotated = entry.orientation == 90 || entry.orientation == 270
                val shownW = if (rotated) entry.height else entry.width
                val shownH = if (rotated) entry.width else entry.height
                val shortSide = minOf(shownW, shownH)
                val effects = if (shortSide > level.shortSide && shownW > 0 && shownH > 0) {
                    val targetH = if (shownH <= shownW) level.shortSide
                    else (level.shortSide.toDouble() * shownH / shownW).toInt() / 2 * 2
                    Effects(listOf(), listOf(Presentation.createForHeight(targetH)))
                } else {
                    Effects.EMPTY
                }

                val edited = EditedMediaItem.Builder(MediaItem.fromUri(entry.uri)).setEffects(effects).build()
                transformer.start(edited, out.absolutePath)

                val handler = Handler(Looper.getMainLooper())
                val holder = ProgressHolder()
                val poll = object : Runnable {
                    override fun run() {
                        if (!cont.isActive) return
                        if (transformer.getProgress(holder) == Transformer.PROGRESS_STATE_AVAILABLE) {
                            onProgress(holder.progress / 100f)
                        }
                        handler.postDelayed(this, 300)
                    }
                }
                handler.post(poll)
                cont.invokeOnCancellation { handler.post { transformer.cancel(); out.delete() } }
            }
        }

    /** Lưu file nén vào thư viện (Movies/Bclean), giữ ngày chụp gốc. */
    fun saveToGallery(file: File, original: MediaEntry): Uri {
        val resolver = context.contentResolver
        val values = ContentValues().apply {
            put(MediaStore.Video.Media.DISPLAY_NAME, "Bclean_${System.currentTimeMillis()}.mp4")
            put(MediaStore.Video.Media.MIME_TYPE, "video/mp4")
            put(MediaStore.Video.Media.RELATIVE_PATH, Environment.DIRECTORY_MOVIES + "/Bclean")
            put(MediaStore.Video.Media.DATE_TAKEN, original.dateTaken)
            put(MediaStore.Video.Media.IS_PENDING, 1)
        }
        val uri = resolver.insert(MediaStore.Video.Media.getContentUri(MediaStore.VOLUME_EXTERNAL_PRIMARY), values)
            ?: error("Cannot create video in gallery")
        resolver.openOutputStream(uri)?.use { output -> file.inputStream().use { it.copyTo(output) } }
        values.clear()
        values.put(MediaStore.Video.Media.IS_PENDING, 0)
        resolver.update(uri, values, null, null)
        file.delete()
        return uri
    }
}
