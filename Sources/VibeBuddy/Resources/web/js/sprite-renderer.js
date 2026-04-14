/**
 * sprite-renderer.js — Canvas render loop.
 * Delegates actual drawing to AnimationSystem.render().
 */
var SpriteRenderer = (function() {

    function SpriteRenderer(canvas) {
        this.canvas = canvas;
        this.ctx = canvas.getContext('2d');
        this.ctx.imageSmoothingEnabled = false;
        this.running = false;
        this.lastTime = 0;
        this.animSystem = null; // set by notch-app.js
    }

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

        this.ctx.clearRect(0, 0, this.canvas.width, this.canvas.height);

        if (this.animSystem) {
            this.animSystem.render(this.ctx, this.canvas.width, this.canvas.height);
        }

        var self = this;
        requestAnimationFrame(function() { self._loop(); });
    };

    return SpriteRenderer;
})();
