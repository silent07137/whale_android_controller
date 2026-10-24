package cn.whale.controller;

import android.app.Activity;
import android.app.ActivityManager;
import android.content.Intent;
import android.content.SharedPreferences;
import android.graphics.Color;
import android.graphics.Typeface;
import android.graphics.drawable.GradientDrawable;
import android.net.Uri;
import android.os.Bundle;
import android.view.Gravity;
import android.view.View;
import android.widget.Button;
import android.widget.CompoundButton;
import android.widget.LinearLayout;
import android.widget.ScrollView;
import android.widget.Switch;
import android.widget.TextView;

import java.io.File;
import java.io.FileOutputStream;
import java.io.InputStream;
import java.nio.charset.StandardCharsets;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;
import java.util.concurrent.TimeUnit;

/**
 * 大肥鱼控制台：仅负责用户主动发起的 Root 命令和显示状态。
 * 长期监控由用户授权后的 KernelSU Root 脚本独立执行，无需运行 Termux Activity。
 */
public class MainActivity extends Activity {
    private static final int BG = Color.rgb(16, 22, 37);
    private static final int PANEL = Color.rgb(28, 39, 60);
    private static final int WHITE = Color.rgb(241, 248, 255);
    private static final int MUTED = Color.rgb(168, 193, 212);
    private static final int BLUE = Color.rgb(132, 194, 241);
    private static final int GOLD = Color.rgb(245, 210, 158);

    private final ExecutorService worker = Executors.newSingleThreadExecutor();
    private LinearLayout body;
    private TextView statusText;
    private TextView activityText;
    private Switch hideToggle;
    private Switch guardToggle;
    private Switch bootToggle;
    private Button startButton;
    private Button stopButton;
    private Button refreshButton;
    private boolean syncing = false;
    private boolean busy = false;
    private File installScript;

    @Override public void onCreate(Bundle state) {
        super.onCreate(state);
        getWindow().setStatusBarColor(BG);
        getWindow().setNavigationBarColor(BG);
        getWindow().getDecorView().setSystemUiVisibility(0);
        installScript = new File(getFilesDir(), "controller.sh");
        createUi();
        SharedPreferences prefs = getSharedPreferences("ui", MODE_PRIVATE);
        syncing = true;
        hideToggle.setChecked(prefs.getBoolean("hide", false));
        syncing = false;
        applyHideFromRecents(hideToggle.isChecked());
        hideToggle.setOnCheckedChangeListener((button, value) -> {
            if (syncing) return;
            prefs.edit().putBoolean("hide", value).apply();
            applyHideFromRecents(value);
            activityText.setText(value ? "控制台已从最近任务隐藏，桌面图标仍可打开" : "控制台可显示在最近任务");
        });
        guardToggle.setOnCheckedChangeListener((button, value) -> {
            if (!syncing) execute(value ? "watch-on" : "watch-off");
        });
        bootToggle.setOnCheckedChangeListener((button, value) -> {
            if (!syncing) execute(value ? "boot-on" : "boot-off");
        });
        execute("install");
    }

    @Override public void onDestroy() {
        worker.shutdownNow();
        super.onDestroy();
    }

