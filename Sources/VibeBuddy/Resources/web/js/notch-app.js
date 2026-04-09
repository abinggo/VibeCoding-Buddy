/**
 * notch-app.js — Notch island main logic
 * Manages collapsed/expanded views and agent status display.
 */
(function() {
    'use strict';

    // ── State ──────────────────────────────────────────────
    var state = {
        agents: [],
        expanded: false
    };

    // ── DOM refs ───────────────────────────────────────────
    var countEl = document.getElementById('agent-count');
    var textEl = document.getElementById('status-text');

    // ── Event Handlers ─────────────────────────────────────

    window.vibe.on('agentsUpdate', function(data) {
        state.agents = data.agents || [];
        renderCollapsed();
        // SpriteRenderer integration will be added in Task 7
        if (window.animSystem) {
            window.animSystem.updateAgents(state.agents);
        }
    });

    window.vibe.on('hookEvent', function(data) {
        // Update agent status based on hook events
        if (data.type === 'PostToolUse' || data.type === 'Stop') {
            state.agents.forEach(function(a) {
                if (a.sessionId === data.sessionId) {
                    a.status = data.type === 'Stop' ? 'idle' : 'working';
                    a.lastTool = (data.payload && data.payload.tool_name) || '';
                }
            });
            renderCollapsed();
            if (window.animSystem) {
                window.animSystem.updateAgents(state.agents);
            }
        }
    });

    window.vibe.on('expand', function() {
        state.expanded = true;
        document.body.classList.add('expanded');
        if (window.spriteRenderer) window.spriteRenderer.start();
    });

    window.vibe.on('collapse', function() {
        state.expanded = false;
        document.body.classList.remove('expanded');
        if (window.spriteRenderer) window.spriteRenderer.stop();
    });

    // ── Render ─────────────────────────────────────────────

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

    // ── Init ───────────────────────────────────────────────
    renderCollapsed();
    window.vibe.send('ready');
})();
