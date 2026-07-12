package com.formuladoc.app

import android.graphics.*
import java.io.ByteArrayOutputStream
import java.nio.ByteBuffer
import java.nio.ByteOrder
import kotlin.math.abs
import kotlin.math.roundToInt

/**
 * Renders a Windows Metafile (WMF) — as produced by MathType / Equation
 * Editor 3.x — to a PNG bitmap using Android Canvas.
 *
 * Supports the subset of GDI records that MathType emits:
 *   SETBKMODE · SETTEXTCOLOR · SETWINDOWORG · SETWINDOWEXT
 *   MOVETO · LINETO · CREATEPENINDIRECT · CREATEFONTINDIRECT
 *   SELECTOBJECT · DELETEOBJECT · TEXTOUT · EXTTEXTOUT
 *
 * Coordinate system:
 *   WMF uses a "placeable" header that declares the bounding box in logical
 *   units and a "units-per-inch" value. We map the bounding box linearly onto
 *   [targetDpi * width_inches] × [targetDpi * height_inches] pixels.
 *
 * Text positioning:
 *   MathType emits EXTTEXTOUT with (x=0, y=0), meaning "use the current
 *   position set by the preceding MOVETO". Subsequent character x-positions
 *   are given by the optional dx[] array (in logical units).
 *   Android's drawText() takes the baseline y; we convert from WMF's top-y
 *   via fontMetrics.
 */
class WmfRenderer {

    // ── GDI object table ──────────────────────────────────────────────────────

    private sealed class GdiObj
    private class FontObj(
        val tf: Typeface,
        val heightLogical: Float,
        val isSymbol: Boolean
    ) : GdiObj()
    private class PenObj(
        val color: Int,
        val widthLogical: Float,
        val style: Int   // 0=solid, 1=dash, 2=dot, 5=null/invisible
    ) : GdiObj()

    // ── Symbol font character mapping (Windows Symbol → Unicode) ─────────────

