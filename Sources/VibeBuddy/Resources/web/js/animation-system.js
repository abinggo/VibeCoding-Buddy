/**
 * animation-system.js — Manages agent animation states and sprite lifecycle.
 * Maps agent sessions to animated pixel characters on the canvas.
 */
var AnimationSystem = (function() {
    'use strict';

    /** Sprite sheet configuration per animation state. {theme} is replaced at runtime. */
    var STATE_CONFIG = {
        idle:    { src: 'sprites/{theme}/idle.png',    fps: 2, frameCount: 4 },
        working: { src: 'sprites/{theme}/working.png', fps: 6, frameCount: 4 },
        waiting: { src: 'sprites/{theme}/waiting.png', fps: 3, frameCount: 4 },
        done:    { src: 'sprites/{theme}/done.png',    fps: 4, frameCount: 4 }
    };

    /**
     * @param {SpriteRenderer} renderer
     */
    function AnimationSystem(renderer) {
        this.renderer = renderer;
        this.agents = {};       // agentId -> { state, index, data }
        this.theme = 'office-human';
        this.spriteSize = 16;
        this.spriteScale = 3;
        this.spacing = 12;
    }

    AnimationSystem.prototype.setTheme = function(theme) {
        this.theme = theme;
        var self = this;
        Object.keys(this.agents).forEach(function(id) {
            self._applySprite(id, self.agents[id].state, self.agents[id].index);
        });
    };

    /**
     * Sync the displayed agents with an updated list.
     * @param {Array} agentList - [{sessionId, status, name, cwd, startedAt, lastTool}]
     */
    AnimationSystem.prototype.updateAgents = function(agentList) {
        var currentIds = Object.keys(this.agents);
        var newIds = agentList.map(function(a) { return a.sessionId; });
        var self = this;

        // Remove departed agents
        currentIds.forEach(function(id) {
            if (newIds.indexOf(id) === -1) {
                self.renderer.removeSprite('agent-' + id);
                delete self.agents[id];
            }
        });

        // Add or update agents
        agentList.forEach(function(agent, index) {
            var id = agent.sessionId;
            var state = agent.status || 'working';

            if (!self.agents[id]) {
                self.agents[id] = { state: state, index: index, data: agent };
                self._applySprite(id, state, index);
            } else {
                var changed = self.agents[id].state !== state || self.agents[id].index !== index;
                self.agents[id].state = state;
                self.agents[id].index = index;
                self.agents[id].data = agent;
                if (changed) self._applySprite(id, state, index);
            }
        });
    };

    AnimationSystem.prototype._applySprite = function(agentId, state, index) {
        var config = STATE_CONFIG[state] || STATE_CONFIG.idle;
        var src = config.src.replace('{theme}', this.theme);
        var x = this._calculateX(index);

        this.renderer.addSprite({
            id: 'agent-' + agentId,
            src: src,
            x: x,
            y: 10,
            frameWidth: this.spriteSize,
            frameHeight: this.spriteSize,
            frameCount: config.frameCount,
            fps: config.fps,
            scale: this.spriteScale,
            onClick: function() {
                window.vibe.send('agentClicked', { sessionId: agentId });
            }
        });
    };

    AnimationSystem.prototype._calculateX = function(index) {
        var totalWidth = this.spriteSize * this.spriteScale;
        var startX = 20;
        return startX + index * (totalWidth + this.spacing);
    };

    return AnimationSystem;
})();
