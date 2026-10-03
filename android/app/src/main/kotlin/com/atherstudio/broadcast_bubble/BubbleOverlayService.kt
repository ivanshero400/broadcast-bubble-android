package com.atherstudio.broadcast_bubble

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Intent
import android.content.pm.ServiceInfo
import android.graphics.Color
import android.graphics.PixelFormat
import android.graphics.Typeface
import android.graphics.drawable.GradientDrawable
import android.os.Build
import android.os.IBinder
import android.provider.Settings
import android.util.TypedValue
import android.view.Gravity
import android.view.MotionEvent
import android.view.View
import android.view.WindowManager
import android.widget.FrameLayout
import android.widget.LinearLayout
import android.widget.ScrollView
import android.widget.TextView
import org.json.JSONArray
import org.json.JSONObject
import kotlin.math.abs

class BubbleOverlayService : Service() {
    private lateinit var preferences: android.content.SharedPreferences
    private lateinit var windowManager: WindowManager
    private var overlayRoot: FrameLayout? = null
    private var windowParams: WindowManager.LayoutParams? = null
    private var expanded = false
    private var ideas = JSONArray()
    private var selectedId: String? = null
    private var fontSize = DEFAULT_FONT_SIZE

    override fun onCreate() {
        super.onCreate()
        preferences = getSharedPreferences(PREFERENCES_NAME, MODE_PRIVATE)
        windowManager = getSystemService(WINDOW_SERVICE) as WindowManager
        createNotificationChannel()
        startInForeground()
        isRunning = true
        preferences.edit().putBoolean(KEY_BUBBLE_ACTIVE, true).apply()
        reloadFromStorage()
        renderOverlay()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            ACTION_STOP -> {
                preferences.edit().putBoolean(KEY_BUBBLE_ACTIVE, false).apply()
                stopSelf()
                return START_NOT_STICKY
            }

            ACTION_REFRESH -> {
                reloadFromStorage()
                renderOverlay()
            }
        }
        return START_STICKY
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onDestroy() {
        overlayRoot?.let { view ->
            try {
                windowManager.removeView(view)
            } catch (_: IllegalArgumentException) {
                // The overlay may already have been detached by Android.
            }
        }
        overlayRoot = null
        preferences.edit().putBoolean(KEY_BUBBLE_ACTIVE, false).apply()
        isRunning = false
        super.onDestroy()
    }

