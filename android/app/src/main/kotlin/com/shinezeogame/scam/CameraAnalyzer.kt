package com.shinezeogame.scam

import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.ImageFormat
import android.graphics.Matrix
import android.graphics.Rect
import android.graphics.YuvImage
import android.os.SystemClock
import com.cloudwebrtc.webrtc.FlutterWebRTCPlugin
import com.cloudwebrtc.webrtc.audio.LocalAudioTrack
import com.cloudwebrtc.webrtc.video.LocalVideoTrack
import org.webrtc.AudioTrackSink
import org.webrtc.VideoFrame
import java.io.ByteArrayOutputStream
import java.nio.ByteBuffer
import java.nio.ByteOrder
import java.util.concurrent.Executors
import kotlin.math.abs
import kotlin.math.log10
import kotlin.math.max
import kotlin.math.sqrt

/**
 * Mesures faites directement sur les images et le son que la caméra transmet, sans
 * second accès au capteur ni au micro (Android ne le permettrait pas) :
 *
 * - niveau sonore (décibels pleine échelle, le plus fort depuis la dernière lecture) ;
 * - mouvement : part de l'image qui a changé, sur une grille réduite de 64 × 48 points,
 *   en retirant le changement global de luminosité (une lampe qu'on allume n'est pas un
 *   mouvement) ;
 * - dernière image en JPEG, préparée seulement quand le flux MJPEG la demande.
 *
 * Les pistes viennent de flutter_webrtc (`FlutterWebRTCPlugin.sharedSingleton`).
 */
class CameraAnalyzer {
    private var videoTrack: LocalVideoTrack? = null
    private var audioTrack: LocalAudioTrack? = null
    private val encoder = Executors.newSingleThreadExecutor()

    @Volatile private var loudestDb = SILENCE_DB
    @Volatile private var lastAudioAt = 0L
    @Volatile private var motion = 0.0
    @Volatile private var lastVideoAt = 0L
    private var previousGrid: IntArray? = null

    @Volatile private var jpegWantedAt = 0L
    @Volatile private var jpegMadeAt = 0L
    @Volatile private var encoding = false
    @Volatile private var latestJpeg: ByteArray? = null

    private val processor = object : LocalVideoTrack.ExternalVideoFrameProcessing {
        override fun onFrame(frame: VideoFrame): VideoFrame {
            try {
                analyse(frame)
            } catch (e: Exception) {
                // Une image ratée ne doit jamais bloquer la transmission.
            }
            return frame
        }
    }

    private val sink = object : AudioTrackSink {
        override fun onData(
            audioData: ByteBuffer,
            bitsPerSample: Int,
            sampleRate: Int,
            numberOfChannels: Int,
            numberOfFrames: Int,
            absoluteCaptureTimestampMs: Long,
        ) {
            if (bitsPerSample != 16) return
            val samples = audioData.duplicate().order(ByteOrder.LITTLE_ENDIAN).asShortBuffer()
            val count = samples.remaining()
            if (count == 0) return
            var sum = 0.0
            for (i in 0 until count) {
                val s = samples.get(i).toDouble()
                sum += s * s
            }
            val rms = sqrt(sum / count)
            val db = if (rms < 1) SILENCE_DB else max(SILENCE_DB, 20 * log10(rms / 32768.0))
            loudestDb = max(loudestDb, db)
            lastAudioAt = SystemClock.elapsedRealtime()
        }
    }

    @Synchronized
    fun start(videoTrackId: String?, audioTrackId: String?) {
        stop()
        val plugin = FlutterWebRTCPlugin.sharedSingleton ?: return
        videoTrack = videoTrackId?.let { plugin.getLocalTrack(it) as? LocalVideoTrack }?.also {
            it.addProcessor(processor)
        }
        audioTrack = audioTrackId?.let { plugin.getLocalTrack(it) as? LocalAudioTrack }?.also {
            it.addSink(sink)
        }
    }

    @Synchronized
    fun stop() {
        videoTrack?.removeProcessor(processor)
        audioTrack?.removeSink(sink)
        videoTrack = null
        audioTrack = null
        previousGrid = null
        motion = 0.0
        loudestDb = SILENCE_DB
        latestJpeg = null
    }

    /** Mesures depuis la lecture précédente (les maximums sont remis à zéro). */
    fun read(): Map<String, Any> {
        val now = SystemClock.elapsedRealtime()
        val sound = if (now - lastAudioAt > 1500) SILENCE_DB else loudestDb
        val moved = if (now - lastVideoAt > 3000) 0.0 else motion
        loudestDb = SILENCE_DB
        motion = 0.0
        return mapOf("sonDb" to sound, "mouvement" to moved)
    }

