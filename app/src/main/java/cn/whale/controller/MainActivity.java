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
import android.widget.Button;
import android.widget.LinearLayout;
import android.widget.ScrollView;
import android.widget.Switch;
import android.widget.TextView;

import java.io.File;
import java.io.FileOutputStream;
import java.io.InputStream;
import java.nio.charset.StandardCharsets;
import java.util.ArrayList;
import java.util.List;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;
import java.util.concurrent.TimeUnit;

/**
 * 小鲸鱼控制台：单独管理 QQAgentPlus，不接触 XiAgent Mobile 或旧 QQAgent 数据。
 * Root 控制脚本只能操作固定 lab 目录；自动守护、开机启动默认关闭。
 */
public final class MainActivity extends Activity {
    private static final int BG = 0xff111a2b;
    private static final int PANEL = 0xff1d2b43;
    private static final int TEXT = 0xfff5f9ff;
    private static final int MUTED = 0xffb3c6df;
    private static final int BLUE = 0xff9bd5f5;
    private static final int GOLD = 0xffffdfaa;

    private final ExecutorService worker = Executors.newSingleThreadExecutor();
    private final List<Button> commands = new ArrayList<>();
    private TextView summary, details, output;
    private Switch watchToggle, bootToggle, hideToggle;
    private boolean syncing = false;
    private boolean busy = false;
    private File rootSource, labSource;

    @Override public void onCreate(Bundle state) {
        super.onCreate(state);
        getWindow().setStatusBarColor(BG);
        getWindow().setNavigationBarColor(BG);
        rootSource = new File(getFilesDir(), "qqplus-root.sh");
        labSource = new File(getFilesDir(), "qqplus-lab.sh");
        createUi();
        SharedPreferences prefs = getSharedPreferences("options", MODE_PRIVATE);
        syncing = true;
        hideToggle.setChecked(prefs.getBoolean("hide_from_recents", false));
        syncing = false;
        setTaskHidden(hideToggle.isChecked());
        hideToggle.setOnCheckedChangeListener((b, active) -> {
            if (syncing) return;
            prefs.edit().putBoolean("hide_from_recents", active).apply();
            setTaskHidden(active);
        });
        watchToggle.setOnCheckedChangeListener((b, active) -> {
            if (!syncing) runCommand(active ? "watch-on" : "watch-off");
        });
        bootToggle.setOnCheckedChangeListener((b, active) -> {
            if (!syncing) runCommand(active ? "boot-on" : "boot-off");
        });
        runCommand("install");
    }

    @Override public void onDestroy() {
        worker.shutdownNow();
        super.onDestroy();
    }

    private void createUi() {
        ScrollView scroll = new ScrollView(this);
        scroll.setFillViewport(true);
        scroll.setBackgroundColor(BG);
        LinearLayout body = new LinearLayout(this);
        body.setPadding(dp(18), dp(24), dp(18), dp(28));
        body.setOrientation(LinearLayout.VERTICAL);
        scroll.addView(body);
        setContentView(scroll);

        body.addView(text("🐳  小鲸鱼控制台", 26, TEXT, true));
        TextView subtitle = text("QQAgentPlus  ·  SnowLuma 2.1.1  ·  Ubuntu chroot", 12, MUTED, false);
        subtitle.setPadding(0, dp(6), 0, dp(18));
        body.addView(subtitle);

        LinearLayout health = card(body, "当前运行状态");
        summary = text("尚未读取服务状态", 17, BLUE, true);
        summary.setPadding(0, dp(10), 0, dp(8));
        details = text("首次启动需要 KernelSU Root 授权。", 13, TEXT, false);
        details.setLineSpacing(dp(3), 1.0f);
        health.addView(summary);
        health.addView(details);

        LinearLayout actions = card(body, "快捷操作");
        button(actions, "启动小鲸鱼", true, "start");
        button(actions, "正常停止", false, "stop");
        button(actions, "刷新运行状态", false, "status");
        button(actions, "重新检查 KernelSU 授权", false, "install");

        LinearLayout background = card(body, "后台与开机");
        watchToggle = option(background, "后台守护（每 120 秒检测，最多恢复 3 次）");
        bootToggle = option(background, "开机自动启动（KernelSU）");
        hideToggle = option(background, "从最近任务隐藏本控制台");
        background.addView(text("守护不会自动注入任意 QQ 进程。SnowLuma 重启后可能需要手动注入新号；登录状态和断线消息补收无法保证。", 12, MUTED, false));

        LinearLayout pages = card(body, "管理页面");
        button(pages, "QQAgentPlus · 43210", false, null)
                .setOnClickListener(v -> open("http://127.0.0.1:43210"));
        button(pages, "SnowLuma · 5100", false, null)
                .setOnClickListener(v -> open("http://127.0.0.1:5100"));
        button(pages, "Linux QQ 桌面 · 6082", false, null)
                .setOnClickListener(v -> open("http://127.0.0.1:6082/vnc.html"));

        LinearLayout logs = card(body, "诊断日志");
        button(logs, "QQAgentPlus 日志", false, "log-agent");
        button(logs, "SnowLuma 日志", false, "log-snow");
        button(logs, "Linux QQ 日志", false, "log-qq");
        button(logs, "守护日志", false, "log-watch");
        button(logs, "开机日志", false, "log-boot");
        logs.addView(text("日志可能包含私人消息、账号信息或凭据，请勿直接公开完整日志。", 12, MUTED, false));

        LinearLayout operations = card(body, "操作结果");
        output = text("还没有执行操作", 12, MUTED, false);
        output.setTextIsSelectable(true);
        output.setLineSpacing(dp(3), 1.0f);
        operations.addView(output);

        body.addView(text("独立运行目录 /root/qqagentplus-lab\n不管理旧鲸鱼控制台、汐的资料或 XiAgent Mobile。", 11, MUTED, false));
    }

