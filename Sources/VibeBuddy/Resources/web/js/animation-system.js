/**
 * animation-system.js — Cozy pixel room scene.
 * Left: rest area (couch, TV, bookshelf, window).
 * Right: work area (desk, monitor, chair).
 * Characters walk between areas based on status.
 * Includes ambient cat, coffee steam, clock, day/night window.
 */
var AnimationSystem = (function() {
    'use strict';

    var S = 4; // pixel scale

    // Key positions (in pixel units)
    var FLOOR_Y = 52;
    var WORK_X = 68;
    var REST_X = 16;
    var WALK_SPEED = 0.5;

    // Shirt colors for multiple agents
    var SHIRT_COLORS = [
        '#3c64c8', '#c8443c', '#3cc864', '#c8a03c',
        '#8844cc', '#cc6688', '#44aacc', '#66cc44'
    ];

    function AnimationSystem(renderer) {
        this.renderer = renderer;
        this.agents = {};
        this.agentChars = {}; // agentId -> {x, targetX, state, colorIdx, frame, frameTimer}
        this.theme = 'office-human';
        this.globalTick = 0;
        this._bgCanvas = null;
        this._bgW = 0;
        this._bgH = 0;

        // Ambient
        this.catX = 40;
        this.catDir = 1;
        this.catState = 'walk'; // walk, sit, sleep
        this.catTimer = 0;
        this.catFrame = 0;
    }

    AnimationSystem.prototype.setTheme = function(t) { this.theme = t; };

    AnimationSystem.prototype.updateAgents = function(agentList) {
        var self = this;
        var newIds = agentList.map(function(a) { return a.sessionId; });
        var currentIds = Object.keys(this.agents);

        // Remove gone agents
        currentIds.forEach(function(id) {
            if (newIds.indexOf(id) === -1) {
                delete self.agents[id];
                delete self.agentChars[id];
            }
        });

        // Add/update
        agentList.forEach(function(a, idx) {
            self.agents[a.sessionId] = a;
            if (!self.agentChars[a.sessionId]) {
                self.agentChars[a.sessionId] = {
                    x: REST_X + idx * 6,
                    targetX: REST_X + idx * 6,
                    state: 'idle',
                    colorIdx: idx % SHIRT_COLORS.length,
                    frame: 0,
                    frameTimer: 0
                };
            }
            var ch = self.agentChars[a.sessionId];
            var isWorking = a.status === 'working';
            ch.targetX = isWorking ? (WORK_X + idx * 10) : (REST_X + idx * 6);
        });
    };

    // ── Main render ──

    AnimationSystem.prototype.render = function(ctx, w, h) {
        this.globalTick++;

        if (!this._bgCanvas || this._bgW !== w || this._bgH !== h) {
            this._buildBg(w, h);
            this._bgW = w; this._bgH = h;
        }
        ctx.drawImage(this._bgCanvas, 0, 0);

        // Animated elements
        this._drawWindow(ctx);
        this._drawTVScreen(ctx);
        this._drawMonitorScreen(ctx);
        this._drawCoffeeSteam(ctx);
        this._drawClockHands(ctx);
        this._drawArcadeScreen(ctx);
        this._drawLavaBlobs(ctx);
        this._drawNeonGlow(ctx);
        this._drawDigitalClock(ctx, w);

        // Cat
        this._updateCat();
        this._drawCat(ctx);

        // Characters
        var self = this;
        var ids = Object.keys(this.agentChars);
        ids.forEach(function(id) {
            self._updateChar(self.agentChars[id]);
            self._drawChar(ctx, self.agentChars[id]);
        });

        // If no agents, draw one idle character
        if (ids.length === 0) {
            if (!this._defaultChar) {
                this._defaultChar = { x: REST_X, targetX: REST_X, state: 'idle', colorIdx: 0, frame: 0, frameTimer: 0 };
            }
            this._updateChar(this._defaultChar);
            this._drawChar(ctx, this._defaultChar);
        }
    };

    // ── Background ──

    AnimationSystem.prototype._buildBg = function(w, h) {
        var c = document.createElement('canvas');
        c.width = w; c.height = h;
        var g = c.getContext('2d');
        g.imageSmoothingEnabled = false;
        var s = S;

        // Wall
        g.fillStyle = '#161630';
        g.fillRect(0, 0, w, FLOOR_Y * s);
        // Wall texture
        g.fillStyle = '#1a1a36';
        for (var wx = 0; wx < w; wx += 18*s) {
            g.fillRect(wx, 0, 9*s, FLOOR_Y * s);
        }

        // Baseboard
        g.fillStyle = '#3a2212';
        g.fillRect(0, (FLOOR_Y-1)*s, w, s);

        // Floor
        g.fillStyle = '#221810';
        g.fillRect(0, FLOOR_Y*s, w, h - FLOOR_Y*s);
        g.fillStyle = '#2a1e14';
        for (var fx = 0; fx < w; fx += 14*s) {
            g.fillRect(fx, FLOOR_Y*s, 7*s, h - FLOOR_Y*s);
        }

        // Rug (under rest area)
        g.fillStyle = '#2a1840';
        g.fillRect(4*s, FLOOR_Y*s, 34*s, 3*s);
        g.fillStyle = '#321e4a';
        g.fillRect(5*s, FLOOR_Y*s, 32*s, 2*s);

        // ─── REST AREA (left half) ───

        // Window frame
        g.fillStyle = '#3a3a50';
        g.fillRect(2*s, 4*s, 16*s, 18*s);
        g.fillStyle = '#2a2a40';
        g.fillRect(3*s, 5*s, 14*s, 16*s);
        // Window panes divider
        g.fillStyle = '#3a3a50';
        g.fillRect(9*s, 5*s, s, 16*s);
        g.fillRect(3*s, 12*s, 14*s, s);
        // Curtains
        g.fillStyle = '#4a2838';
        g.fillRect(0, 3*s, 3*s, 20*s);
        g.fillRect(17*s, 3*s, 3*s, 20*s);
        g.fillStyle = '#5a3048';
        g.fillRect(0, 3*s, 2*s, 20*s);
        g.fillRect(18*s, 3*s, 2*s, 20*s);

        // Couch
        g.fillStyle = '#3a2050';
        g.fillRect(8*s, 37*s, 20*s, 2*s);  // back
        g.fillStyle = '#5a3078';
        g.fillRect(7*s, 39*s, 22*s, 5*s);  // seat
        g.fillStyle = '#6a3888';
        g.fillRect(8*s, 39*s, 9*s, 4*s);   // cushion L
        g.fillRect(19*s, 39*s, 9*s, 4*s);  // cushion R
        // Armrests
        g.fillStyle = '#4a2868';
        g.fillRect(6*s, 38*s, 2*s, 6*s);
        g.fillRect(28*s, 38*s, 2*s, 6*s);
        // Legs
        g.fillStyle = '#2a180a';
        g.fillRect(8*s, 44*s, 2*s, 2*s);
        g.fillRect(26*s, 44*s, 2*s, 2*s);
        // Pillows
        g.fillStyle = '#c8a040';
        g.fillRect(9*s, 37*s, 4*s, 3*s);
        g.fillStyle = '#80c060';
        g.fillRect(24*s, 37*s, 3*s, 3*s);

        // Coffee table
        g.fillStyle = '#4a3218';
        g.fillRect(12*s, 46*s, 12*s, s);
        g.fillStyle = '#3a2210';
        g.fillRect(14*s, 47*s, s, 3*s);
        g.fillRect(22*s, 47*s, s, 3*s);

        // TV (wall-mounted above couch area)
        g.fillStyle = '#1a1a2a';
        g.fillRect(32*s, 8*s, 14*s, 10*s);
        g.fillStyle = '#333346';
        g.fillRect(32*s, 8*s, 14*s, s);
        g.fillRect(32*s, 8*s, s, 10*s);
        g.fillRect(45*s, 8*s, s, 10*s);
        g.fillRect(32*s, 17*s, 14*s, s);
        // TV stand
        g.fillStyle = '#333';
        g.fillRect(37*s, 18*s, 4*s, s);
        g.fillRect(38*s, 19*s, 2*s, 2*s);

        // Bookshelf (between areas)
        g.fillStyle = '#4a3218';
        g.fillRect(34*s, 24*s, 12*s, 2*s); // top shelf
        g.fillRect(34*s, 32*s, 12*s, 2*s); // bottom shelf
        g.fillStyle = '#3a2210';
        g.fillRect(34*s, 24*s, s, 22*s);   // left side
        g.fillRect(45*s, 24*s, s, 22*s);   // right side
        // Books top row
        g.fillStyle = '#cc4444'; g.fillRect(35*s, 21*s, 2*s, 3*s);
        g.fillStyle = '#4488cc'; g.fillRect(37*s, 22*s, 2*s, 2*s);
        g.fillStyle = '#44cc44'; g.fillRect(39*s, 21*s, 2*s, 3*s);
        g.fillStyle = '#cccc44'; g.fillRect(41*s, 22*s, 2*s, 2*s);
        g.fillStyle = '#cc44cc'; g.fillRect(43*s, 21*s, 2*s, 3*s);
        // Books bottom row
        g.fillStyle = '#cc8844'; g.fillRect(35*s, 27*s, 3*s, 5*s);
        g.fillStyle = '#8888cc'; g.fillRect(38*s, 28*s, 2*s, 4*s);
        g.fillStyle = '#88cc88'; g.fillRect(40*s, 27*s, 2*s, 5*s);
        g.fillStyle = '#cc88aa'; g.fillRect(42*s, 28*s, 3*s, 4*s);

        // Small plant on coffee table
        g.fillStyle = '#5a4030';
        g.fillRect(15*s, 44*s, 3*s, 2*s);
        g.fillStyle = '#4aaa4a';
        g.fillRect(15*s, 42*s, 3*s, 2*s);
        g.fillRect(14*s, 41*s, 2*s, 2*s);
        g.fillRect(17*s, 40*s, 2*s, 2*s);

        // ─── WORK AREA (right half) ───

        // Desk
        g.fillStyle = '#5a3a20';
        g.fillRect(60*s, 42*s, 28*s, 2*s);
        g.fillStyle = '#4a2a18';
        g.fillRect(61*s, 44*s, 2*s, 7*s);
        g.fillRect(85*s, 44*s, 2*s, 7*s);
        // Drawer
        g.fillStyle = '#3a2010';
        g.fillRect(70*s, 44*s, 12*s, 4*s);
        g.fillStyle = '#6a4a28';
        g.fillRect(74*s, 45*s, 4*s, s);

        // Chair
        g.fillStyle = '#2a2a50';
        g.fillRect(64*s, 36*s, 8*s, 2*s);
        g.fillStyle = '#2a2a48';
        g.fillRect(64*s, 38*s, s, 6*s);
        g.fillRect(64*s, 44*s, 8*s, 2*s);
        g.fillStyle = '#222240';
        g.fillRect(66*s, 46*s, s, 4*s);
        g.fillRect(70*s, 46*s, s, 4*s);
        g.fillRect(65*s, 50*s, 3*s, s);
        g.fillRect(69*s, 50*s, 3*s, s);

        // Monitor
        g.fillStyle = '#333';
        g.fillRect(75*s, 39*s, 4*s, 2*s); // stand base
        g.fillRect(76*s, 37*s, 2*s, 2*s); // stand neck
        g.fillStyle = '#222';
        g.fillRect(70*s, 25*s, 14*s, 12*s); // frame
        g.fillStyle = '#444';
        g.fillRect(70*s, 25*s, 14*s, s);
        g.fillRect(70*s, 25*s, s, 12*s);
        g.fillRect(83*s, 25*s, s, 12*s);
        g.fillRect(70*s, 36*s, 14*s, s);

        // Keyboard
        g.fillStyle = '#444';
        g.fillRect(72*s, 43*s, 8*s, s);
        g.fillStyle = '#555';
        for (var ki = 0; ki < 4; ki++) {
            g.fillRect((72 + ki*2)*s, 43*s, s, s);
        }

        // Mouse
        g.fillStyle = '#555';
        g.fillRect(81*s, 43*s, 2*s, s);

        // Coffee mug
        g.fillStyle = '#ddd';
        g.fillRect(62*s, 40*s, 3*s, 2*s);
        g.fillStyle = '#cc4444';
        g.fillRect(62*s, 39*s, 3*s, s);
        // Handle
        g.fillStyle = '#ccc';
        g.fillRect(65*s, 40*s, s, s);

        // Desk lamp
        g.fillStyle = '#555';
        g.fillRect(85*s, 34*s, s, 8*s);
        g.fillStyle = '#4ade80';
        g.fillRect(83*s, 32*s, 5*s, 2*s);
        g.fillRect(84*s, 34*s, 3*s, s);

        // Wall clock
        g.fillStyle = '#444';
        g.fillRect(54*s, 6*s, 6*s, 6*s);
        g.fillStyle = '#eee';
        g.fillRect(55*s, 7*s, 4*s, 4*s);

        // Wall poster (right side)
        g.fillStyle = '#333';
        g.fillRect(78*s, 6*s, 10*s, 8*s);
        g.fillStyle = '#2a4a6a';
        g.fillRect(79*s, 7*s, 8*s, 6*s);
        g.fillStyle = '#4ade80';
        g.fillRect(81*s, 9*s, 4*s, 2*s);
        g.fillStyle = '#fff';
        g.fillRect(80*s, 11*s, 6*s, s);

        // Potted plant (between work and arcade)
        g.fillStyle = '#5a4020';
        g.fillRect(90*s, 46*s, 4*s, 4*s);
        g.fillStyle = '#3a8a3a';
        g.fillRect(89*s, 42*s, 6*s, 4*s);
        g.fillRect(88*s, 40*s, 3*s, 3*s);
        g.fillRect(93*s, 39*s, 3*s, 4*s);
        g.fillStyle = '#2a7a2a';
        g.fillRect(91*s, 38*s, 2*s, 3*s);

        // ─── FUN ZONE (far right) ───

        // Neon "HACK" sign on wall
        g.fillStyle = '#1a0a2a';
        g.fillRect(98*s, 4*s, 22*s, 10*s);
        g.fillStyle = '#2a1a3a';
        g.fillRect(99*s, 5*s, 20*s, 8*s);
        // H
        g.fillStyle = '#ff44aa';
        g.fillRect(100*s, 6*s, s, 5*s);
        g.fillRect(103*s, 6*s, s, 5*s);
        g.fillRect(101*s, 8*s, 2*s, s);
        // A
        g.fillRect(105*s, 7*s, 3*s, s);
        g.fillRect(105*s, 6*s, s, 5*s);
        g.fillRect(107*s, 6*s, s, 5*s);
        g.fillRect(105*s, 9*s, 3*s, s);
        // C
        g.fillRect(109*s, 6*s, 3*s, s);
        g.fillRect(109*s, 6*s, s, 5*s);
        g.fillRect(109*s, 10*s, 3*s, s);
        // K
        g.fillRect(113*s, 6*s, s, 5*s);
        g.fillRect(114*s, 8*s, s, s);
        g.fillRect(115*s, 6*s, s, 2*s);
        g.fillRect(115*s, 9*s, s, 2*s);

        // Arcade cabinet
        g.fillStyle = '#2a1040';
        g.fillRect(98*s, 22*s, 10*s, 28*s);  // body
        g.fillStyle = '#3a1858';
        g.fillRect(99*s, 22*s, 8*s, 3*s);    // marquee area
        g.fillStyle = '#1a0a20';
        g.fillRect(99*s, 26*s, 8*s, 10*s);   // screen recess
        // Controls panel
        g.fillStyle = '#4a2068';
        g.fillRect(99*s, 37*s, 8*s, 4*s);
        // Joystick
        g.fillStyle = '#aaa';
        g.fillRect(101*s, 38*s, s, 2*s);
        g.fillStyle = '#cc0';
        g.fillRect(100*s, 37*s, 3*s, s);
        // Buttons
        g.fillStyle = '#ff4444';
        g.fillRect(104*s, 38*s, 2*s, s);
        g.fillStyle = '#4488ff';
        g.fillRect(104*s, 40*s, 2*s, s);
        // Cabinet side trim
        g.fillStyle = '#00cccc';
        g.fillRect(98*s, 22*s, s, 28*s);
        g.fillRect(107*s, 22*s, s, 28*s);
        // Cabinet legs
        g.fillStyle = '#1a0a20';
        g.fillRect(99*s, 50*s, 2*s, s);
        g.fillRect(105*s, 50*s, 2*s, s);

        // Lava lamp side table
        g.fillStyle = '#4a3218';
        g.fillRect(110*s, 44*s, 8*s, s);     // table top
        g.fillStyle = '#3a2210';
        g.fillRect(111*s, 45*s, s, 6*s);
        g.fillRect(116*s, 45*s, s, 6*s);
        // Lava lamp base
        g.fillStyle = '#555';
        g.fillRect(112*s, 41*s, 4*s, 3*s);
        // Lamp glass (static part)
        g.fillStyle = '#1a3a6a';
        g.fillRect(113*s, 30*s, 2*s, 11*s);
        g.fillStyle = '#555';
        g.fillRect(112*s, 29*s, 4*s, 2*s);   // top cap

        // Mini fridge
        g.fillStyle = '#666';
        g.fillRect(120*s, 38*s, 8*s, 13*s);
        g.fillStyle = '#777';
        g.fillRect(121*s, 39*s, 6*s, 5*s);   // upper door
        g.fillRect(121*s, 45*s, 6*s, 5*s);   // lower door
        // Handle
        g.fillStyle = '#999';
        g.fillRect(126*s, 41*s, s, 2*s);
        g.fillRect(126*s, 47*s, s, 2*s);
        // Logo sticker
        g.fillStyle = '#4ade80';
        g.fillRect(123*s, 40*s, 2*s, s);
        // Magnets/stickers
        g.fillStyle = '#ff6644';
        g.fillRect(122*s, 46*s, 2*s, 2*s);
        g.fillStyle = '#44aaff';
        g.fillRect(124*s, 47*s, s, s);

        // Right wall edge (doorway hint)
        g.fillStyle = '#1a1a2e';
        g.fillRect(130*s, 0, 2*s, FLOOR_Y * s);
        g.fillStyle = '#3a2212';
        g.fillRect(130*s, (FLOOR_Y-1)*s, 2*s, s);

        this._bgCanvas = c;
    };

    // ── Window (day/night) ──

    AnimationSystem.prototype._drawWindow = function(ctx) {
        var s = S;
        var hour = new Date().getHours();
        var sky, stars = false;
        if (hour >= 6 && hour < 8) { sky = '#4a6a9a'; }       // dawn
        else if (hour >= 8 && hour < 17) { sky = '#5a8aca'; }  // day
        else if (hour >= 17 && hour < 19) { sky = '#8a5a4a'; } // sunset
        else { sky = '#0a0a2a'; stars = true; }                 // night

        // Sky in window panes
        ctx.fillStyle = sky;
        ctx.fillRect(3*s, 5*s, 6*s, 7*s);
        ctx.fillRect(10*s, 5*s, 7*s, 7*s);
        ctx.fillRect(3*s, 13*s, 6*s, 8*s);
        ctx.fillRect(10*s, 13*s, 7*s, 8*s);

        if (stars) {
            ctx.fillStyle = '#fff';
            var t = this.globalTick;
            if ((t >> 5) % 2 === 0) ctx.fillRect(5*s, 7*s, s, s);
            if ((t >> 4) % 3 !== 0) ctx.fillRect(12*s, 6*s, s, s);
            if ((t >> 6) % 2 === 0) ctx.fillRect(14*s, 9*s, s, s);
            // Moon
            ctx.fillStyle = '#eeeebb';
            ctx.fillRect(4*s, 6*s, 2*s, 2*s);
        } else if (hour >= 8 && hour < 17) {
            // Sun
            ctx.fillStyle = '#ffe040';
            ctx.fillRect(13*s, 6*s, 3*s, 3*s);
            // Clouds
            ctx.fillStyle = 'rgba(255,255,255,0.4)';
            ctx.fillRect(4*s, 8*s, 4*s, 2*s);
            ctx.fillRect(11*s, 14*s, 3*s, s);
        }

        // Ground in lower panes
        ctx.fillStyle = hour >= 19 || hour < 6 ? '#0a1a0a' : '#3a6a3a';
        ctx.fillRect(3*s, 18*s, 6*s, 3*s);
        ctx.fillRect(10*s, 18*s, 7*s, 3*s);
    };

    // ── TV ──

    AnimationSystem.prototype._drawTVScreen = function(ctx) {
        var s = S;
        var f = (this.globalTick >> 4) % 4;
        var colors = ['#2a5a8a', '#3a7a5a', '#8a5a3a', '#5a3a8a'];
        ctx.fillStyle = colors[f];
        ctx.fillRect(33*s, 9*s, 12*s, 8*s);
        // Scanlines
        ctx.fillStyle = 'rgba(0,0,0,0.12)';
        for (var sy = 9; sy < 17; sy += 2) ctx.fillRect(33*s, sy*s, 12*s, 1);
        // Content
        ctx.fillStyle = 'rgba(255,255,255,0.3)';
        if (f === 0) { ctx.fillRect(35*s, 11*s, 6*s, 2*s); ctx.fillRect(36*s, 14*s, 4*s, s); }
        else if (f === 1) { ctx.fillRect(34*s, 10*s, 3*s, 5*s); ctx.fillRect(39*s, 12*s, 4*s, 3*s); }
        else if (f === 2) { ctx.fillRect(35*s, 13*s, 8*s, 2*s); ctx.fillRect(37*s, 10*s, 4*s, 3*s); }
        else { ctx.fillRect(34*s, 11*s, 5*s, 3*s); ctx.fillRect(40*s, 10*s, 3*s, 4*s); }
    };

    // ── Monitor ──

    AnimationSystem.prototype._drawMonitorScreen = function(ctx) {
        var s = S;
        var anyWorking = false;
        var ids = Object.keys(this.agentChars);
        for (var i = 0; i < ids.length; i++) {
            if (this.agentChars[ids[i]].state === 'working') { anyWorking = true; break; }
        }

        if (anyWorking) {
            ctx.fillStyle = '#0a2a1a';
            ctx.fillRect(71*s, 26*s, 12*s, 10*s);
            var cl = ['#4ade80', '#60a5fa', '#c084fc', '#fbbf24', '#f472b6'];
            var f = (this.globalTick >> 3) % 4;
            for (var line = 0; line < 5; line++) {
                var lw = 2 + ((f + line * 3) % 8);
                ctx.fillStyle = cl[line % cl.length];
                ctx.fillRect(72*s, (27 + line*2)*s, lw*s, s);
            }
            if (f % 2 === 0) {
                ctx.fillStyle = '#fff';
                ctx.fillRect((72 + 2 + f)*s, 35*s, s, s);
            }
        } else {
            ctx.fillStyle = '#08081a';
            ctx.fillRect(71*s, 26*s, 12*s, 10*s);
            ctx.fillStyle = '#1a1a3a';
            ctx.fillRect(75*s, 29*s, 4*s, 4*s);
        }
    };

    // ── Coffee steam ──

    AnimationSystem.prototype._drawCoffeeSteam = function(ctx) {
        var s = S;
        var f = (this.globalTick >> 3) % 4;
        ctx.fillStyle = 'rgba(200,200,200,0.3)';
        if (f === 0) { ctx.fillRect(63*s, 37*s, s, s); ctx.fillRect(64*s, 36*s, s, s); }
        else if (f === 1) { ctx.fillRect(62*s, 36*s, s, s); ctx.fillRect(64*s, 37*s, s, s); }
        else if (f === 2) { ctx.fillRect(63*s, 36*s, s, s); ctx.fillRect(63*s, 34*s, s, s); }
        else { ctx.fillRect(64*s, 37*s, s, s); ctx.fillRect(62*s, 35*s, s, s); }
    };

    // ── Clock hands ──

    AnimationSystem.prototype._drawClockHands = function(ctx) {
        var s = S;
        var now = new Date();
        var h = now.getHours() % 12, m = now.getMinutes();
        ctx.fillStyle = '#222';
        // Hour hand (short)
        if (h < 3 || h >= 9) ctx.fillRect(57*s, 8*s, s, 2*s);
        else ctx.fillRect(57*s, 9*s, s, 2*s);
        // Minute hand (long)
        if (m < 30) ctx.fillRect(57*s, 8*s, 2*s, s);
        else ctx.fillRect(56*s, 9*s, 2*s, s);
    };

    // ── Digital clock (right side) ──

    // 3x5 pixel digit patterns
    var DIGITS = [
        [0x1F,0x11,0x11,0x11,0x1F], // 0
        [0x04,0x0C,0x04,0x04,0x0E], // 1
        [0x1F,0x01,0x1F,0x10,0x1F], // 2
        [0x1F,0x01,0x1F,0x01,0x1F], // 3
        [0x11,0x11,0x1F,0x01,0x01], // 4
        [0x1F,0x10,0x1F,0x01,0x1F], // 5
        [0x1F,0x10,0x1F,0x11,0x1F], // 6
        [0x1F,0x01,0x02,0x04,0x04], // 7
        [0x1F,0x11,0x1F,0x11,0x1F], // 8
        [0x1F,0x11,0x1F,0x01,0x1F]  // 9
    ];

    AnimationSystem.prototype._drawDigitalClock = function(ctx, canvasW) {
        var s = S;
        var now = new Date();
        var h = now.getHours();
        var m = now.getMinutes();
        var timeStr = (h < 10 ? '0' : '') + h + (h < 10 ? '' : '') +
                      (m < 10 ? '0' : '') + m;
        var h1 = Math.floor(h / 10), h2 = h % 10;
        var m1 = Math.floor(m / 10), m2 = m % 10;

        // Position: right of room boundary, centered in remaining space
        var roomEnd = 132 * s;
        var rightSpace = canvasW - roomEnd;
        if (rightSpace < 40 * s) return; // not enough space

        var cx = roomEnd + Math.floor(rightSpace / 2);
        var startX = cx - 14 * s; // center the clock (28px total width for HH:MM)
        var startY = 10 * s;

        // Background panel
        ctx.fillStyle = 'rgba(10,10,30,0.7)';
        ctx.fillRect(startX - 3*s, startY - 3*s, 32*s, 12*s);
        ctx.fillStyle = 'rgba(74,222,128,0.08)';
        ctx.fillRect(startX - 2*s, startY - 2*s, 30*s, 10*s);

        // Draw digits
        var digits = [h1, h2, -1, m1, m2]; // -1 = colon
        var dx = startX;
        var self = this;
        var color = '#4ade80';

        digits.forEach(function(d) {
            if (d === -1) {
                // Colon (blink)
                if ((self.globalTick >> 5) % 2 === 0) {
                    ctx.fillStyle = color;
                    ctx.fillRect(dx + s, startY + s, s, s);
                    ctx.fillRect(dx + s, startY + 3*s, s, s);
                }
                dx += 3 * s;
            } else {
                var pat = DIGITS[d];
                ctx.fillStyle = color;
                for (var row = 0; row < 5; row++) {
                    for (var col = 0; col < 5; col++) {
                        if (pat[row] & (0x10 >> col)) {
                            ctx.fillRect(dx + col*s, startY + row*s, s, s);
                        }
                    }
                }
                dx += 6 * s;
            }
        });

        // Date below
        var months = ['JAN','FEB','MAR','APR','MAY','JUN','JUL','AUG','SEP','OCT','NOV','DEC'];
        var dateStr = months[now.getMonth()] + ' ' + now.getDate();
        ctx.fillStyle = 'rgba(150,150,200,0.5)';
        ctx.font = (2*s) + 'px monospace';
        ctx.textAlign = 'center';
        ctx.fillText(dateStr, cx, startY + 9*s);
        ctx.textAlign = 'start'; // reset
    };

    // ── Arcade screen ──

    AnimationSystem.prototype._drawArcadeScreen = function(ctx) {
        var s = S;
        var f = (this.globalTick >> 4) % 5;
        // Screen background
        ctx.fillStyle = '#0a0a1a';
        ctx.fillRect(100*s, 27*s, 6*s, 8*s);

        if (f === 0) {
            // Space invaders
            ctx.fillStyle = '#4ade80';
            ctx.fillRect(101*s, 28*s, 2*s, s);
            ctx.fillRect(103*s, 29*s, 2*s, s);
            ctx.fillRect(101*s, 31*s, s, s);
            // Ship
            ctx.fillStyle = '#60a5fa';
            ctx.fillRect(102*s, 33*s, 2*s, s);
            // Bullet
            ctx.fillStyle = '#fff';
            var by = 33 - ((this.globalTick >> 2) % 5);
            if (by >= 28) ctx.fillRect(103*s, by*s, s, s);
        } else if (f === 1) {
            // Pong
            ctx.fillStyle = '#fff';
            ctx.fillRect(100*s, 29*s, s, 2*s);
            ctx.fillRect(105*s, 30*s, s, 2*s);
            var bx = 101 + ((this.globalTick >> 2) % 4);
            ctx.fillRect(bx*s, 30*s, s, s);
            // Score
            ctx.fillStyle = '#fbbf24';
            ctx.fillRect(102*s, 27*s, s, s);
            ctx.fillRect(104*s, 27*s, s, s);
        } else if (f === 2) {
            // Snake
            ctx.fillStyle = '#4ade80';
            var sx = 101 + ((this.globalTick >> 3) % 3);
            ctx.fillRect(sx*s, 30*s, s, s);
            ctx.fillRect((sx-1)*s, 30*s, s, s);
            ctx.fillRect((sx-2)*s, 30*s, s, s);
            // Apple
            ctx.fillStyle = '#ff4444';
            ctx.fillRect(104*s, 30*s, s, s);
        } else if (f === 3) {
            // Tetris-like
            ctx.fillStyle = '#c084fc';
            ctx.fillRect(101*s, 33*s, 2*s, s);
            ctx.fillRect(103*s, 33*s, 2*s, s);
            ctx.fillStyle = '#60a5fa';
            ctx.fillRect(100*s, 34*s, 3*s, s);
            ctx.fillStyle = '#fbbf24';
            var ty = 28 + ((this.globalTick >> 3) % 5);
            ctx.fillRect(102*s, ty*s, 2*s, s);
            ctx.fillRect(101*s, (ty+1)*s, 2*s, s);
        } else {
            // HIGH SCORE
            ctx.fillStyle = '#fbbf24';
            ctx.fillRect(100*s, 28*s, 6*s, s); // "HI"
            ctx.fillStyle = '#ff44aa';
            ctx.fillRect(101*s, 30*s, 4*s, s); // score
            ctx.fillRect(100*s, 32*s, 6*s, s);
            ctx.fillStyle = '#4ade80';
            ctx.fillRect(101*s, 34*s, 4*s, s); // rank
        }

        // CRT scanlines
        ctx.fillStyle = 'rgba(0,0,0,0.15)';
        for (var sl = 27; sl < 35; sl += 2) ctx.fillRect(100*s, sl*s, 6*s, 1);

        // Marquee glow
        var mc = (this.globalTick >> 3) % 2;
        ctx.fillStyle = mc ? '#00ffff' : '#ff44aa';
        ctx.fillRect(100*s, 23*s, 6*s, s);
    };

    // ── Lava lamp blobs ──

    AnimationSystem.prototype._drawLavaBlobs = function(ctx) {
        var s = S;
        var t = this.globalTick;
        // Blob 1 — slow rise/fall cycle
        var b1y = 34 + Math.round(Math.sin(t * 0.02) * 3);
        ctx.fillStyle = '#ff6644';
        ctx.fillRect(113*s, b1y*s, 2*s, 2*s);
        ctx.fillStyle = '#ff8866';
        ctx.fillRect(113*s, (b1y+1)*s, 2*s, s);

        // Blob 2 — offset phase
        var b2y = 37 + Math.round(Math.sin(t * 0.025 + 2) * 2);
        ctx.fillStyle = '#cc44aa';
        ctx.fillRect(113*s, b2y*s, 2*s, s);

        // Blob 3 — small, fast
        var b3y = 32 + Math.round(Math.sin(t * 0.035 + 4) * 3);
        ctx.fillStyle = '#ffaa44';
        ctx.fillRect(114*s, b3y*s, s, s);

        // Lamp glow on wall (subtle)
        ctx.fillStyle = 'rgba(255,100,70,0.06)';
        ctx.fillRect(110*s, 28*s, 8*s, 16*s);
    };

    // ── Neon sign glow ──

    AnimationSystem.prototype._drawNeonGlow = function(ctx) {
        var s = S;
        var t = this.globalTick;
        var flicker = ((t >> 2) % 7 === 0) ? 0 : 1; // occasional flicker off
        if (!flicker) return;

        // Pink glow around letters
        ctx.fillStyle = 'rgba(255,68,170,0.12)';
        ctx.fillRect(99*s, 5*s, 18*s, 7*s);

        // Occasional sparkle
        if ((t >> 4) % 3 === 0) {
            ctx.fillStyle = '#fff';
            ctx.fillRect(117*s, 6*s, s, s);
        }
    };

    // ── Cat ──

    AnimationSystem.prototype._updateCat = function() {
        this.catTimer++;
        if (this.catState === 'walk') {
            this.catX += this.catDir * 0.15;
            this.catFrame = (this.globalTick >> 3) % 2;
            if (this.catX > 120) { this.catDir = -1; }
            if (this.catX < 5) { this.catDir = 1; }
            if (this.catTimer > 200) {
                this.catState = 'sit';
                this.catTimer = 0;
            }
        } else if (this.catState === 'sit') {
            this.catFrame = 0;
            if (this.catTimer > 150) {
                this.catState = (Math.random() < 0.5) ? 'sleep' : 'walk';
                this.catTimer = 0;
            }
        } else { // sleep
            this.catFrame = (this.globalTick >> 5) % 2;
            if (this.catTimer > 200) {
                this.catState = 'walk';
                this.catTimer = 0;
                this.catDir = Math.random() < 0.5 ? 1 : -1;
            }
        }
    };

    AnimationSystem.prototype._drawCat = function(ctx) {
        var s = S;
        var cx = Math.round(this.catX) * s;
        var cy = (FLOOR_Y - 3) * s;

        if (this.catState === 'sleep') {
            // Curled up ball
            ctx.fillStyle = '#ff9030';
            ctx.fillRect(cx, cy + s, 4*s, 2*s);
            ctx.fillStyle = '#ffb060';
            ctx.fillRect(cx + s, cy, 2*s, s);
            // Zzz
            if (this.catFrame === 0) {
                ctx.fillStyle = 'rgba(150,150,200,0.5)';
                ctx.fillRect(cx + 5*s, cy - s, s, s);
            }
            return;
        }

        // Body
        ctx.fillStyle = '#ff9030';
        ctx.fillRect(cx, cy, 4*s, 2*s);
        // Head
        ctx.fillRect(this.catDir > 0 ? cx + 3*s : cx - s, cy - s, 2*s, 2*s);
        // Ears
        var hx = this.catDir > 0 ? cx + 3*s : cx - s;
        ctx.fillStyle = '#dd7020';
        ctx.fillRect(hx, cy - 2*s, s, s);
        ctx.fillRect(hx + s, cy - 2*s, s, s);
        // Eye
        ctx.fillStyle = '#40c080';
        ctx.fillRect(this.catDir > 0 ? cx + 4*s : cx - s, cy - s, s, s);
        // Tail
        ctx.fillStyle = '#ff9030';
        var tx = this.catDir > 0 ? cx - s : cx + 4*s;
        var tailUp = this.catFrame === 0 ? -s : 0;
        ctx.fillRect(tx, cy + tailUp, s, s + (tailUp === 0 ? s : 0));
        // Legs
        ctx.fillStyle = '#dd7020';
        if (this.catState === 'walk') {
            if (this.catFrame === 0) {
                ctx.fillRect(cx, cy + 2*s, s, s);
                ctx.fillRect(cx + 3*s, cy + 2*s, s, s);
            } else {
                ctx.fillRect(cx + s, cy + 2*s, s, s);
                ctx.fillRect(cx + 2*s, cy + 2*s, s, s);
            }
        } else {
            ctx.fillRect(cx, cy + 2*s, s, s);
            ctx.fillRect(cx + 3*s, cy + 2*s, s, s);
        }
    };

    // ── Character update ──

    AnimationSystem.prototype._updateChar = function(ch) {
        if (Math.abs(ch.x - ch.targetX) > 0.5) {
            ch.x += (ch.targetX > ch.x ? 1 : -1) * WALK_SPEED;
            ch.state = 'walking';
        } else {
            ch.x = ch.targetX;
            ch.state = (ch.targetX >= WORK_X - 5) ? 'working' : 'idle';
        }
        ch.frameTimer++;
        var spd = ch.state === 'working' ? 8 : (ch.state === 'walking' ? 6 : 18);
        if (ch.frameTimer >= spd) {
            ch.frameTimer = 0;
            ch.frame = (ch.frame + 1) % 4;
        }
    };

    // ── Character draw ──

    AnimationSystem.prototype._drawChar = function(ctx, ch) {
        var s = S;
        var x = Math.round(ch.x) * s;
        var y = (FLOOR_Y - 2) * s;
        var f = ch.frame;
        var shirt = SHIRT_COLORS[ch.colorIdx];
        var hair = '#503220', skin = '#ffce9e', pants = '#3c3c64', shoe = '#322820', eye = '#282840';

        if (ch.state === 'walking') {
            var bob = f % 2 === 0 ? 0 : -s;
            var right = ch.targetX > ch.x;
            // Hair
            ctx.fillStyle = hair;
            ctx.fillRect(x+2*s, y-9*s+bob, 5*s, 2*s);
            // Head
            ctx.fillStyle = skin;
            ctx.fillRect(x+2*s, y-7*s+bob, 5*s, 3*s);
            // Eye
            ctx.fillStyle = eye;
            ctx.fillRect(right ? x+5*s : x+3*s, y-6*s+bob, s, s);
            // Body
            ctx.fillStyle = shirt;
            ctx.fillRect(x+2*s, y-4*s+bob, 5*s, 3*s);
            // Arms
            ctx.fillStyle = skin;
            var a1 = f % 4 < 2 ? -3 : -4;
            var a2 = f % 4 < 2 ? -4 : -3;
            ctx.fillRect(x+s, (y+a1*s)+bob, s, 2*s);
            ctx.fillRect(x+7*s, (y+a2*s)+bob, s, 2*s);
            // Legs
            ctx.fillStyle = pants;
            ctx.fillRect(x+2*s, y-s, 2*s, 2*s);
            ctx.fillRect(x+5*s, y-s, 2*s, 2*s);
            if (f%2===0) { ctx.fillRect(x+2*s, y+s, 2*s, s); } else { ctx.fillRect(x+5*s, y+s, 2*s, s); }
            ctx.fillStyle = shoe;
            ctx.fillRect(x+2*s, y+2*s, 2*s, s);
            ctx.fillRect(x+5*s, y+2*s, 2*s, s);
        } else if (ch.state === 'working') {
            var bob2 = f%2===0?0:-1;
            // Hair
            ctx.fillStyle = hair;
            ctx.fillRect(x+2*s, y-9*s+bob2, 5*s, 2*s);
            // Head
            ctx.fillStyle = skin;
            ctx.fillRect(x+2*s, y-7*s+bob2, 5*s, 3*s);
            // Eye
            ctx.fillStyle = eye;
            ctx.fillRect(x+3*s, y-6*s+bob2, s, s);
            // Body
            ctx.fillStyle = shirt;
            ctx.fillRect(x+2*s, y-4*s, 5*s, 3*s);
            // Typing arms
            ctx.fillStyle = skin;
            if (f%2===0) {
                ctx.fillRect(x, y-2*s, 2*s, s);
                ctx.fillRect(x+s, y-3*s, s, s);
            } else {
                ctx.fillRect(x-s, y-2*s, 2*s, s);
                ctx.fillRect(x+2*s, y-3*s, s, s);
            }
            // Seated legs
            ctx.fillStyle = pants;
            ctx.fillRect(x+2*s, y-s, 5*s, s);
            ctx.fillStyle = shoe;
            ctx.fillRect(x+2*s, y, 2*s, s);
            ctx.fillRect(x+5*s, y, 2*s, s);
        } else {
            // Resting on couch
            // Hair
            ctx.fillStyle = hair;
            ctx.fillRect(x+2*s, y-9*s, 5*s, 2*s);
            // Head
            ctx.fillStyle = skin;
            ctx.fillRect(x+2*s, y-7*s, 5*s, 3*s);
            // Eyes
            ctx.fillStyle = eye;
            ctx.fillRect(x+5*s, y-6*s, s, s);
            // Blink
            if (f===2) { ctx.fillStyle = skin; ctx.fillRect(x+5*s, y-6*s, s, s); }
            // Smile
            ctx.fillStyle = '#c05050';
            ctx.fillRect(x+4*s, y-5*s, 2*s, s);
            // Body
            ctx.fillStyle = shirt;
            ctx.fillRect(x+2*s, y-4*s, 5*s, 3*s);
            // Arm with remote
            ctx.fillStyle = skin;
            ctx.fillRect(x+7*s, y-3*s, s, 2*s);
            if (f%2===0) { ctx.fillStyle='#444'; ctx.fillRect(x+8*s, y-4*s, s, s); }
            ctx.fillStyle = skin;
            ctx.fillRect(x+s, y-2*s, 2*s, s);
            // Seated
            ctx.fillStyle = pants;
            ctx.fillRect(x+2*s, y-s, 5*s, s);
            ctx.fillStyle = shoe;
            ctx.fillRect(x+2*s, y, 2*s, s);
            ctx.fillRect(x+5*s, y, 2*s, s);
        }
    };

    return AnimationSystem;
})();
