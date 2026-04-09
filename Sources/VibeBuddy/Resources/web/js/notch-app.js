/**
 * notch-app.js — Notch island main logic
 * Manages collapsed/expanded views, agent status, detail cards, and approval UI.
 */
(function() {
    'use strict';

    // ── State ──────────────────────────────────────────────
    var state = {
        agents: [],
        expanded: false,
        currentApprovalId: null
    };

    // ── DOM refs ───────────────────────────────────────────
    var countEl = document.getElementById('agent-count');
    var textEl = document.getElementById('status-text');
    var canvas = document.getElementById('agent-canvas');

    // ── Sprite System Init ─────────────────────────────────
    var renderer = new SpriteRenderer(canvas);
    var animSystem = new AnimationSystem(renderer);
    window.spriteRenderer = renderer;
    window.animSystem = animSystem;

    function resizeCanvas() {
        var rect = canvas.getBoundingClientRect();
        canvas.width = rect.width * 2;
        canvas.height = rect.height * 2;
        renderer.ctx.imageSmoothingEnabled = false;
    }

    // ── Canvas Click ───────────────────────────────────────
    canvas.addEventListener('click', function(e) {
        var rect = canvas.getBoundingClientRect();
        var x = (e.clientX - rect.left) * 2;
        var y = (e.clientY - rect.top) * 2;
        renderer.handleClick(x, y);
    });

    // ── Agent Updates ──────────────────────────────────────

    window.vibe.on('agentsUpdate', function(data) {
        state.agents = data.agents || [];
        renderCollapsed();
        animSystem.updateAgents(state.agents);
    });

    window.vibe.on('hookEvent', function(data) {
        if (data.type === 'PostToolUse' || data.type === 'Stop') {
            state.agents.forEach(function(a) {
                if (a.sessionId === data.sessionId) {
                    a.status = data.type === 'Stop' ? 'idle' : 'working';
                    a.lastTool = (data.payload && data.payload.tool_name) || '';
                }
            });
            renderCollapsed();
            animSystem.updateAgents(state.agents);
        }
    });

    // ── Expand / Collapse ──────────────────────────────────

    window.vibe.on('expand', function() {
        state.expanded = true;
        document.body.classList.add('expanded');
        resizeCanvas();
        renderer.start();
    });

    window.vibe.on('collapse', function() {
        state.expanded = false;
        document.body.classList.remove('expanded');
        renderer.stop();
        // Hide detail card when collapsing
        document.getElementById('agent-detail-card').style.display = 'none';
    });

    // ── Agent Detail ───────────────────────────────────────

    window.vibe.on('showAgentDetail', function(data) {
        var card = document.getElementById('agent-detail-card');
        document.getElementById('detail-title').textContent = data.name || 'Agent';
        document.getElementById('detail-status').textContent = data.status || 'working';
        document.getElementById('detail-cwd').textContent = shortenPath(data.cwd || '-');
        document.getElementById('detail-duration').textContent = formatDuration(data.startedAt);
        document.getElementById('detail-tool').textContent = data.lastTool || '-';
        card.style.display = 'block';
    });

    // ── Approval UI ────────────────────────────────────────

    window.vibe.on('approvalRequest', function(data) {
        state.currentApprovalId = data.approvalId;
        var panel = document.getElementById('approval-panel');
        document.getElementById('approval-tool').textContent = 'Tool: ' + data.toolName;

        var detail = '';
        if (data.toolInput) {
            if (data.toolInput.command) detail = data.toolInput.command;
            else if (data.toolInput.file_path) detail = data.toolInput.file_path;
            else if (data.toolInput.pattern) detail = data.toolInput.pattern;
        }
        document.getElementById('approval-detail').textContent = detail;
        panel.style.display = 'block';
    });

    window.vibe.on('approvalTimeout', function() {
        document.getElementById('approval-panel').style.display = 'none';
        state.currentApprovalId = null;
    });

    document.getElementById('btn-approve').addEventListener('click', function() {
        if (state.currentApprovalId) {
            window.vibe.send('approve', { approvalId: state.currentApprovalId });
            document.getElementById('approval-panel').style.display = 'none';
            state.currentApprovalId = null;
        }
    });

    document.getElementById('btn-deny').addEventListener('click', function() {
        if (state.currentApprovalId) {
            window.vibe.send('deny', { approvalId: state.currentApprovalId });
            document.getElementById('approval-panel').style.display = 'none';
            state.currentApprovalId = null;
        }
    });

    // ── Theme ──────────────────────────────────────────────

    window.vibe.on('setTheme', function(data) {
        if (data.theme) animSystem.setTheme(data.theme);
    });

    // ── Render Helpers ─────────────────────────────────────

    function renderCollapsed() {
        var count = state.agents.length;
        countEl.textContent = count;

        if (count === 0) {
            textEl.textContent = 'No agents';
        } else if (count === 1) {
            var a = state.agents[0];
            textEl.textContent = a.lastTool || a.name || 'Working...';
        } else {
            textEl.textContent = count + ' agents working';
        }
    }

    function shortenPath(p) {
        var parts = p.split('/');
        return parts.length > 3 ? '.../' + parts.slice(-2).join('/') : p;
    }

    function formatDuration(startMs) {
        if (!startMs) return '-';
        var secs = Math.floor((Date.now() - startMs) / 1000);
        if (secs < 60) return secs + 's';
        if (secs < 3600) return Math.floor(secs / 60) + 'm ' + (secs % 60) + 's';
        return Math.floor(secs / 3600) + 'h ' + Math.floor((secs % 3600) / 60) + 'm';
    }

    // ── Init ───────────────────────────────────────────────
    renderCollapsed();
    window.vibe.send('ready');
})();