    private LinearLayout card(LinearLayout parent, String header) {
        LinearLayout out = new LinearLayout(this);
        out.setOrientation(LinearLayout.VERTICAL);
        out.setPadding(dp(17), dp(16), dp(17), dp(17));
        GradientDrawable shape = new GradientDrawable();
        shape.setColor(PANEL);
        shape.setCornerRadius(dp(18));
        shape.setStroke(dp(1), 0xff344765);
        out.setBackground(shape);
        LinearLayout.LayoutParams lp = new LinearLayout.LayoutParams(-1, -2);
        lp.setMargins(0, 0, 0, dp(14));
        parent.addView(out, lp);
        out.addView(text(header, 17, GOLD, true));
        return out;
    }

    private Button button(LinearLayout parent, String label, boolean primary, String action) {
        Button result = new Button(this);
        result.setAllCaps(false);
        result.setText(label);
        result.setTextSize(14);
        result.setTextColor(primary ? BG : TEXT);
        GradientDrawable bg = new GradientDrawable();
        bg.setColor(primary ? BLUE : 0xff334965);
        bg.setCornerRadius(dp(12));
        result.setBackground(bg);
        LinearLayout.LayoutParams lp = new LinearLayout.LayoutParams(-1, dp(48));
        lp.topMargin = dp(10);
        parent.addView(result, lp);
        if (action != null) {
            commands.add(result);
            result.setOnClickListener(v -> runCommand(action));
        }
        return result;
    }

    private Switch option(LinearLayout parent, String title) {
        Switch sw = new Switch(this);
        sw.setText(title);
        sw.setTextColor(TEXT);
        sw.setTextSize(13);
        sw.setPadding(0, dp(15), 0, dp(13));
        parent.addView(sw);
        return sw;
    }

