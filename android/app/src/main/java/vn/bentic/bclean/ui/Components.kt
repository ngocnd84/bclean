package vn.bentic.bclean.ui

import android.content.Context
import android.graphics.Bitmap
import android.net.Uri
import android.util.LruCache
import android.util.Size
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.CheckCircle
import androidx.compose.material.icons.filled.PlayArrow
import androidx.compose.material.icons.outlined.Circle
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.darkColorScheme
import androidx.compose.material3.lightColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.produceState
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.ImageBitmap
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import vn.bentic.bclean.R
import vn.bentic.bclean.core.CleanCategory
import vn.bentic.bclean.core.Fmt
import vn.bentic.bclean.core.MediaEntry

object BColors {
    val teal = Color(0xFF0DA69E)
    val blue = Color(0xFF2973F5)
    val danger = Color(0xFFEB4345)
    val gradient = Brush.linearGradient(listOf(teal, blue))
}

@Composable
fun BcleanTheme(content: @Composable () -> Unit) {
    val scheme = if (isSystemInDarkTheme()) {
        darkColorScheme(primary = Color(0xFF2EC7B8), secondary = BColors.blue, error = BColors.danger)
    } else {
        lightColorScheme(primary = BColors.teal, secondary = BColors.blue, error = BColors.danger,
            background = Color(0xFFF2F4F7), surface = Color.White)
    }
    MaterialTheme(colorScheme = scheme, content = content)
}

fun CleanCategory.titleRes(): Int = when (this) {
    CleanCategory.DUPLICATES -> R.string.cat_duplicates
    CleanCategory.SIMILAR -> R.string.cat_similar
    CleanCategory.SCREENSHOTS -> R.string.cat_screenshots
    CleanCategory.BLURRY -> R.string.cat_blurry
    CleanCategory.VIDEOS -> R.string.cat_videos
}

fun CleanCategory.subtitleRes(): Int = when (this) {
    CleanCategory.DUPLICATES -> R.string.cat_duplicates_sub
    CleanCategory.SIMILAR -> R.string.cat_similar_sub
    CleanCategory.SCREENSHOTS -> R.string.cat_screenshots_sub
    CleanCategory.BLURRY -> R.string.cat_blurry_sub
    CleanCategory.VIDEOS -> R.string.cat_videos_sub
}

fun CleanCategory.color(): Color = when (this) {
    CleanCategory.DUPLICATES -> Color(0xFFFF9500)
    CleanCategory.SIMILAR -> Color(0xFFAF52DE)
    CleanCategory.SCREENSHOTS -> Color(0xFF007AFF)
    CleanCategory.BLURRY -> Color(0xFF8E8E93)
    CleanCategory.VIDEOS -> Color(0xFFFF2D55)
}

/** Bộ nhớ đệm thumbnail (giới hạn 48 MB). */
object ThumbCache {
    private val cache = object : LruCache<String, Bitmap>(48 * 1024 * 1024) {
        override fun sizeOf(key: String, value: Bitmap): Int = value.byteCount
    }

    fun load(context: Context, uri: Uri, side: Int): ImageBitmap? {
        val key = "$uri@$side"
        cache.get(key)?.let { return it.asImageBitmap() }
        return runCatching { context.contentResolver.loadThumbnail(uri, Size(side, side), null) }
            .getOrNull()
            ?.also { cache.put(key, it) }
            ?.asImageBitmap()
    }
}

@Composable
fun Thumbnail(uri: Uri, modifier: Modifier = Modifier, side: Int = 256, crop: Boolean = true) {
    val context = LocalContext.current
    val image by produceState<ImageBitmap?>(initialValue = null, uri, side) {
        value = withContext(Dispatchers.IO) { ThumbCache.load(context, uri, side) }
    }
    Box(modifier.background(MaterialTheme.colorScheme.surfaceVariant)) {
        image?.let {
            Image(
                bitmap = it,
                contentDescription = null,
                modifier = Modifier.fillMaxSize(),
                contentScale = if (crop) ContentScale.Crop else ContentScale.Fit,
            )
        }
    }
}