    private void createUi() {
        ScrollView scroll = new ScrollView(this);
        scroll.setFillViewport(true);
        scroll.setBackgroundColor(BG);
        body = new LinearLayout(this);
        body.setPadding(dp(20), dp(20), dp(20), dp(26));
        body.setOrientation(LinearLayout.VERTICAL);
        scroll.addView(body);
        setContentView(scroll);

        TextView title = text("🐋  大肥鱼控制台", 25, WHITE, true);
        body.addView(title);
        TextView subtitle = text("蓝色大肥鱼  ·  QQ Agent 0.4  ·  SnowLuma", 12, MUTED, false);
        subtitle.setPadding(0, dp(7), 0, dp(15));
        body.addView(subtitle);

        LinearLayout statusBox = panel();
        statusBox.addView(text("运行状态", 17, GOLD, true));
        statusText = text("正在连接 Root 控制层……", 14, WHITE, false);
        statusText.setLineSpacing(dp(3), 1.0f);
        statusText.setPadding(0, dp(12), 0, 0);
        statusBox.addView(statusText);
        body.addView(statusBox);

        LinearLayout controls = panel();
        controls.addView(text("快捷操作", 17, GOLD, true));
        startButton = button("启动大肥鱼", true);
        stopButton = button("关闭大肥鱼", false);
        refreshButton = button("刷新运行状态", false);
        controls.addView(startButton);
        controls.addView(stopButton);
        controls.addView(refreshButton);
        startButton.setOnClickListener(v -> execute("start"));
        stopButton.setOnClickListener(v -> execute("stop"));
        refreshButton.setOnClickListener(v -> execute("status"));
        body.addView(controls);

        LinearLayout options = panel();
        options.addView(text("后台设置", 17, GOLD, true));
        hideToggle = new Switch(this);
        setupSwitch(hideToggle, "后台隐藏（最近任务不显示本 App）");
        options.addView(hideToggle);
        guardToggle = new Switch(this);
        setupSwitch(guardToggle, "后台守护（每 90 秒检测，连续失败两次恢复）");
        options.addView(guardToggle);
        bootToggle = new Switch(this);
        setupSwitch(bootToggle, "开机自启（KernelSU boot-completed.d）");
        options.addView(bootToggle);
        TextView note = text("隐藏最近任务 ≠ 永久保活。守护脚本在 Root 后台运行，不会打开 Termux 窗口。启动和停止保留手动控制；不能保证断线期间的消息全部补收。", 12, MUTED, false);
        note.setPadding(0, dp(8), 0, 0);
        options.addView(note);
        body.addView(options);

        LinearLayout browser = panel();
        browser.addView(text("管理页面", 17, GOLD, true));
        Button qq = button("QQ Agent · 3210", false);
        Button snow = button("SnowLuma · 5099", false);
        Button vnc = button("Linux QQ 桌面 · 6081", false);
        qq.setOnClickListener(v -> open("http://127.0.0.1:3210"));
        snow.setOnClickListener(v -> open("http://127.0.0.1:5099"));
        vnc.setOnClickListener(v -> open("http://127.0.0.1:6081/vnc.html"));
        browser.addView(qq); browser.addView(snow); browser.addView(vnc);
        body.addView(browser);

        LinearLayout output = panel();
        output.addView(text("最近操作", 17, GOLD, true));
        activityText = text("尚未执行操作", 12, MUTED, false);
        activityText.setLineSpacing(dp(3), 1.0f);
        activityText.setPadding(0, dp(10), 0, 0);
        output.addView(activityText);
        Button logs = button("查看守护日志", false);
        logs.setOnClickListener(v -> execute("logs"));
        output.addView(logs);
        body.addView(output);
    }

    private void setupSwitch(Switch toggle, String name) {
        toggle.setText(name);
        toggle.setTextColor(WHITE);
        toggle.setTextSize(13);
        toggle.setPadding(0, dp(16), 0, dp(10));
    }

    private TextView text(String message, int size, int color, boolean bold) {
        TextView out = new TextView(this);
        out.setText(message);
        out.setTextColor(color);
        out.setTextSize(size);
        if (bold) out.setTypeface(Typeface.DEFAULT, Typeface.BOLD);
        return out;
    }

    private LinearLayout panel() {
        LinearLayout box = new LinearLayout(this);
        box.setOrientation(LinearLayout.VERTICAL);
        box.setPadding(dp(17), dp(15), dp(17), dp(15));
        GradientDrawable bg = new GradientDrawable();
        bg.setColor(PANEL);
        bg.setCornerRadius(dp(18));
        bg.setStroke(dp(1), Color.rgb(49, 69, 96));
        box.setBackground(bg);
        LinearLayout.LayoutParams params = new LinearLayout.LayoutParams(-1, -2);
        params.setMargins(0, dp(6), 0, dp(12));
        box.setLayoutParams(params);
        return box;
    }