    companion object {
        private const val PLACEABLE_MAGIC = 0x9AC6CDD7.toInt()

        /** Map a byte value in the Windows "Symbol" font encoding to a Unicode string. */
        fun symbolToUnicode(b: Int): String = when (b) {
            // Digits and punctuation identical to ASCII
            in 0x21..0x2F -> b.toChar().toString()
            in 0x30..0x39 -> b.toChar().toString()
            in 0x3A..0x3F -> b.toChar().toString()
            // Uppercase → Greek capitals
            0x41 -> "Α"; 0x42 -> "Β"; 0x43 -> "Χ"; 0x44 -> "Δ"
            0x45 -> "Ε"; 0x46 -> "Φ"; 0x47 -> "Γ"; 0x48 -> "Η"
            0x49 -> "Ι"; 0x4A -> "ϑ"; 0x4B -> "Κ"; 0x4C -> "Λ"
            0x4D -> "Μ"; 0x4E -> "Ν"; 0x4F -> "Ο"; 0x50 -> "Π"
            0x51 -> "Θ"; 0x52 -> "Ρ"; 0x53 -> "Σ"; 0x54 -> "Τ"
            0x55 -> "Υ"; 0x56 -> "ς"; 0x57 -> "Ω"; 0x58 -> "Ξ"
            0x59 -> "Ψ"; 0x5A -> "Ζ"
            0x5B -> "["; 0x5C -> "∴"; 0x5D -> "]"; 0x5E -> "⊥"
            0x5F -> "_"; 0x60 -> "‾"
            // Lowercase → Greek lowercase
            0x61 -> "α"; 0x62 -> "β"; 0x63 -> "χ"; 0x64 -> "δ"
            0x65 -> "ε"; 0x66 -> "φ"; 0x67 -> "γ"; 0x68 -> "η"
            0x69 -> "ι"; 0x6A -> "ϕ"; 0x6B -> "κ"; 0x6C -> "λ"
            0x6D -> "μ"; 0x6E -> "ν"; 0x6F -> "ο"; 0x70 -> "π"
            0x71 -> "θ"; 0x72 -> "ρ"; 0x73 -> "σ"; 0x74 -> "τ"
            0x75 -> "υ"; 0x76 -> "ϖ"; 0x77 -> "ω"; 0x78 -> "ξ"
            0x79 -> "ψ"; 0x7A -> "ζ"
            0x7B -> "{"; 0x7C -> "|"; 0x7D -> "}"; 0x7E -> "~"
            // Extended Symbol chars
            0xA0 -> "\u00A0"; 0xA1 -> "ϒ"; 0xA2 -> "′"
            0xA3 -> "≤";      0xA4 -> "⁄"; 0xA5 -> "∞"
            0xA6 -> "ƒ";      0xA7 -> "♣"; 0xA8 -> "♦"
            0xA9 -> "♥";      0xAA -> "♠"; 0xAB -> "↔"
            0xAC -> "←";      0xAD -> "↑"; 0xAE -> "→"; 0xAF -> "↓"
            0xB0 -> "°";      0xB1 -> "±"; 0xB2 -> "″"
            0xB3 -> "≥";      0xB4 -> "×"; 0xB5 -> "∝"
            0xB6 -> "∂";      0xB7 -> "•"; 0xB8 -> "÷"
            0xB9 -> "≠";      0xBA -> "≡"; 0xBB -> "≈"
            0xBC -> "…";      0xBD -> "⏐"; 0xBE -> "⎯"; 0xBF -> "↵"
            0xC0 -> "ℵ";      0xC1 -> "ℑ"; 0xC2 -> "ℜ"
            0xC3 -> "℘";      0xC4 -> "⊗"; 0xC5 -> "⊕"
            0xC6 -> "∅";      0xC7 -> "∩"; 0xC8 -> "∪"
            0xC9 -> "⊃";      0xCA -> "⊇"; 0xCB -> "⊄"
            0xCC -> "⊂";      0xCD -> "⊆"; 0xCE -> "∈"; 0xCF -> "∉"
            0xD0 -> "∠";      0xD1 -> "∇"; 0xD2 -> "®";  0xD3 -> "©"
            0xD4 -> "™";      0xD5 -> "∏"; 0xD6 -> "√"; 0xD7 -> "·"
            0xD8 -> "¬";      0xD9 -> "∧"; 0xDA -> "∨"
            0xDB -> "⇔";      0xDC -> "⇐"; 0xDD -> "⇑"
            0xDE -> "⇒";      0xDF -> "⇓"
            // 0xE0-0xEF: misc symbols + LARGE BRACKET COMPONENTS
            // These are critical for MathType structural formulas: a left
            // curly brace spanning multiple lines uses 0xEC (top), 0xED
            // (middle), 0xEE (bottom), 0xEF (extension piece).
            0xE0 -> "◊"; 0xE1 -> "〈"; 0xE2 -> "®"
            0xE3 -> "©"; 0xE4 -> "™"
            0xE5 -> "∑"
            0xE6 -> "⎛"; 0xE7 -> "⎜"; 0xE8 -> "⎝"  // large ( parts
            0xE9 -> "⎡"; 0xEA -> "⎢"; 0xEB -> "⎣"  // large [ parts
            0xEC -> "⎧"; 0xED -> "⎨"; 0xEE -> "⎩"; 0xEF -> "⎪" // large { parts
            // 0xF0-0xF1
            0xF0 -> "⟩"; 0xF1 -> "〉"
            0xF2 -> "∫"
            else -> if (b in 0x20..0x7E) b.toChar().toString() else "?"
        }
    }

    // ── Public API ────────────────────────────────────────────────────────────

    /**
     * Render [wmfBytes] to PNG and return the PNG bytes.
     * Returns null on any error; the caller should fall back to a placeholder.
     *
     * @param wmfBytes  Raw WMF file content.
     * @param targetDpi Rendering resolution. 192 = 2× at 96 DPI baseline.
     */
    fun render(wmfBytes: ByteArray, targetDpi: Float = 192f): ByteArray? {
        if (wmfBytes.size < 44) return null
        return try {
            renderInternal(wmfBytes, targetDpi)
        } catch (e: Exception) {
            null
        }
    }

    // ── Internal renderer ────────────────────────────────────────────────────