@Composable
fun MediaCell(entry: MediaEntry, selected: Boolean, modifier: Modifier = Modifier, badge: String? = null) {
    Box(
        modifier
            .aspectRatio(1f)
            .clip(RoundedCornerShape(10.dp))
            .border(if (selected) 3.dp else 0.dp, if (selected) BColors.danger else Color.Transparent, RoundedCornerShape(10.dp))
    ) {
        Thumbnail(entry.uri, Modifier.fillMaxSize())
        Icon(
            imageVector = if (selected) Icons.Filled.CheckCircle else Icons.Outlined.Circle,
            contentDescription = null,
            tint = if (selected) BColors.danger else Color.White,
            modifier = Modifier
                .align(Alignment.TopEnd)
                .padding(6.dp)
                .size(24.dp)
                .background(if (selected) Color.White else Color.Black.copy(alpha = 0.2f), CircleShape),
        )
        if (badge != null) {
            Text(
                badge,
                color = Color.White,
                fontSize = 11.sp,
                fontWeight = FontWeight.Bold,
                modifier = Modifier
                    .align(Alignment.TopStart)
                    .padding(6.dp)
                    .background(BColors.teal, RoundedCornerShape(50))
                    .padding(horizontal = 6.dp, vertical = 2.dp),
            )
        }
        Row(
            Modifier
                .align(Alignment.BottomCenter)
                .fillMaxWidth()
                .background(Brush.verticalGradient(listOf(Color.Transparent, Color.Black.copy(alpha = 0.55f))))
                .padding(6.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            if (entry.isVideo) {
                Icon(Icons.Filled.PlayArrow, null, tint = Color.White, modifier = Modifier.size(14.dp))
                Text(Fmt.duration(entry.durationMs), color = Color.White, fontSize = 11.sp)
            }
            Spacer(Modifier.weight(1f))
            Text(Fmt.bytes(entry.bytes), color = Color.White, fontSize = 11.sp, fontWeight = FontWeight.SemiBold)
        }
    }
}

@Composable
fun SelectionBar(
    count: Int,
    bytes: Long,
    onDelete: () -> Unit,
) {
    Surface(tonalElevation = 3.dp, shadowElevation = 8.dp) {
        Column(Modifier.fillMaxWidth().navigationBarsPadding().padding(16.dp)) {
            Button(
                onClick = onDelete,
                enabled = count > 0,
                colors = ButtonDefaults.buttonColors(containerColor = BColors.danger),
                modifier = Modifier.fillMaxWidth(),
            ) {
                Text(stringResource(R.string.delete_n, count, Fmt.bytes(bytes)), fontWeight = FontWeight.Bold, modifier = Modifier.padding(vertical = 6.dp))
            }
        }
    }
}

@Composable
fun EmptyState(icon: ImageVector, title: String, message: String, modifier: Modifier = Modifier) {
    Column(
        modifier.fillMaxSize().padding(32.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.Center,
    ) {
        Icon(icon, null, tint = BColors.teal, modifier = Modifier.size(64.dp))
        Spacer(Modifier.size(12.dp))
        Text(title, style = MaterialTheme.typography.titleLarge, fontWeight = FontWeight.Bold, textAlign = TextAlign.Center)
        Spacer(Modifier.size(6.dp))
        Text(message, style = MaterialTheme.typography.bodyMedium, color = MaterialTheme.colorScheme.onSurfaceVariant, textAlign = TextAlign.Center)
    }
}

@Composable
fun PrimaryButton(text: String, onClick: () -> Unit, modifier: Modifier = Modifier, color: Color = BColors.teal, enabled: Boolean = true) {
    Button(
        onClick = onClick,
        enabled = enabled,
        colors = ButtonDefaults.buttonColors(containerColor = color),
        shape = RoundedCornerShape(14.dp),
        modifier = modifier.fillMaxWidth(),
    ) {
        Text(text, fontWeight = FontWeight.Bold, modifier = Modifier.padding(vertical = 8.dp))
    }
}

@Composable
fun SecondaryButton(text: String, onClick: () -> Unit, modifier: Modifier = Modifier) {
    OutlinedButton(onClick = onClick, shape = RoundedCornerShape(14.dp), modifier = modifier.fillMaxWidth()) {
        Text(text, modifier = Modifier.padding(vertical = 6.dp))
    }
}