    /** Dernière image JPEG ; la demande déclenche la préparation des suivantes. */
    fun jpeg(): ByteArray? {
        jpegWantedAt = SystemClock.elapsedRealtime()
        return latestJpeg
    }

    private fun analyse(frame: VideoFrame) {
        val now = SystemClock.elapsedRealtime()
        val wantMotion = now - lastVideoAt >= MOTION_INTERVAL_MS
        val wantJpeg = now - jpegWantedAt < 5000 && now - jpegMadeAt >= JPEG_INTERVAL_MS && !encoding
        if (!wantMotion && !wantJpeg) return
        val i420 = frame.buffer.toI420() ?: return
        try {
            if (wantMotion) {
                lastVideoAt = now
                measureMotion(i420)
            }
            if (wantJpeg) {
                jpegMadeAt = now
                val nv21 = toNv21(i420)
                val width = i420.width
                val height = i420.height
                val rotation = frame.rotation
                encoding = true
                encoder.execute {
                    try {
                        latestJpeg = encode(nv21, width, height, rotation)
                    } catch (e: Exception) {
                        // On garde l'image précédente.
                    } finally {
                        encoding = false
                    }
                }
            }
        } finally {
            i420.release()
        }
    }

    private fun measureMotion(i420: VideoFrame.I420Buffer) {
        val width = i420.width
        val height = i420.height
        val y = i420.dataY
        val stride = i420.strideY
        val grid = IntArray(GRID_W * GRID_H)
        for (gy in 0 until GRID_H) {
            val row = (gy * height / GRID_H + height / (2 * GRID_H)).coerceAtMost(height - 1)
            for (gx in 0 until GRID_W) {
                val col = (gx * width / GRID_W + width / (2 * GRID_W)).coerceAtMost(width - 1)
                val v = y.get(row * stride + col).toInt() and 0xFF
                grid[gy * GRID_W + gx] = v
            }
        }
        val previous = previousGrid
        previousGrid = grid
        if (previous == null) return
        // Changement moyen de luminosité, retiré de chaque point.
        var shift = 0L
        for (i in grid.indices) shift += grid[i] - previous[i]
        val mean = shift.toDouble() / grid.size
        var changed = 0
        for (i in grid.indices) {
            if (abs(grid[i] - previous[i] - mean) > PIXEL_THRESHOLD) changed++
        }
        motion = max(motion, changed.toDouble() / grid.size)
    }

    private fun toNv21(i420: VideoFrame.I420Buffer): ByteArray {
        val width = i420.width
        val height = i420.height
        val out = ByteArray(width * height * 3 / 2)
        val y = i420.dataY
        val u = i420.dataU
        val v = i420.dataV
        var o = 0
        for (row in 0 until height) {
            val base = row * i420.strideY
            for (col in 0 until width) out[o++] = y.get(base + col)
        }
        for (row in 0 until height / 2) {
            val baseU = row * i420.strideU
            val baseV = row * i420.strideV
            for (col in 0 until width / 2) {
                out[o++] = v.get(baseV + col)
                out[o++] = u.get(baseU + col)
            }
        }
        return out
    }

    private fun encode(nv21: ByteArray, width: Int, height: Int, rotation: Int): ByteArray {
        val buffer = ByteArrayOutputStream()
        YuvImage(nv21, ImageFormat.NV21, width, height, null).compressToJpeg(Rect(0, 0, width, height), 75, buffer)
        if (rotation % 360 == 0) return buffer.toByteArray()
        // Téléphone posé de travers ou debout : l'image est remise à l'endroit.
        val bytes = buffer.toByteArray()
        val bitmap = BitmapFactory.decodeByteArray(bytes, 0, bytes.size) ?: return bytes
        val rotated = Bitmap.createBitmap(bitmap, 0, 0, width, height, Matrix().apply { postRotate(rotation.toFloat()) }, true)
        val out = ByteArrayOutputStream()
        rotated.compress(Bitmap.CompressFormat.JPEG, 75, out)
        bitmap.recycle()
        rotated.recycle()
        return out.toByteArray()
    }

    companion object {
        private const val SILENCE_DB = -90.0
        private const val GRID_W = 64
        private const val GRID_H = 48
        private const val PIXEL_THRESHOLD = 24
        private const val MOTION_INTERVAL_MS = 400L
        private const val JPEG_INTERVAL_MS = 450L
    }
}