    private fun renderInternal(data: ByteArray, targetDpi: Float): ByteArray? {
        val buf = ByteBuffer.wrap(data).order(ByteOrder.LITTLE_ENDIAN)

        // ── 1. Parse placeable header (22 bytes) ────────────────────────────
        val magic = buf.getInt(0)
        if (magic != PLACEABLE_MAGIC) return null  // only placeable WMF supported

        buf.position(4)
        buf.short               // handle (ignored)
        val left   = buf.short.toInt()
        val top    = buf.short.toInt()
        val right  = buf.short.toInt()
        val bottom = buf.short.toInt()
        val inch   = (buf.short.toInt() and 0xFFFF).coerceAtLeast(1)
        // skip reserved(4) + checksum(2)

        // ── 2. Skip standard WMF header ─────────────────────────────────────
        buf.position(22)       // after placeable header
        val hdrSize = buf.getShort(24).toInt() and 0xFFFF  // in words
        buf.position(22 + hdrSize * 2)                      // jump to first record

        // ── 3. Calculate bitmap size ─────────────────────────────────────────
        val winW = (right - left).toFloat().coerceAtLeast(1f)
        val winH = (bottom - top).toFloat().coerceAtLeast(1f)
        val pxW  = (winW / inch * targetDpi).roundToInt().coerceIn(1, 4096)

        // Pre-scan records to find the largest font height used.
        // WMF equations place text near the bottom of the window extent, then
        // the font's ascent + descent push the glyphs BELOW the logical boundary.
        // Without extra height the bottom of every equation is clipped by 22–32px.
        val recStart = 22 + hdrSize * 2
        var maxFontLogical = 0f
        val scanBuf = ByteBuffer.wrap(data).order(ByteOrder.LITTLE_ENDIAN)
        scanBuf.position(recStart)
        while (scanBuf.remaining() >= 6) {
            val rw = scanBuf.int; val fn = scanBuf.short.toInt() and 0xFFFF
            val rb = rw * 2; val ps = scanBuf.position()
            if (fn == 0 || rb < 6) break
            if (fn == 0x02FB && scanBuf.remaining() >= 2) {  // CREATEFONTINDIRECT
                val h = kotlin.math.abs(scanBuf.short.toFloat())
                if (h > maxFontLogical) maxFontLogical = h
            }
            scanBuf.position((ps + rb - 6).coerceAtMost(data.size))
        }
        val maxFontPx = (maxFontLogical / inch * targetDpi).roundToInt()

        // Add one full maxFontPx of padding so descenders are never clipped.
        val pxH = (winH / inch * targetDpi + maxFontPx).roundToInt().coerceIn(1, 4096)
        val scaleX = pxW / winW
        val scaleY = pxH / (winH + maxFontLogical)  // scale based on padded logical height

        val bitmap = Bitmap.createBitmap(pxW, pxH, Bitmap.Config.ARGB_8888)
        bitmap.eraseColor(Color.WHITE)
        val canvas = Canvas(bitmap)

        // ── 4. Coordinate helpers ─────────────────────────────────────────────
        fun lx(x: Float) = (x - left) * scaleX
        fun ly(y: Float) = (y - top)  * scaleY
        fun fontPx(logicalH: Float) =
            (abs(logicalH) / inch * targetDpi).coerceAtLeast(6f)

        // ── 5. GDI state ──────────────────────────────────────────────────────
        val objTable = HashMap<Int, GdiObj>()
        // WMF spec §3.1.5: new objects take the LOWEST available slot.
        // Freed slots (DELETEOBJECT) are reused. A sequential counter breaks
        // this — after any delete/create pair every SELECTOBJECT picks the
        // wrong object, causing Symbol ↔ Times New Roman to be swapped.
        fun nextSlot(): Int { var i = 0; while (objTable.containsKey(i)) i++; return i }
        var curX = 0f;  var curY = 0f
        var textColor = Color.BLACK
        var penColor  = Color.BLACK
        var penWidth  = 1f
        var penStyle  = 0
        var fontH     = 16f
        var fontTf    = Typeface.SERIF
        var fontSym   = false

        val linePaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            style = Paint.Style.STROKE
        }
        val textPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            textAlign = Paint.Align.LEFT
        }

        // ── 6. Record loop ────────────────────────────────────────────────────
        while (buf.remaining() >= 6) {
            val recWords = buf.int               // DWORD: record size in words
            val func     = buf.short.toInt() and 0xFFFF
            val recBytes = recWords * 2
            val paramEnd = buf.position() - 6 + recBytes

            if (func == 0x0000) break            // META_EOF

            val paramStart = buf.position()

            when (func) {

                // ── SETTEXTCOLOR ──────────────────────────────────────────
                0x0209 -> {
                    if (buf.remaining() >= 4) {
                        val b = buf.get().toInt() and 0xFF
                        val g = buf.get().toInt() and 0xFF
                        val r = buf.get().toInt() and 0xFF
                        textColor = Color.rgb(r, g, b)
                    }
                }

                // ── MOVETO ────────────────────────────────────────────────
                0x0214 -> {
                    if (buf.remaining() >= 4) {
                        curY = buf.short.toFloat()
                        curX = buf.short.toFloat()
                    }
                }

                // ── LINETO ────────────────────────────────────────────────
                0x0213 -> {
                    if (buf.remaining() >= 4) {
                        val y2 = buf.short.toFloat()
                        val x2 = buf.short.toFloat()
                        if (penStyle != 5) {  // not NULL pen
                            linePaint.color = penColor
                            linePaint.strokeWidth =
                                (penWidth / inch * targetDpi).coerceAtLeast(1f)
                            canvas.drawLine(lx(curX), ly(curY), lx(x2), ly(y2), linePaint)
                        }
                        curX = x2; curY = y2
                    }
                }

                // ── CREATEPENINDIRECT ──────────────────────────────────────
                0x02FA -> {
                    if (buf.remaining() >= 8) {
                        val style  = buf.short.toInt() and 0xFFFF
                        val wx     = buf.short.toFloat()
                        buf.short  // y-width (ignored)
                        val cb     = buf.get().toInt() and 0xFF
                        val cg     = buf.get().toInt() and 0xFF
                        val cr     = buf.get().toInt() and 0xFF
                        objTable[nextSlot()] = PenObj(Color.rgb(cr, cg, cb), wx, style)
                    }
                }

                // ── CREATEFONTINDIRECT ────────────────────────────────────
                0x02FB -> {
                    if (buf.remaining() >= 34) {
                        val lfHeight  = buf.short.toFloat()
                        buf.short   // width
                        buf.short   // escapement
                        buf.short   // orientation
                        val weight  = buf.short.toInt() and 0xFFFF
                        val italic  = buf.get().toInt() != 0
                        buf.get()   // underline
                        buf.get()   // strikeout
                        val charset = buf.get().toInt() and 0xFF
                        buf.get(); buf.get(); buf.get(); buf.get()  // precision/quality
                        val nameBytes = ByteArray(32); buf.get(nameBytes)
                        val fname = nameBytes.takeWhile { it != 0.toByte() }
                            .map { it.toInt().toChar() }.joinToString("")
                            .lowercase()

                        val style = when {
                            weight >= 700 && italic -> Typeface.BOLD_ITALIC
                            weight >= 700           -> Typeface.BOLD
                            italic                  -> Typeface.ITALIC
                            else                    -> Typeface.NORMAL
                        }
                        val isSym = fname.contains("symbol") || charset == 2
                        val tf = when {
                            fname.contains("times") || fname.contains("roman") ->
                                Typeface.create(Typeface.SERIF, style)
                            fname.contains("arial") || fname.contains("helvetica") ->
                                Typeface.create(Typeface.SANS_SERIF, style)
                            isSym ->
                                Typeface.create(Typeface.SERIF, style)
                            else ->
                                Typeface.create(Typeface.DEFAULT, style)
                        }
                        objTable[nextSlot()] = FontObj(tf, lfHeight, isSym)
                    }
                }

                // ── SELECTOBJECT ──────────────────────────────────────────
                0x012D -> {
                    if (buf.remaining() >= 2) {
                        val idx = buf.short.toInt() and 0xFFFF
                        when (val o = objTable[idx]) {
                            is FontObj -> { fontH = o.heightLogical; fontTf = o.tf; fontSym = o.isSymbol }
                            is PenObj  -> { penColor = o.color; penWidth = o.widthLogical; penStyle = o.style }
                            else -> {}
                        }
                    }
                }

                // ── DELETEOBJECT ──────────────────────────────────────────
                0x01F0 -> {
                    if (buf.remaining() >= 2) {
                        objTable.remove(buf.short.toInt() and 0xFFFF)
                    }
                }

                // ── TEXTOUT ───────────────────────────────────────────────
                0x0521 -> {
                    if (buf.remaining() >= 6) {
                        val n     = buf.short.toInt() and 0xFFFF
                        val bytes = ByteArray(n); buf.get(bytes)
                        if (n % 2 != 0) buf.get()      // padding
                        val ty = buf.short.toFloat()
                        val tx = buf.short.toFloat()
                        val posX = if (tx == 0f && ty == 0f) curX else tx
                        val posY = if (tx == 0f && ty == 0f) curY else ty
                        drawRunText(canvas, bytes, null, posX, posY,
                            textColor, fontPx(fontH), fontTf, fontSym,
                            ::lx, ::ly, scaleX)
                    }
                }

                // ── EXTTEXTOUT ────────────────────────────────────────────
                0x0A32 -> {
                    if (buf.remaining() >= 8) {
                        val ty    = buf.short.toFloat()
                        val tx    = buf.short.toFloat()
                        val n     = buf.short.toInt() and 0xFFFF
                        val opts  = buf.short.toInt() and 0xFFFF
                        if (opts and 0x06 != 0) {      // skip optional rect
                            buf.short; buf.short; buf.short; buf.short
                        }
                        val bytes = ByteArray(n); buf.get(bytes)
                        if (n % 2 != 0) buf.get()      // padding
                        val posX = if (tx == 0f && ty == 0f) curX else tx
                        val posY = if (tx == 0f && ty == 0f) curY else ty

                        // Optional dx array: present when bytes remain in record
                        val consumed = buf.position() - paramStart
                        val remaining = (paramEnd - buf.position()).coerceAtLeast(0)
                        val dx: ShortArray? = if (remaining >= n * 2) {
                            ShortArray(n) { buf.short }
                        } else null

                        drawRunText(canvas, bytes, dx, posX, posY,
                            textColor, fontPx(fontH), fontTf, fontSym,
                            ::lx, ::ly, scaleX)
                    }
                }

                // ── Ignore everything else ────────────────────────────────
                else -> { /* META_SETBKMODE, META_ESCAPE, etc. */ }
            }

            // Advance to next record (handle truncated/bad records gracefully)
            if (buf.position() < paramEnd) buf.position(paramEnd.coerceAtMost(buf.limit()))
        }

        // ── 7. Encode to PNG ──────────────────────────────────────────────────
        val out = ByteArrayOutputStream()
        bitmap.compress(Bitmap.CompressFormat.PNG, 95, out)
        bitmap.recycle()
        return out.toByteArray()
    }

    // ── Text drawing helper ───────────────────────────────────────────────────

    /**
     * Draw [bytes] as a text run at logical position ([x], [y]).
     *
     * When a [dx] array is provided, each character is drawn individually at
     * the correct x position (WMF top-y). Without dx, the whole string is
     * drawn at once.
     *
     * WMF default text alignment is TA_TOP | TA_LEFT (y is TOP of text cell).
     * Android's drawText() uses baseline y, so we shift down by -ascent.
     */
    private fun drawRunText(
        canvas: Canvas,
        bytes: ByteArray,
        dx: ShortArray?,
        x: Float, y: Float,
        color: Int,
        fontSizePx: Float,
        tf: Typeface,
        isSymbol: Boolean,
        lx: (Float) -> Float,
        ly: (Float) -> Float,
        scaleX: Float,
    ) {
        if (bytes.isEmpty()) return

        val paint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            this.color = color
            textSize   = fontSizePx
            typeface   = tf
            textAlign  = Paint.Align.LEFT
        }
        // Convert WMF top-y → Android baseline-y
        val ascent = paint.fontMetrics.ascent   // negative value
        val pyBase = ly(y) - ascent

        if (dx != null && dx.isNotEmpty()) {
            // Character-by-character with explicit advances
            var px = lx(x)
            for (i in bytes.indices) {
                val b  = bytes[i].toInt() and 0xFF
                val ch = if (isSymbol) symbolToUnicode(b) else b.toChar().toString()
                canvas.drawText(ch, px, pyBase, paint)
                if (i < dx.size) {
                    // dx[i] is in WMF logical units → pixels via scaleX
                    px += dx[i].toFloat() * scaleX
                }
            }
        } else {
            // Whole string at once
            val str = if (isSymbol) {
                bytes.joinToString("") { b -> symbolToUnicode(b.toInt() and 0xFF) }
            } else {
                String(bytes, Charsets.ISO_8859_1)
            }
            canvas.drawText(str, lx(x), pyBase, paint)
        }
    }
}