    private Button button(String title, boolean primary) {
        Button button = new Button(this);
        button.setText(title);
        button.setAllCaps(false);
        button.setTextColor(primary ? BG : WHITE);
        button.setTextSize(14);
        button.setGravity(Gravity.CENTER);
        GradientDrawable d = new GradientDrawable();
        d.setColor(primary ? BLUE : Color.rgb(47, 65, 89));
        d.setCornerRadius(dp(13));
        button.setBackground(d);
        LinearLayout.LayoutParams p = new LinearLayout.LayoutParams(-1, dp(47));
        p.setMargins(0, dp(12), 0, 0);
        button.setLayoutParams(p);
        return button;
    }

    private int dp(float n) { return (int)(n * getResources().getDisplayMetrics().density + 0.5f); }

    private void applyHideFromRecents(boolean hide) {
        try {
            ActivityManager manager = getSystemService(ActivityManager.class);
            if (manager != null) for (ActivityManager.AppTask task : manager.getAppTasks()) {
                task.setExcludeFromRecents(hide);
            }
        } catch (Exception ignored) {
            // 有些厂商系统会拦截；不能因此破坏启动/关闭功能。
        }
    }

    private void open(String url) {
        try { startActivity(new Intent(Intent.ACTION_VIEW, Uri.parse(url))); }
        catch (Exception ex) { activityText.setText("浏览器打开失败：" + ex.getMessage()); }
    }

    private synchronized void execute(String action) {
        if (busy) return;
        busy = true;
        setControlsEnabled(false);
        activityText.setText("正在执行 " + action + "……\n首次使用时请在 Root 管理器中授权本 App。");
        worker.execute(() -> {
            String result;
            try {
                if ("install".equals(action)) writeAsset();
                String script = "install".equals(action) ? installScript.getAbsolutePath() :
                        "/data/adb/whale-controller/controller.sh";
                String command = "/system/bin/sh " + script + " " + action;
                Process process = new ProcessBuilder("su", "-c", command)
                        .redirectErrorStream(true).start();
                boolean finished = process.waitFor(55, TimeUnit.SECONDS);
                if (!finished) {
                    process.destroy();
                    result = "操作超时，请检查 Root 授权弹窗或后台日志。";
                } else {
                    byte[] bytes = process.getInputStream().readNBytes(24000);
                    result = "退出码 " + process.exitValue() + "\n" + new String(bytes, StandardCharsets.UTF_8);
                }
            } catch (Exception error) {
                result = "执行失败：" + error.toString();
            }
            final String response = result;
            runOnUiThread(() -> {
                activityText.setText(response);
                busy = false;
                setControlsEnabled(true);
                if ("install".equals(action) && response.contains("CONTROLLER_INSTALLED=1")) execute("status");
                else if (!"logs".equals(action) && !"status".equals(action) &&
                        !"install".equals(action)) execute("status");
                else if ("status".equals(action)) parseStatus(response);
            });
        });
    }

    private void parseStatus(String result) {
        statusText.setText(result.replace("退出码 0\n", ""));
        syncing = true;
        if (result.contains("WATCH=ON")) guardToggle.setChecked(true);
        else if (result.contains("WATCH=OFF")) guardToggle.setChecked(false);
        if (result.contains("AUTOBOOT=ON")) bootToggle.setChecked(true);
        else if (result.contains("AUTOBOOT=OFF")) bootToggle.setChecked(false);
        syncing = false;
    }

    private void setControlsEnabled(boolean enabled) {
        if (startButton != null) startButton.setEnabled(enabled);
        if (stopButton != null) stopButton.setEnabled(enabled);
        if (refreshButton != null) refreshButton.setEnabled(enabled);
    }

    private void writeAsset() throws Exception {
        try (InputStream in = getAssets().open("controller.sh");
             FileOutputStream out = new FileOutputStream(installScript, false)) {
            byte[] buffer = new byte[8192];
            int n;
            while ((n = in.read(buffer)) > 0) out.write(buffer, 0, n);
        }
        installScript.setReadable(true, true);
    }
}
