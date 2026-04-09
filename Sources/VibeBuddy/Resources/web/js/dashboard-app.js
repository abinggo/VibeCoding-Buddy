/**
 * dashboard-app.js — Pixel art dashboard with charts and theme selection.
 */
(function() {
    'use strict';

    // ── Stats Update ───────────────────────────────────────
    window.vibe.on('statsUpdate', function(data) {
        document.getElementById('total-sessions').textContent = data.totalSessions || 0;
        document.getElementById('total-messages').textContent = data.totalMessages || 0;
        drawActivityChart(data.dailyActivity || []);
        drawTokenChart(data.dailyTokens || []);
    });

    // ── Pixel Bar Drawing ──────────────────────────────────

    function drawPixelBar(ctx, x, y, w, h, color) {
        ctx.fillStyle = color;
        var step = 4;
        for (var py = y; py < y + h; py += step) {
            for (var px = x; px < x + w; px += step) {
                ctx.fillRect(px, py, step - 1, step - 1);
            }
        }
    }

    // ── Activity Chart ─────────────────────────────────────

    function drawActivityChart(days) {
        var canvas = document.getElementById('activity-chart');
        var ctx = canvas.getContext('2d');
        ctx.imageSmoothingEnabled = false;
        ctx.clearRect(0, 0, canvas.width, canvas.height);
        if (days.length === 0) return;

        var maxVal = Math.max.apply(null, days.map(function(d) { return d.messages; })) || 1;
        var barWidth = Math.floor((canvas.width - 40) / days.length) - 8;
        var chartHeight = canvas.height - 40;

        days.forEach(function(day, i) {
            var barH = Math.floor((day.messages / maxVal) * chartHeight);
            var x = 30 + i * (barWidth + 8);
            var y = chartHeight - barH + 10;
            drawPixelBar(ctx, x, y, barWidth, barH, '#4ade80');

            ctx.fillStyle = '#666';
            ctx.font = '8px monospace';
            ctx.fillText(day.date.slice(5), x, canvas.height - 4);
        });

        ctx.fillStyle = '#666';
        ctx.font = '8px monospace';
        ctx.fillText(String(maxVal), 2, 16);
    }

    // ── Token Chart ────────────────────────────────────────

    function drawTokenChart(days) {
        var canvas = document.getElementById('token-chart');
        var ctx = canvas.getContext('2d');
        ctx.imageSmoothingEnabled = false;
        ctx.clearRect(0, 0, canvas.width, canvas.height);
        if (days.length === 0) return;

        var maxVal = Math.max.apply(null, days.map(function(d) { return d.tokens; })) || 1;
        var barWidth = Math.floor((canvas.width - 40) / days.length) - 8;
        var chartHeight = canvas.height - 40;

        days.forEach(function(day, i) {
            var barH = Math.floor((day.tokens / maxVal) * chartHeight);
            var x = 30 + i * (barWidth + 8);
            var y = chartHeight - barH + 10;
            drawPixelBar(ctx, x, y, barWidth, barH, '#60a5fa');

            ctx.fillStyle = '#666';
            ctx.font = '8px monospace';
            ctx.fillText(day.date.slice(5), x, canvas.height - 4);
        });

        ctx.fillStyle = '#666';
        ctx.font = '8px monospace';
        ctx.fillText(formatTokenCount(maxVal), 2, 16);
    }

    function formatTokenCount(n) {
        if (n >= 1000000) return (n / 1000000).toFixed(1) + 'M';
        if (n >= 1000) return Math.floor(n / 1000) + 'K';
        return String(n);
    }

    // ── Theme Selection ────────────────────────────────────
    document.getElementById('theme-select').addEventListener('change', function(e) {
        window.vibe.send('setTheme', { theme: e.target.value });
    });

    // ── Init ───────────────────────────────────────────────
    window.vibe.send('dashboardReady');
})();