    private TextView text(String content, int size, int color, boolean bold) {
        TextView label = new TextView(this);
        label.setText(content);
        label.setTextSize(size);
        label.setTextColor(color);
        if (bold) label.setTypeface(Typeface.DEFAULT, Typeface.BOLD);
        return label;
    }
    private int dp(float n) {
        return (int)(n * getResources().getDisplayMetrics().density + 0.5f);
    }
    private void open(String url) {
        try { startActivity(new Intent(Intent.ACTION_VIEW, Uri.parse(url))); }
        catch (Exception e) { output.setText("打开浏览器失败：" + e.getMessage()); }
    }
    private void setTaskHidden(boolean hidden) {
        try {
            ActivityManager am = getSystemService(ActivityManager.class);
            if (am != null) for (ActivityManager.AppTask task : am.getAppTasks())
                task.setExcludeFromRecents(hidden);
        } catch (Exception ignored) { }
    }
    private void writeAsset(String name, File destination) throws Exception {
        try (InputStream in = getAssets().open(name);
             FileOutputStream stream = new FileOutputStream(destination, false)) {
            byte[] buf = new byte[8192];
            int n;
            while ((n = in.read(buf)) != -1) stream.write(buf, 0, n);
        }
    }
    private String quote(String path) {
        return "'" + path.replace("'", "'\\''") + "'";
    }
    private synchronized void runCommand(String action) {
        if (busy) return;
        busy = true;
        for (Button button : commands) button.setEnabled(false);
        if (watchToggle != null) watchToggle.setEnabled(false);
        if (bootToggle != null) bootToggle.setEnabled(false);
        output.setText("正在执行：" + action + "\n首次使用时请在 KernelSU 中授权。");
        worker.execute(() -> {
            String result;
            try {
                String call;
                if ("install".equals(action)) {
                    writeAsset("qqplus-root.sh", rootSource);
                    writeAsset("qqplus-lab.sh", labSource);
                    call = "/system/bin/sh " + quote(rootSource.getAbsolutePath()) +
                            " install " + quote(rootSource.getAbsolutePath()) +
                            " " + quote(labSource.getAbsolutePath());
                } else {
                    call = "/system/bin/sh /data/adb/qqaplus-controller/controller.sh " + action;
                }
                // KernelSU 只向获准应用开放 su；未经手动授权时，execve 可能直接 EACCES。
                // 不修改 SELinux/su 权限，不在此使用其它应用的 Root 权限。
                Process process = new ProcessBuilder("su", "-c", call)
                        .redirectErrorStream(true).start();
                boolean completed = process.waitFor(55, TimeUnit.SECONDS);
                if (!completed) {
                    process.destroyForcibly();
                    result = "执行超时。请检查 Root 授权及日志。\n";
                } else {
                    byte[] outputBytes = process.getInputStream().readNBytes(24000);
                    result = "退出码：" + process.exitValue() + "\n" +
                            new String(outputBytes, StandardCharsets.UTF_8);
                }
            } catch (Exception e) {
                String description = String.valueOf(e.getMessage());
                if (description.contains("Cannot run program \"su\"") &&
                        description.contains("Permission denied")) {
                    result = "ROOT_PERMISSION_DENIED=YES\n" +
                        "KernelSU 尚未允许本应用调用 su。\n" +
                        "请在 KernelSU → 超级用户中，找到「小鲸鱼控制台」\n" +
                        "（cn.whale.qqaplus.controller），手动开启 Root。\n" +
                        "然后返回本页点击「重新检查 KernelSU 授权」。\n" +
                        "无需重装 Ubuntu，也不要更改 SELinux 或 su 文件权限。";
                } else {
                    result = "执行失败：" + e;
                }
            }
            final String safe = redact(result);
            runOnUiThread(() -> {
                output.setText("操作：" + action + "\n" + safe);
                busy = false;
                for (Button button : commands) button.setEnabled(true);
                if (watchToggle != null) watchToggle.setEnabled(true);
                if (bootToggle != null) bootToggle.setEnabled(true);
                if (safe.contains("ROOT_PERMISSION_DENIED=YES")) {
                    summary.setText("● 需要在 KernelSU 授予 Root");
                    details.setText("小鲸鱼控制台尚无 Root 授权。请先授权，再点击「重新检查 KernelSU 授权」。");
                } else if ("status".equals(action)) applyStatus(safe);
                else if ("install".equals(action) && safe.contains("INSTALLED=YES")) runCommand("status");
                else if (!action.startsWith("log-")) runCommand("status");
            });
        });
    }
    private String redact(String input) {
        return input
            .replaceAll("(?i)(api[_-]?key|access[_-]?token|authorization|password|secret)(\\s*[:=]\\s*)[^\\s]+", "$1$2[已隐藏]")
            .replaceAll("sk-[A-Za-z0-9_-]{8,}", "sk-[已隐藏]");
    }
    private void applyStatus(String result) {
        if (result.contains("ROOT_PERMISSION_DENIED=YES")) {
            summary.setText("● 需要在 KernelSU 授予 Root");
            details.setText("请在 KernelSU → 超级用户中允许 cn.whale.qqaplus.controller，随后重新检查。");
            return;
        }
        details.setText(result.replace("退出码：0\n", ""));
        boolean agent = result.contains("AGENT=UP");
        boolean snow = result.contains("SNOWLUMA=UP");
        boolean qq = result.contains("QQ_PROCESS=UP");
        if (agent && snow && qq) summary.setText("● 核心服务在线 · 消息链路待独立验证");
        else summary.setText("● 部分服务未就绪");
        syncing = true;
        watchToggle.setChecked(result.contains("WATCH=ON"));
        bootToggle.setChecked(result.contains("AUTOBOOT=ON"));
        syncing = false;
    }
}