    private fun startInForeground() {
        val launchIntent = packageManager.getLaunchIntentForPackage(packageName)
        val contentPendingIntent = launchIntent?.let {
            it.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP)
            PendingIntent.getActivity(this, 1, it, pendingIntentFlags())
        }
        val stopIntent = Intent(this, BubbleOverlayService::class.java).setAction(ACTION_STOP)
        val stopPendingIntent = PendingIntent.getService(this, 2, stopIntent, pendingIntentFlags())
        val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            Notification.Builder(this, CHANNEL_ID)
        } else {
            @Suppress("DEPRECATION")
            Notification.Builder(this)
        }
        val notification = builder
            .setSmallIcon(android.R.drawable.ic_dialog_info)
            .setContentTitle("فقاعة البث")
            .setContentText("الفقاعة العائمة جاهزة للقراءة")
            .setOngoing(true)
            .setOnlyAlertOnce(true)
            .setCategory(Notification.CATEGORY_SERVICE)
            .apply {
                if (contentPendingIntent != null) setContentIntent(contentPendingIntent)
                addAction(android.R.drawable.ic_menu_close_clear_cancel, "إيقاف", stopPendingIntent)
            }
            .build()

        if (Build.VERSION.SDK_INT >= 34) {
            startForeground(NOTIFICATION_ID, notification, ServiceInfo.FOREGROUND_SERVICE_TYPE_SPECIAL_USE)
        } else {
            startForeground(NOTIFICATION_ID, notification)
        }
    }

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val channel = NotificationChannel(
            CHANNEL_ID,
            "الفقاعة العائمة",
            NotificationManager.IMPORTANCE_LOW,
        ).apply {
            description = "إبقاء فقاعة قراءة الأفكار متاحة أثناء استخدام تطبيق البث"
            setShowBadge(false)
        }
        (getSystemService(NOTIFICATION_SERVICE) as NotificationManager).createNotificationChannel(channel)
    }

    private fun pendingIntentFlags(): Int =
        PendingIntent.FLAG_UPDATE_CURRENT or if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            PendingIntent.FLAG_IMMUTABLE
        } else {
            0
        }

    private fun reloadFromStorage() {
        ideas = try {
            JSONArray(preferences.getString(KEY_IDEAS, "[]") ?: "[]")
        } catch (_: Exception) {
            JSONArray()
        }
        selectedId = preferences.getString(KEY_SELECTED_ID, null)
        fontSize = preferences.getInt(KEY_FONT_SIZE, DEFAULT_FONT_SIZE).coerceIn(22, 48)
    }

    private fun renderOverlay() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M && !Settings.canDrawOverlays(this)) {
            stopSelf()
            return
        }
        val root = overlayRoot ?: FrameLayout(this).also { overlayRoot = it }
        root.removeAllViews()
        root.setBackgroundColor(Color.TRANSPARENT)
        root.layoutDirection = View.LAYOUT_DIRECTION_RTL
        root.addView(if (expanded) createPanel() else createBubble())

        val display = resources.displayMetrics
        val maxWidth = (display.widthPixels - dp(24)).coerceAtLeast(dp(1))
        val maxHeight = (display.heightPixels - dp(32)).coerceAtLeast(dp(1))
        val width = if (expanded) {
            minOf(dp(620), (display.widthPixels * 0.92f).toInt(), maxWidth)
        } else {
            dp(58)
        }
        val height = if (expanded) {
            minOf(dp(720), (display.heightPixels * 0.74f).toInt(), maxHeight)
        } else {
            dp(58)
        }
        val params = windowParams ?: WindowManager.LayoutParams(
            width,
            height,
            overlayWindowType(),
            WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE or WindowManager.LayoutParams.FLAG_NOT_TOUCH_MODAL,
            PixelFormat.TRANSLUCENT,
        ).apply {
            gravity = Gravity.TOP or Gravity.RIGHT
            x = dp(14)
            y = dp(190)
        }.also { windowParams = it }
        params.width = width
        params.height = height
        params.x = params.x.coerceIn(0, (display.widthPixels - width).coerceAtLeast(0))
        params.y = params.y.coerceIn(0, (display.heightPixels - height).coerceAtLeast(0))
        try {
            if (root.isAttachedToWindow) {
                windowManager.updateViewLayout(root, params)
            } else {
                windowManager.addView(root, params)
            }
        } catch (_: SecurityException) {
            stopSelf()
        } catch (_: WindowManager.BadTokenException) {
            stopSelf()
        }
    }

    private fun createBubble(): View {
        val bubble = FrameLayout(this).apply {
            background = roundedDrawable(Color.rgb(57, 91, 201), dp(29), Color.rgb(57, 91, 201), 0)
            elevation = dp(7).toFloat()
            isClickable = true
            contentDescription = "افتح فقاعة البث"
        }
        val letter = TextView(this).apply {
            text = "ف"
            setTextColor(Color.WHITE)
            setTextSize(TypedValue.COMPLEX_UNIT_SP, 25f)
            typeface = Typeface.DEFAULT_BOLD
            gravity = Gravity.CENTER
            layoutDirection = View.LAYOUT_DIRECTION_RTL
        }
        bubble.addView(letter, FrameLayout.LayoutParams(-1, -1))
        val count = TextView(this).apply {
            text = ideas.length().coerceAtMost(99).toString()
            setTextColor(Color.WHITE)
            setTextSize(TypedValue.COMPLEX_UNIT_SP, 9f)
            typeface = Typeface.DEFAULT_BOLD
            gravity = Gravity.CENTER
            background = roundedDrawable(Color.rgb(239, 151, 67), dp(11), Color.WHITE, dp(2))
        }
        bubble.addView(
            count,
            FrameLayout.LayoutParams(dp(21), dp(21), Gravity.TOP or Gravity.LEFT).apply {
                leftMargin = dp(1)
                topMargin = dp(1)
            },
        )
        attachDragHandler(bubble) {
            expanded = true
            renderOverlay()
        }
        return bubble
    }

    private fun createPanel(): View {
        val card = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            layoutDirection = View.LAYOUT_DIRECTION_RTL
            setPadding(dp(16), dp(15), dp(16), dp(16))
            background = roundedDrawable(Color.WHITE, dp(23), Color.rgb(224, 231, 243), dp(1))
            elevation = dp(10).toFloat()
        }

        val header = LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER_VERTICAL
            layoutDirection = View.LAYOUT_DIRECTION_RTL
        }
        val emblem = TextView(this).apply {
            text = "ف"
            setTextColor(Color.WHITE)
            setTextSize(TypedValue.COMPLEX_UNIT_SP, 15f)
            typeface = Typeface.DEFAULT_BOLD
            gravity = Gravity.CENTER
            background = roundedDrawable(Color.rgb(60, 94, 207), dp(11), Color.rgb(60, 94, 207), 0)
        }
        header.addView(emblem, LinearLayout.LayoutParams(dp(38), dp(38)))
        val headerTitle = TextView(this).apply {
            text = "فقاعة البث"
            setTextColor(Color.rgb(31, 48, 75))
            setTextSize(TypedValue.COMPLEX_UNIT_SP, 16f)
            typeface = Typeface.DEFAULT_BOLD
            gravity = Gravity.CENTER_VERTICAL or Gravity.RIGHT
            setPadding(dp(9), 0, dp(4), 0)
            layoutDirection = View.LAYOUT_DIRECTION_RTL
            contentDescription = "اسحب لتحريك اللوحة"
        }
        header.addView(headerTitle, LinearLayout.LayoutParams(0, dp(44), 1f))
        attachDragHandler(headerTitle) {}
        header.addView(
            panelIconButton("−", "تصغير اللوحة") {
                expanded = false
                renderOverlay()
            },
            LinearLayout.LayoutParams(dp(40), dp(40)),
        )
        header.addView(View(this), LinearLayout.LayoutParams(dp(4), 1))
        header.addView(
            panelIconButton("×", "إغلاق الفقاعة") {
                preferences.edit().putBoolean(KEY_BUBBLE_ACTIVE, false).apply()
                stopSelf()
            },
            LinearLayout.LayoutParams(dp(40), dp(40)),
        )
        card.addView(header, LinearLayout.LayoutParams(-1, dp(44)))

        val selected = currentIdea()
        val title = TextView(this).apply {
            text = selected?.optString("title").orEmpty().ifBlank { "فكرة بلا عنوان" }
            setTextColor(Color.rgb(28, 43, 67))
            setTextSize(TypedValue.COMPLEX_UNIT_SP, 19f)
            typeface = Typeface.DEFAULT_BOLD
            gravity = Gravity.CENTER_VERTICAL or Gravity.RIGHT
            maxLines = 2
            ellipsize = android.text.TextUtils.TruncateAt.END
            textDirection = View.TEXT_DIRECTION_RTL
            layoutDirection = View.LAYOUT_DIRECTION_RTL
            setPadding(dp(3), dp(10), dp(3), dp(7))
        }
        card.addView(title, LinearLayout.LayoutParams(-1, dp(58)))

        val body = TextView(this).apply {
            text = selected?.optString("body").orEmpty().ifBlank {
                if (ideas.length() == 0) "لا توجد أفكار محفوظة بعد. أضف فكرة من التطبيق، ثم ستظهر هنا."
                else "لا يوجد نص لهذه الفكرة بعد."
            }
            setTextColor(Color.rgb(47, 61, 83))
            setTextSize(TypedValue.COMPLEX_UNIT_SP, fontSize.coerceIn(20, 48).toFloat())
            setLineSpacing(dp(5).toFloat(), 1.12f)
            gravity = Gravity.TOP or Gravity.RIGHT
            textDirection = View.TEXT_DIRECTION_RTL
            layoutDirection = View.LAYOUT_DIRECTION_RTL
            setPadding(dp(16), dp(15), dp(16), dp(17))
        }
        val scroll = ScrollView(this).apply {
            isFillViewport = true
            isVerticalScrollBarEnabled = true
            overScrollMode = View.OVER_SCROLL_IF_CONTENT_SCROLLS
            background = roundedDrawable(Color.rgb(247, 249, 253), dp(13), Color.rgb(236, 240, 247), dp(1))
            addView(body, FrameLayout.LayoutParams(-1, -2))
        }
        card.addView(scroll, LinearLayout.LayoutParams(-1, 0, 1f))

        if (ideas.length() == 0) {
            val openApp = panelTextButton("افتح التطبيق", Color.rgb(235, 240, 253), Color.rgb(52, 82, 180)) {
                openMainActivity()
            }
            card.addView(openApp, LinearLayout.LayoutParams(-1, dp(48)).apply { topMargin = dp(10) })
        } else {
            val controls = LinearLayout(this).apply {
                orientation = LinearLayout.HORIZONTAL
                gravity = Gravity.CENTER_VERTICAL
                layoutDirection = View.LAYOUT_DIRECTION_RTL
            }
            controls.addView(
                panelTextButton("السابق", Color.rgb(238, 242, 251), Color.rgb(52, 70, 105)) { stepIdea(-1) },
                LinearLayout.LayoutParams(0, dp(48), 1f),
            )
            controls.addView(View(this), LinearLayout.LayoutParams(dp(7), 1))
            controls.addView(
                panelTextButton("أ+", Color.rgb(238, 242, 251), Color.rgb(52, 82, 180)) { increaseFont() },
                LinearLayout.LayoutParams(dp(58), dp(48)),
            )
            controls.addView(View(this), LinearLayout.LayoutParams(dp(7), 1))
            controls.addView(
                panelTextButton("التالية", Color.rgb(238, 242, 251), Color.rgb(52, 70, 105)) { stepIdea(1) },
                LinearLayout.LayoutParams(0, dp(48), 1f),
            )
            card.addView(controls, LinearLayout.LayoutParams(-1, dp(48)).apply { topMargin = dp(10) })
        }
        return card
    }

    private fun panelIconButton(label: String, description: String, action: () -> Unit): TextView =
        TextView(this).apply {
            text = label
            contentDescription = description
            setTextColor(Color.rgb(76, 91, 115))
            setTextSize(TypedValue.COMPLEX_UNIT_SP, 23f)
            gravity = Gravity.CENTER
            background = roundedDrawable(Color.rgb(244, 247, 252), dp(11), Color.rgb(244, 247, 252), 0)
            isClickable = true
            setOnClickListener { action() }
        }

    private fun panelTextButton(label: String, backgroundColor: Int, textColor: Int, action: () -> Unit): TextView =
        TextView(this).apply {
            text = label
            setTextColor(textColor)
            setTextSize(TypedValue.COMPLEX_UNIT_SP, if (label == "أ+") 18f else 14f)
            typeface = Typeface.DEFAULT_BOLD
            gravity = Gravity.CENTER
            background = roundedDrawable(backgroundColor, dp(12), backgroundColor, 0)
            isClickable = true
            setOnClickListener { action() }
        }

    private fun attachDragHandler(view: View, onTap: () -> Unit) {
        var startX = 0
        var startY = 0
        var downRawX = 0f
        var downRawY = 0f
        var moved = false
        view.setOnTouchListener { touchedView, event ->
            when (event.actionMasked) {
                MotionEvent.ACTION_DOWN -> {
                    val params = windowParams ?: return@setOnTouchListener false
                    startX = params.x
                    startY = params.y
                    downRawX = event.rawX
                    downRawY = event.rawY
                    moved = false
                    true
                }

                MotionEvent.ACTION_MOVE -> {
                    val params = windowParams ?: return@setOnTouchListener false
                    val dx = (event.rawX - downRawX).toInt()
                    val dy = (event.rawY - downRawY).toInt()
                    if (abs(dx) > dp(5) || abs(dy) > dp(5)) moved = true
                    if (moved) {
                        val display = resources.displayMetrics
                        params.x = (startX - dx).coerceIn(0, (display.widthPixels - params.width).coerceAtLeast(0))
                        params.y = (startY + dy).coerceIn(0, (display.heightPixels - params.height).coerceAtLeast(0))
                        overlayRoot?.let { windowManager.updateViewLayout(it, params) }
                    }
                    true
                }

                MotionEvent.ACTION_UP -> {
                    if (!moved) onTap()
                    touchedView.performClick()
                    true
                }

                MotionEvent.ACTION_CANCEL -> true
                else -> false
            }
        }
    }

    private fun currentIdea(): JSONObject? {
        if (ideas.length() == 0) return null
        for (index in 0 until ideas.length()) {
            val idea = ideas.optJSONObject(index) ?: continue
            if (idea.optString("id") == selectedId) return idea
        }
        return ideas.optJSONObject(0)
    }

    private fun stepIdea(offset: Int) {
        if (ideas.length() == 0) return
        val index = (0 until ideas.length()).firstOrNull { ideas.optJSONObject(it)?.optString("id") == selectedId } ?: 0
        val next = (index + offset).coerceIn(0, ideas.length() - 1)
        selectedId = ideas.optJSONObject(next)?.optString("id")
        preferences.edit().putString(KEY_SELECTED_ID, selectedId).apply()
        renderOverlay()
    }

    private fun increaseFont() {
        fontSize = (fontSize + 2).coerceAtMost(48)
        preferences.edit().putInt(KEY_FONT_SIZE, fontSize).apply()
        renderOverlay()
    }

    private fun openMainActivity() {
        val intent = packageManager.getLaunchIntentForPackage(packageName) ?: return
        intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP)
        startActivity(intent)
    }

    private fun overlayWindowType(): Int = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
        WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY
    } else {
        @Suppress("DEPRECATION")
        WindowManager.LayoutParams.TYPE_PHONE
    }

    private fun roundedDrawable(color: Int, radius: Int, strokeColor: Int, strokeWidth: Int): GradientDrawable =
        GradientDrawable().apply {
            setColor(color)
            cornerRadius = radius.toFloat()
            if (strokeWidth > 0) setStroke(strokeWidth, strokeColor)
        }

    private fun dp(value: Int): Int = (value * resources.displayMetrics.density).toInt()

    companion object {
        const val PREFERENCES_NAME = "broadcast_bubble_local"
        const val KEY_IDEAS = "ideas_json"
        const val KEY_SELECTED_ID = "selected_id"
        const val KEY_FONT_SIZE = "font_size"
        const val KEY_BUBBLE_ACTIVE = "bubble_active"
        const val ACTION_START = "com.atherstudio.broadcast_bubble.START"
        const val ACTION_REFRESH = "com.atherstudio.broadcast_bubble.REFRESH"
        const val ACTION_STOP = "com.atherstudio.broadcast_bubble.STOP"
        private const val DEFAULT_FONT_SIZE = 30
        private const val CHANNEL_ID = "broadcast_bubble_overlay"
        private const val NOTIFICATION_ID = 7314

        @Volatile
        var isRunning: Boolean = false
            private set
    }
}
