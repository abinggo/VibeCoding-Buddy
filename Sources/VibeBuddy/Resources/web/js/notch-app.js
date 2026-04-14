/**
 * notch-app.js — Floating bubble main logic
 * Manages collapsed/expanded views, agent status, detail cards, approval UI, and stats.
 */
(function() {
    'use strict';

    // ── State ──────────────────────────────────────────────
    var state = {
        agents: [],
        expanded: false,
        currentApprovalId: null,
        globalStatus: 'idle',  // 'idle' | 'working' | 'waiting'
        stats: null
    };

    // ── DOM refs ───────────────────────────────────────────
    var countEl = document.getElementById('agent-count');
    var textEl = document.getElementById('status-text');
    var headerCountEl = document.getElementById('header-count');
    var canvas = document.getElementById('agent-canvas');
    var agentListEl = document.getElementById('agent-list');
    var noAgentsEl = document.getElementById('no-agents-msg');

    // Stats elements
    var statTokensEl = document.getElementById('stat-tokens');
    var statMessagesEl = document.getElementById('stat-messages');
    var statSessionsEl = document.getElementById('stat-sessions');
    var statToolsEl = document.getElementById('stat-tools');

    // ── Sprite System Init ─────────────────────────────────
    var renderer = new SpriteRenderer(canvas);
    var animSystem = new AnimationSystem(renderer);
    renderer.animSystem = animSystem;
    window.spriteRenderer = renderer;
    window.animSystem = animSystem;

    function resizeCanvas() {
        var rect = canvas.getBoundingClientRect();
        if (rect.width > 0 && rect.height > 0) {
            canvas.width = rect.width * 2;
            canvas.height = rect.height * 2;
            renderer.ctx.imageSmoothingEnabled = false;
        }
    }

    // ── Agent Updates ──────────────────────────────────────

    window.vibe.on('agentsUpdate', function(data) {
        state.agents = data.agents || [];
        updateGlobalStatus();
        renderCollapsed();
        renderAgentList();
        animSystem.updateAgents(state.agents);
    });

    window.vibe.on('hookEvent', function(data) {
        if (data.type === 'PostToolUse' || data.type === 'Stop') {
            state.agents.forEach(function(a) {
                if (a.sessionId === data.sessionId) {
                    if (data.type === 'Stop') {
                        a.status = 'waiting';
                    } else {
                        a.status = 'working';
                        a.lastTool = (data.payload && data.payload.tool_name) || '';
                    }
                }
            });
            updateGlobalStatus();
            renderCollapsed();
            renderAgentList();
            animSystem.updateAgents(state.agents);
        }
    });

    // ── Stats Updates ──────────────────────────────────────

    window.vibe.on('statsUpdate', function(data) {
        state.stats = data;
        renderStats();
    });

    // ── Expand / Collapse ──────────────────────────────────

    window.vibe.on('expand', function() {
        state.expanded = true;
        document.body.classList.add('expanded');
        // Request fresh stats on expand
        window.vibe.send('requestStats');
        setTimeout(function() {
            resizeCanvas();
            renderer.start();
        }, 250);
    });

    window.vibe.on('collapse', function() {
        state.expanded = false;
        document.body.classList.remove('expanded');
        renderer.stop();
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
        state.currentApprovalSessionId = data.sessionId || '';
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
        state.currentApprovalSessionId = null;
    });

    document.getElementById('btn-approve').addEventListener('click', function() {
        if (state.currentApprovalId) {
            window.vibe.send('approve', { approvalId: state.currentApprovalId, sessionId: state.currentApprovalSessionId });
            document.getElementById('approval-panel').style.display = 'none';
            state.currentApprovalId = null;
            state.currentApprovalSessionId = null;
        }
    });

    document.getElementById('btn-deny').addEventListener('click', function() {
        if (state.currentApprovalId) {
            window.vibe.send('deny', { approvalId: state.currentApprovalId, sessionId: state.currentApprovalSessionId });
            document.getElementById('approval-panel').style.display = 'none';
            state.currentApprovalId = null;
            state.currentApprovalSessionId = null;
        }
    });

    // Enter = Approve, Escape = Deny when approval panel is visible
    document.addEventListener('keydown', function(e) {
        if (!state.currentApprovalId) return;
        if (e.key === 'Enter') {
            e.preventDefault();
            document.getElementById('btn-approve').click();
        } else if (e.key === 'Escape') {
            e.preventDefault();
            document.getElementById('btn-deny').click();
        }
    });

    // ── Dashboard link ─────────────────────────────────────
    var dashBtn = document.getElementById('btn-dashboard');
    if (dashBtn) {
        dashBtn.addEventListener('click', function() {
            window.vibe.send('openDashboard');
        });
    }

    // ── Theme ──────────────────────────────────────────────

    window.vibe.on('setTheme', function(data) {
        if (data.theme) animSystem.setTheme(data.theme);
    });

    // ── Status Logic ───────────────────────────────────────

    function updateGlobalStatus() {
        var agents = state.agents;
        var oldStatus = state.globalStatus;

        if (agents.length === 0) {
            state.globalStatus = 'idle';
        } else {
            var anyWorking = agents.some(function(a) {
                return a.status === 'working';
            });
            state.globalStatus = anyWorking ? 'working' : 'waiting';
        }

        if (oldStatus !== state.globalStatus) {
            document.body.classList.remove('status-idle', 'status-working', 'status-waiting');
            document.body.classList.add('status-' + state.globalStatus);
        }
    }

    // ── Render Helpers ─────────────────────────────────────

    function renderCollapsed() {
        var count = state.agents.length;
        countEl.textContent = count;

        var statusLabels = {
            idle: 'Idle',
            working: 'Working',
            waiting: 'Done'
        };

        if (count === 0) {
            textEl.textContent = 'Idle';
        } else if (count === 1) {
            var a = state.agents[0];
            if (a.status === 'working') {
                textEl.textContent = a.lastTool || 'Working';
            } else if (a.status === 'waiting') {
                textEl.textContent = 'Done';
            } else {
                textEl.textContent = 'Ready';  // idle/connected — neutral
            }
        } else {
            var workingCount = state.agents.filter(function(a) { return a.status === 'working'; }).length;
            if (workingCount > 0) {
                textEl.textContent = workingCount + ' working';
            } else {
                var waitingCount = state.agents.filter(function(a) { return a.status === 'waiting'; }).length;
                textEl.textContent = waitingCount > 0 ? 'All done' : 'Ready';
            }
        }

        if (headerCountEl) {
            headerCountEl.textContent = count + (count === 1 ? ' agent' : ' agents');
        }
    }

    // Custom agent names (persisted in localStorage)
    function getAgentName(sessionId, defaultName) {
        var custom = localStorage.getItem('agentName_' + sessionId);
        return custom || defaultName || 'Claude Code';
    }

    function setAgentName(sessionId, name) {
        if (name) {
            localStorage.setItem('agentName_' + sessionId, name);
        } else {
            localStorage.removeItem('agentName_' + sessionId);
        }
    }

    function renderAgentList() {
        if (!agentListEl) return;
        var agents = state.agents;

        if (agents.length === 0) {
            agentListEl.innerHTML = '';
            if (noAgentsEl) noAgentsEl.style.display = 'block';
            return;
        }
        if (noAgentsEl) noAgentsEl.style.display = 'none';

        var html = '';
        agents.forEach(function(a) {
            var statusColor = a.status === 'waiting' ? '#fbbf24' : (a.status === 'idle' ? '#888' : '#4ade80');
            var statusLabel = a.status === 'waiting' ? 'done' : (a.status || 'working');
            var statusDot = '<span style="color:' + statusColor + ';">&#9679;</span> ';
            var name = escapeHtml(getAgentName(a.sessionId, a.name));
            var cwd = escapeHtml(shortenPath(a.cwd || ''));
            var duration = formatDuration(a.startedAt);
            var tool = a.lastTool ? ' | ' + escapeHtml(a.lastTool) : '';

            html += '<div class="agent-row" data-sid="' + escapeHtml(a.sessionId) + '">'
                + statusDot + '<span class="agent-name" data-sid="' + escapeHtml(a.sessionId) + '"><strong>' + name + '</strong>'
                + ' <span class="rename-icon" data-sid="' + escapeHtml(a.sessionId) + '" style="cursor:pointer;color:#aaa;font-size:9px;" title="Rename">&#9998;</span></span>'
                + ' <span style="color:' + statusColor + '; font-size:5px;">(' + statusLabel + ')</span>'
                + '<br><span class="agent-meta">' + cwd + ' | ' + duration + tool + '</span>'
                + '</div>';
        });
        agentListEl.innerHTML = html;

        // Click row → show detail
        agentListEl.querySelectorAll('.agent-row').forEach(function(row) {
            row.addEventListener('click', function(e) {
                // Don't trigger detail if clicking rename icon
                if (e.target.classList.contains('rename-icon')) return;
                window.vibe.send('agentClicked', { sessionId: row.dataset.sid });
            });
        });

        // Click rename icon → prompt for custom name
        agentListEl.querySelectorAll('.rename-icon').forEach(function(icon) {
            icon.addEventListener('click', function(e) {
                e.stopPropagation();
                var sid = icon.dataset.sid;
                var current = getAgentName(sid, '');
                var newName = prompt('Enter custom name for this agent:', current);
                if (newName !== null) {
                    setAgentName(sid, newName.trim());
                    renderAgentList();
                }
            });
        });
    }

    function renderStats() {
        var s = state.stats;
        if (!s) return;

        // Today's messages (live count)
        statTokensEl.textContent = formatNumber(s.todayMessages || 0);

        // Today's tokens
        statMessagesEl.textContent = formatNumber(s.todayTokens || 0);

        // Total sessions (all time)
        statSessionsEl.textContent = formatNumber(s.totalSessions || 0);

        // Today's tool calls (live count)
        statToolsEl.textContent = formatNumber(s.todayToolCalls || 0);
    }

    function formatNumber(n) {
        if (n >= 1000000) return (n / 1000000).toFixed(1) + 'M';
        if (n >= 1000) return (n / 1000).toFixed(1) + 'K';
        return String(n);
    }

    function escapeHtml(str) {
        var div = document.createElement('div');
        div.textContent = str;
        return div.innerHTML;
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
    updateGlobalStatus();
    renderCollapsed();
    window.vibe.send('ready');
})();
