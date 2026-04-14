/**
 * dashboard-app.js — Pixel art dashboard with charts and theme selection.
 */
(function() {
    'use strict';

    // ── Stats Update ───────────────────────────────────────
    window.vibe.on('statsUpdate', function(data) {
        document.getElementById('total-sessions').textContent = data.totalSessions || 0;
        document.getElementById('total-messages').textContent = data.totalMessages || 0;
        document.getElementById('total-tokens').textContent = formatTokenCount(data.totalTokens || 0);
        drawActivityChart(data.dailyActivity || []);
        drawTokenChart(data.dailyActivity || []);
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

    // ── Activity Chart (Messages) ─────────────────────────

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
            if (day.messages > 0 && barH < 4) barH = 4;
            var x = 30 + i * (barWidth + 8);
            var y = chartHeight - barH + 10;
            drawPixelBar(ctx, x, y, barWidth, barH, '#4ade80');

            // Number label on top of bar
            if (day.messages > 0) {
                ctx.fillStyle = '#fff';
                ctx.font = '9px monospace';
                ctx.textAlign = 'center';
                ctx.fillText(String(day.messages), x + barWidth / 2, y - 4);
            }

            // Date label below
            ctx.fillStyle = '#666';
            ctx.font = '8px monospace';
            ctx.textAlign = 'center';
            ctx.fillText(day.date.slice(5), x + barWidth / 2, canvas.height - 4);
        });

        ctx.textAlign = 'left';
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

        var maxVal = Math.max.apply(null, days.map(function(d) { return d.tokens || 0; })) || 1;
        var barWidth = Math.floor((canvas.width - 40) / days.length) - 8;
        var chartHeight = canvas.height - 40;

        days.forEach(function(day, i) {
            var tokens = day.tokens || 0;
            var barH = Math.floor((tokens / maxVal) * chartHeight);
            if (tokens > 0 && barH < 4) barH = 4;
            var x = 30 + i * (barWidth + 8);
            var y = chartHeight - barH + 10;
            drawPixelBar(ctx, x, y, barWidth, barH, '#60a5fa');

            // Number label on top of bar
            if (tokens > 0) {
                ctx.fillStyle = '#fff';
                ctx.font = '9px monospace';
                ctx.textAlign = 'center';
                ctx.fillText(formatTokenCount(tokens), x + barWidth / 2, y - 4);
            }

            // Date label below
            ctx.fillStyle = '#666';
            ctx.font = '8px monospace';
            ctx.textAlign = 'center';
            ctx.fillText(day.date.slice(5), x + barWidth / 2, canvas.height - 4);
        });

        ctx.textAlign = 'left';
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
