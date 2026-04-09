/**
 * sprite-renderer.js — Canvas-based pixel art sprite sheet renderer
 * Full implementation in Task 7.
 */
var SpriteRenderer = (function() {

    function SpriteRenderer(canvas) {
        this.canvas = canvas;
        this.ctx = canvas.getContext('2d');
        this.ctx.imageSmoothingEnabled = false;
        this.sprites = [];
        this.images = {};
        this.lastTime = 0;
        this.running = false;
    }

    /** Load an image and cache it by src. Returns a Promise. */
    SpriteRenderer.prototype.loadImage = function(src) {
        var self = this;
        if (this.images[src]) return Promise.resolve(this.images[src]);
        return new Promise(function(resolve, reject) {
            var img = new Image();
            img.onload = function() { self.images[src] = img; resolve(img); };
            img.onerror = reject;
            img.src = src;
        });
    };

    /**
     * Add a sprite to the render list.
     * @param {Object} config - { id, src, x, y, frameWidth, frameHeight, frameCount, fps, scale, onClick }
     */
    SpriteRenderer.prototype.addSprite = function(config) {
        var sprite = {
            id: config.id,
            src: config.src,
            x: config.x || 0,
            y: config.y || 0,
            frameWidth: config.frameWidth || 16,
            frameHeight: config.frameHeight || 16,
            frameCount: config.frameCount || 4,
            fps: config.fps || 4,
            scale: config.scale || 3,
            currentFrame: 0,
            elapsed: 0,
            image: null,
            onClick: config.onClick || null
        };
        var self = this;
        this.loadImage(config.src).then(function(img) { sprite.image = img; });
        this.sprites = this.sprites.filter(function(s) { return s.id !== config.id; });
        this.sprites.push(sprite);
        return sprite;
    };

    SpriteRenderer.prototype.removeSprite = function(id) {
        this.sprites = this.sprites.filter(function(s) { return s.id !== id; });
    };

    SpriteRenderer.prototype.clear = function() {
        this.sprites = [];
    };

    SpriteRenderer.prototype.start = function() {
        if (this.running) return;
        this.running = true;
        this.lastTime = performance.now();
        this._loop();
    };

    SpriteRenderer.prototype.stop = function() {
        this.running = false;
    };

    SpriteRenderer.prototype._loop = function() {
        if (!this.running) return;
        var now = performance.now();
        var dt = (now - this.lastTime) / 1000;
        this.lastTime = now;

        this.ctx.clearRect(0, 0, this.canvas.width, this.canvas.height);

        for (var i = 0; i < this.sprites.length; i++) {
            var s = this.sprites[i];
            if (!s.image) continue;

            s.elapsed += dt;
            var frameDuration = 1 / s.fps;
            if (s.elapsed >= frameDuration) {
                s.currentFrame = (s.currentFrame + 1) % s.frameCount;
                s.elapsed -= frameDuration;
            }

            this.ctx.drawImage(
                s.image,
                s.currentFrame * s.frameWidth, 0, s.frameWidth, s.frameHeight,
                s.x, s.y, s.frameWidth * s.scale, s.frameHeight * s.scale
            );
        }

        var self = this;
        requestAnimationFrame(function() { self._loop(); });
    };

    /** Hit-test a canvas click and invoke the sprite's onClick handler. */
    SpriteRenderer.prototype.handleClick = function(canvasX, canvasY) {
        for (var i = this.sprites.length - 1; i >= 0; i--) {
            var s = this.sprites[i];
            var dw = s.frameWidth * s.scale;
            var dh = s.frameHeight * s.scale;
            if (canvasX >= s.x && canvasX <= s.x + dw &&
                canvasY >= s.y && canvasY <= s.y + dh) {
                if (s.onClick) s.onClick(s);
                return s;
            }
        }
        return null;
    };

    return SpriteRenderer;
})();
