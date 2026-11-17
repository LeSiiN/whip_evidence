// Forensic minigames (WHIP skill check games, see shared/games.lua and client/games.lua).
// Each game draws on one canvas; the page tells Lua the result with the token whip_core gave.
(() => {
    const RES = typeof GetParentResourceName === 'function' ? GetParentResourceName() : 'whip_evidence';
    const W = 600, H = 380;
    const LEVEL = { easy: 1, medium: 1.35, hard: 1.7 };
    const SECONDS = { easy: 24, medium: 19, hard: 15 };
    const TITLES = {
        dust: ['Dust for prints', 'Hold and brush slowly over the surface. Too fast smudges the print.'],
        tweezers: ['Tweezers', 'Grab the casing at its rim (the dark end) and carry it into the bag. Do not knock it.'],
        swab: ['Swab', 'Hold and rub in circles over the stain until the swab is soaked.'],
        pull: ['Pull it out', 'Hold to pull. Keep the needle in the green zone. Too hard breaks it.'],
        shards: ['Pick up fragments', 'Click every fragment. They glint now and then.'],
        gsrswab: ['GSR swab', 'Hold the swab on each glowing spot: right hand first, then the left.'],
    };

    // ---------------------------------------------------------------- page bits
    const style = document.createElement('style');
    style.textContent = `
    #mg { position: fixed; inset: 0; display: none; align-items: center; justify-content: center;
          background: radial-gradient(ellipse at center, rgba(6,8,12,.35), rgba(6,8,12,.7));
          font-family: var(--ui-font, 'Barlow', sans-serif); color: var(--ui-text, rgba(255,255,255,.93)); }
    #mg.open { display: flex; }
    #mg .panel { width: 640px; padding: 16px 20px 18px; border-radius: 14px;
          background: var(--ui-surface-raised, rgba(12,14,20,.94)); border: 1px solid var(--ui-border, rgba(255,255,255,.08));
          box-shadow: 0 24px 60px rgba(0,0,0,.5); animation: mgIn .22s cubic-bezier(.16,1,.3,1); }
    @keyframes mgIn { from { transform: translateY(14px) scale(.97); opacity: 0; } to { transform: none; opacity: 1; } }
    #mg .top { display: flex; align-items: baseline; gap: 12px; }
    #mg .kicker { font-size: 12px; font-weight: 800; letter-spacing: 3px; color: #fde047; }
    #mg .title { font-size: 22px; font-weight: 800; }
    #mg .strikes { margin-left: auto; display: flex; gap: 5px; }
    #mg .strikes i { width: 12px; height: 12px; border-radius: 50%; background: rgba(255,255,255,.14); }
    #mg .strikes i.on { background: #f87171; box-shadow: 0 0 8px rgba(248,113,113,.7); }
    #mg .hint { font-size: 14px; font-weight: 600; color: rgba(255,255,255,.6); margin: 4px 0 10px; min-height: 18px; }
    #mg canvas { display: block; width: ${W}px; height: ${H}px; border-radius: 10px; cursor: none; background: #1b1f26; }
    #mg .bars { display: grid; grid-template-columns: 1fr 160px; gap: 12px; margin-top: 12px; align-items: center; }
    #mg .bar { height: 10px; border-radius: 6px; background: rgba(255,255,255,.08); overflow: hidden; }
    #mg .bar b { display: block; height: 100%; width: 0; border-radius: 6px; transition: width .08s linear; }
    #mg .prog b { background: linear-gradient(90deg, #22c55e, #4ade80); }
    #mg .time b { background: linear-gradient(90deg, #fbbf24, #f59e0b); }
    #mg .time.low b { background: linear-gradient(90deg, #ef4444, #f87171); }
    #mg .keys { font-size: 12px; font-weight: 600; color: rgba(255,255,255,.4); margin-top: 8px; }
    `;
    document.head.appendChild(style);

    const root = document.createElement('div');
    root.id = 'mg';
    root.innerHTML = `<div class="panel">
        <div class="top"><span class="kicker">FORENSICS</span><span class="title" id="mgTitle"></span><span class="strikes" id="mgStrikes"></span></div>
        <div class="hint" id="mgHint"></div>
        <canvas id="mgCanvas" width="${W * 2}" height="${H * 2}"></canvas>
        <div class="bars"><div class="bar prog"><b id="mgProg"></b></div><div class="bar time" id="mgTimeBar"><b id="mgTime"></b></div></div>
        <div class="keys" id="mgKeys"></div></div>`;
    document.body.appendChild(root);
    const canvas = root.querySelector('#mgCanvas');
    const ctx = canvas.getContext('2d');
    ctx.scale(2, 2);   // sharp on any screen

    const $ = (id) => document.getElementById(id);
    const rand = (a, b) => a + Math.random() * (b - a);
    const clamp = (v, a, b) => Math.max(a, Math.min(b, v));
    const dist = (ax, ay, bx, by) => Math.hypot(ax - bx, ay - by);

    // ---------------------------------------------------------------- shared state
    let G = null;          // running game
    let raf = 0;
    const input = { x: W / 2, y: H / 2, down: false, pressed: false, released: false, px: W / 2, py: H / 2 };

    canvas.addEventListener('mousemove', (e) => {
        const r = canvas.getBoundingClientRect();
        input.x = clamp((e.clientX - r.left) * (W / r.width), 0, W);
        input.y = clamp((e.clientY - r.top) * (H / r.height), 0, H);
    });
    window.addEventListener('mousedown', (e) => { if (G && e.button === 0) { input.down = true; input.pressed = true; } });
    window.addEventListener('mouseup', (e) => { if (G && e.button === 0) { input.down = false; input.released = true; } });
    window.addEventListener('keydown', (e) => { if (G && e.key === 'Escape') finish(false, 'cancelled', true); });

    function strike(text) {
        G.strikes++;
        flash(text, '#f87171');
        drawStrikes();
        if (G.strikes >= G.maxStrikes) finish(false, 'failed');
    }
    function flash(text, color) { G.flash = { text, color: color || '#fde047', until: performance.now() + 900 }; }
    function drawStrikes() {
        $('mgStrikes').innerHTML = G.maxStrikes > 0
            ? Array.from({ length: G.maxStrikes }, (_, i) => `<i class="${i < G.strikes ? 'on' : ''}"></i>`).join('') : '';
    }

    function finish(passed, why, quiet) {
        if (!G || G.done) return;
        G.done = { passed, why, at: performance.now() };
        if (!quiet) flash(passed ? 'Done' : (why === 'timeout' ? 'Out of time' : 'Failed'), passed ? '#4ade80' : '#f87171');
        const token = G.token;
        setTimeout(() => {
            fetch(`https://${RES}/gameDone`, { method: 'POST', body: JSON.stringify({ token, passed, why }) }).catch(() => {});
        }, quiet ? 0 : 650);
    }

    // ---------------------------------------------------------------- drawing helpers
    function roundRect(x, y, w, h, r) {
        ctx.beginPath();
        ctx.moveTo(x + r, y); ctx.arcTo(x + w, y, x + w, y + h, r); ctx.arcTo(x + w, y + h, x, y + h, r);
        ctx.arcTo(x, y + h, x, y, r); ctx.arcTo(x, y, x + w, y, r); ctx.closePath();
    }
    // a surface texture made once per game (speckles)
    function makeSurface(base, speck, n) {
        const c = document.createElement('canvas'); c.width = W; c.height = H;
        const g = c.getContext('2d');
        const grd = g.createLinearGradient(0, 0, W, H);
        grd.addColorStop(0, base[0]); grd.addColorStop(1, base[1]);
        g.fillStyle = grd; g.fillRect(0, 0, W, H);
        for (let i = 0; i < n; i++) {
            g.fillStyle = speck[Math.floor(Math.random() * speck.length)];
            g.globalAlpha = rand(0.05, 0.25);
            g.fillRect(rand(0, W), rand(0, H), rand(1, 3), rand(1, 3));
        }
        g.globalAlpha = 1;
        return c;
    }
    function text(t, x, y, size, color, align) {
        ctx.font = `800 ${size}px Barlow, sans-serif`;
        ctx.fillStyle = color; ctx.textAlign = align || 'center';
        ctx.fillText(t, x, y);
    }

    // tools drawn at the cursor
    const TOOLS = {
        brush(x, y, down) {
            ctx.save(); ctx.translate(x, y); ctx.rotate(-0.6);
            ctx.fillStyle = '#7c5a3a'; roundRect(-4, 14, 8, 46, 3); ctx.fill();
            ctx.fillStyle = '#cbd5e1'; ctx.fillRect(-6, 6, 12, 10);
            ctx.fillStyle = down ? '#e5e7eb' : '#f3f4f6';
            ctx.beginPath(); ctx.ellipse(0, 0, 9, 9, 0, 0, Math.PI * 2); ctx.fill();
            ctx.restore();
        },
        tweezers(x, y, down) {
            const s = down ? 2 : 7;
            ctx.save(); ctx.translate(x, y); ctx.rotate(-0.5);
            ctx.strokeStyle = '#e2e8f0'; ctx.lineWidth = 3; ctx.lineCap = 'round';
            ctx.beginPath(); ctx.moveTo(-s, 0); ctx.lineTo(-5, -60); ctx.moveTo(s, 0); ctx.lineTo(5, -60); ctx.stroke();
            ctx.restore();
        },
        swab(x, y, down, fill) {
            ctx.save(); ctx.translate(x, y); ctx.rotate(-0.7);
            ctx.fillStyle = '#f8fafc'; ctx.fillRect(-2, 6, 4, 60);
            const r = Math.round(248 - 120 * (fill || 0)), gb = Math.round(250 - 230 * (fill || 0));
            ctx.fillStyle = `rgb(${r},${gb},${gb})`;
            ctx.beginPath(); ctx.ellipse(0, 0, 8, 11, 0, 0, Math.PI * 2); ctx.fill();
            ctx.restore();
        },
        dot(x, y) {
            ctx.strokeStyle = '#fff'; ctx.lineWidth = 2;
            ctx.beginPath(); ctx.arc(x, y, 7, 0, Math.PI * 2); ctx.stroke();
        },
    };

    // ---------------------------------------------------------------- the games
    const GAMES = {};

    // 1. Fingerprint: brush it visible, then press the tape on at the right moment
    GAMES.dust = {
        tool: 'brush', strikes: 3,
        start(g, L) {
            g.surface = makeSurface(['#2a2f38', '#1e222a'], ['#94a3b8', '#64748b'], 900);
            g.cx = rand(250, 350); g.cy = rand(170, 210);
            // the print: ridges as wavy ellipses on their own canvas
            const pc = document.createElement('canvas'); pc.width = W; pc.height = H;
            const p = pc.getContext('2d');
            p.strokeStyle = '#e5e7eb'; p.lineWidth = 2.2;
            const seed = rand(0, 10);
            for (let r = 8; r < 92; r += 6.5) {
                p.beginPath();
                for (let a = 0; a <= Math.PI * 2 + 0.05; a += 0.06) {
                    const w = r + Math.sin(a * 3 + seed) * 2.5 + Math.sin(a * 7 + r) * 1.2;
                    const x = g.cx + Math.cos(a) * w * 0.78, y = g.cy + Math.sin(a) * w;
                    if (a === 0) p.moveTo(x, y); else p.lineTo(x, y);
                }
                p.stroke();
            }
            p.globalCompositeOperation = 'destination-in';
            const og = p.createRadialGradient(g.cx, g.cy, 40, g.cx, g.cy, 92);
            og.addColorStop(0, 'rgba(0,0,0,1)'); og.addColorStop(1, 'rgba(0,0,0,0)');
            p.fillStyle = og; p.beginPath(); p.ellipse(g.cx, g.cy, 74, 94, 0, 0, Math.PI * 2); p.fill();
            g.print = pc;
            // reveal grid over the print
            g.cols = 18; g.rows = 22; g.gx = g.cx - 78; g.gy = g.cy - 98; g.cw = 156 / g.cols; g.ch = 196 / g.rows;
            g.cells = [];
            for (let j = 0; j < g.rows; j++) for (let i = 0; i < g.cols; i++) {
                const x = g.gx + (i + 0.5) * g.cw, y = g.gy + (j + 0.5) * g.ch;
                const inside = ((x - g.cx) / 74) ** 2 + ((y - g.cy) / 94) ** 2 < 0.9;
                g.cells.push({ x, y, need: inside, rev: 0 });
            }
            g.need = g.cells.filter((c) => c.need).length;
            g.mask = document.createElement('canvas'); g.mask.width = W; g.mask.height = H;
            g.view = document.createElement('canvas'); g.view.width = W; g.view.height = H;
            g.maskDirty = true;
            g.brushR = 30 / Math.sqrt(L); g.maxSpeed = 15 / L; g.phase = 'brush';
            g.particles = []; g.smearAt = 0;
        },
        update(g, L, dt, now) {
            if (g.phase === 'brush') {
                const speed = dist(input.x, input.y, input.px, input.py) / dt;
                if (input.down) {
                    if (speed > g.maxSpeed && now > g.smearAt) {
                        g.smearAt = now + 700;
                        for (const c of g.cells) if (dist(c.x, c.y, input.x, input.y) < g.brushR * 1.6) c.rev *= 0.4;
                        g.maskDirty = true;
                        strike('Too fast: smudged!');
                        return;
                    }
                    let hit = false;
                    for (const c of g.cells) {
                        if (c.rev < 1 && dist(c.x, c.y, input.x, input.y) < g.brushR) { c.rev = Math.min(1, c.rev + 0.05 * dt); hit = true; }
                    }
                    if (hit) {
                        g.maskDirty = true;
                        if (Math.random() < 0.6) g.particles.push({ x: input.x + rand(-8, 8), y: input.y + rand(-8, 8), vy: rand(0.2, 0.8), life: 1 });
                    }
                }
                let sum = 0;
                for (const c of g.cells) if (c.need) sum += c.rev;
                g.progress = sum / g.need / 0.82;
                if (g.progress >= 1) {
                    g.phase = 'tape'; g.tape = 0; g.tapeDir = 1; g.zone = 26 / L;
                    flash('Now press the tape on', '#fde047');
                    $('mgHint').textContent = 'Click when the tape is right over the print.';
                }
            } else {
                g.tape += g.tapeDir * dt * 2.6 * L;
                if (g.tape > 200 || g.tape < -200) g.tapeDir *= -1;
                if (input.pressed) {
                    if (Math.abs(g.tape) < g.zone) { g.progress = 1; finish(true); }
                    else strike('Missed: try again');
                }
            }
            for (const p of g.particles) { p.y += p.vy * dt; p.life -= 0.02 * dt; }
            g.particles = g.particles.filter((p) => p.life > 0).slice(-120);
        },
        draw(g) {
            ctx.drawImage(g.surface, 0, 0, W, H);
            if (g.maskDirty) {
                const m = g.mask.getContext('2d');
                m.clearRect(0, 0, W, H);
                m.fillStyle = '#e5e7eb';
                for (const c of g.cells) if (c.rev > 0) { m.globalAlpha = c.rev; m.fillRect(c.x - g.cw / 2 - 1, c.y - g.ch / 2 - 1, g.cw + 2, g.ch + 2); }
                const v = g.view.getContext('2d');
                v.globalCompositeOperation = 'source-over';
                v.clearRect(0, 0, W, H); v.drawImage(g.print, 0, 0);
                v.globalCompositeOperation = 'destination-in'; v.drawImage(g.mask, 0, 0);
                g.maskDirty = false;
            }
            // light powder haze where brushed
            ctx.globalAlpha = 0.08; ctx.drawImage(g.mask, 0, 0, W, H); ctx.globalAlpha = 1;
            ctx.drawImage(g.view, 0, 0, W, H);
            for (const p of g.particles) { ctx.globalAlpha = p.life * 0.7; ctx.fillStyle = '#e5e7eb'; ctx.fillRect(p.x, p.y, 2, 2); }
            ctx.globalAlpha = 1;
            if (g.phase === 'tape') {
                const x = g.cx + g.tape;
                ctx.fillStyle = 'rgba(74,222,128,.18)'; ctx.fillRect(g.cx - g.zone, g.cy - 110, g.zone * 2, 220);
                ctx.fillStyle = 'rgba(253,253,240,.32)'; ctx.strokeStyle = 'rgba(255,255,255,.6)';
                roundRect(x - 60, g.cy - 115, 120, 230, 4); ctx.fill(); ctx.stroke();
            }
        },
    };

    // 2. Casing: grab it at the rim, carry it into the bag without moving too fast
    GAMES.tweezers = {
        tool: 'tweezers', strikes: 3,
        start(g, L) {
            g.surface = makeSurface(['#3a3d42', '#2b2e33'], ['#9ca3af', '#4b5563', '#d1d5db'], 1400);
            g.c = { x: rand(140, 330), y: rand(120, 260), a: rand(0, Math.PI * 2), vx: rand(-0.3, 0.3) * L, vy: rand(-0.3, 0.3) * L, va: rand(-0.01, 0.01) * L };
            g.bag = { x: 448, y: 214, w: 128, h: 142 };
            g.grabR = 12 / Math.sqrt(L) + 6; g.maxSpeed = 16 / L; g.phase = 'grab'; g.wob = 0;
        },
        rim(g) { return { x: g.c.x + Math.cos(g.c.a) * 22, y: g.c.y + Math.sin(g.c.a) * 22 }; },
        nearBody(g, x, y) {
            const ax = g.c.x - Math.cos(g.c.a) * 22, ay = g.c.y - Math.sin(g.c.a) * 22;
            const r = this.rim(g);
            const t = clamp(((x - ax) * (r.x - ax) + (y - ay) * (r.y - ay)) / (44 * 44), 0, 1);
            return dist(x, y, ax + (r.x - ax) * t, ay + (r.y - ay) * t) < 9;
        },
        update(g, L, dt) {
            g.wob += dt * 0.08 * L;
            if (g.phase === 'grab') {
                g.c.x += (g.c.vx + Math.sin(g.wob) * 0.25 * L) * dt; g.c.y += (g.c.vy + Math.cos(g.wob * 0.7) * 0.2 * L) * dt; g.c.a += g.c.va * dt;
                if (g.c.x < 40 || g.c.x > 400) g.c.vx *= -1;
                if (g.c.y < 40 || g.c.y > H - 40) g.c.vy *= -1;
                g.c.x = clamp(g.c.x, 40, 400); g.c.y = clamp(g.c.y, 40, H - 40);
                if (input.pressed) {
                    const r = this.rim(g);
                    if (dist(input.x, input.y, r.x, r.y) < g.grabR) { g.phase = 'carry'; flash('Got it: into the bag', '#4ade80'); }
                    else if (this.nearBody(g, input.x, input.y)) {
                        g.c.vx = rand(-2, 2) * L; g.c.vy = rand(-2, 2) * L; g.c.va = rand(-0.08, 0.08);
                        setTimeout(() => { if (G === g) { g.c.vx *= 0.15; g.c.vy *= 0.15; g.c.va *= 0.2; } }, 400);
                        strike('You knocked it!');
                    }
                }
            } else {
                const speed = dist(input.x, input.y, input.px, input.py) / dt;
                g.c.x = input.x - Math.cos(g.c.a) * 22; g.c.y = input.y - Math.sin(g.c.a) * 22;
                if (!input.down) { g.phase = 'grab'; g.c.vx = rand(-0.3, 0.3) * L; g.c.vy = rand(-0.3, 0.3) * L; flash('Dropped it'); }
                else if (speed > g.maxSpeed) {
                    g.phase = 'grab'; g.c.vx = rand(-1, 1) * L; g.c.vy = rand(-1, 1) * L;
                    strike('Too fast: it slipped!');
                } else if (input.x > g.bag.x && input.x < g.bag.x + g.bag.w && input.y > g.bag.y + 20 && input.y < g.bag.y + g.bag.h) {
                    g.progress = 1; finish(true);
                }
            }
            if (!g.done) g.progress = g.phase === 'carry' ? 0.5 + 0.5 * clamp(1 - dist(input.x, input.y, g.bag.x + 64, g.bag.y + 70) / 400, 0, 1) * 0.9 : 0;
        },
        draw(g) {
            ctx.drawImage(g.surface, 0, 0, W, H);
            const b = g.bag;
            ctx.fillStyle = 'rgba(220,232,240,.22)'; ctx.strokeStyle = 'rgba(255,255,255,.7)'; ctx.lineWidth = 2;
            roundRect(b.x, b.y, b.w, b.h, 8); ctx.fill(); ctx.stroke();
            ctx.fillStyle = '#f59e0b'; ctx.fillRect(b.x + 10, b.y + 12, b.w - 20, 20);
            text('EVIDENCE', b.x + b.w / 2, b.y + 27, 13, '#fff');
            ctx.save(); ctx.translate(g.c.x, g.c.y); ctx.rotate(g.c.a);
            const grd = ctx.createLinearGradient(0, -7, 0, 7);
            grd.addColorStop(0, '#fde68a'); grd.addColorStop(0.5, '#f59e0b'); grd.addColorStop(1, '#92400e');
            ctx.fillStyle = grd; roundRect(-22, -7, 42, 14, 3); ctx.fill();
            ctx.fillStyle = '#78350f'; ctx.fillRect(18, -8, 5, 16);
            ctx.restore();
            if (g.phase === 'grab') {
                const r = this.rim(g);
                ctx.strokeStyle = 'rgba(253,224,71,.5)'; ctx.setLineDash([3, 3]);
                ctx.beginPath(); ctx.arc(r.x, r.y, g.grabR, 0, Math.PI * 2); ctx.stroke(); ctx.setLineDash([]);
            }
        },
    };

    // 3. Blood (and civilians wiping): rub in circles on the stain
    GAMES.swab = {
        tool: 'swab', strikes: 0,
        start(g, L) {
            g.surface = makeSurface(['#3b3f45', '#2c3036'], ['#9ca3af', '#52525b'], 1200);
            g.cx = rand(220, 380); g.cy = rand(150, 230); g.r = 70;
            g.blob = Array.from({ length: 14 }, (_, i) => ({ a: i / 14 * Math.PI * 2, r: rand(0.75, 1.15) }));
            g.drops = Array.from({ length: 7 }, () => ({ a: rand(0, Math.PI * 2), d: rand(1.2, 1.7), s: rand(3, 8) }));
            g.need = Math.PI * 2 * 2.6 * L; g.done2 = 0; g.lastA = null; g.warnAt = 0;
        },
        update(g, L, dt, now) {
            const d = dist(input.x, input.y, g.cx, g.cy);
            const a = Math.atan2(input.y - g.cy, input.x - g.cx);
            if (input.down && d < g.r + 6 && d > 10) {
                if (g.lastA !== null) {
                    let da = a - g.lastA;
                    if (da > Math.PI) da -= Math.PI * 2; if (da < -Math.PI) da += Math.PI * 2;
                    g.done2 += Math.min(Math.abs(da), 0.35);
                }
                g.lastA = a;
            } else {
                g.lastA = null;
                if (input.down && d >= g.r + 6) {
                    g.done2 = Math.max(0, g.done2 - 0.04 * dt * L);
                    if (now > g.warnAt) { g.warnAt = now + 900; flash('Stay on the stain'); }
                }
            }
            g.progress = g.done2 / g.need;
            if (g.progress >= 1) finish(true);
        },
        draw(g) {
            ctx.drawImage(g.surface, 0, 0, W, H);
            const fade = 1 - 0.7 * clamp(g.progress || 0, 0, 1);
            ctx.fillStyle = `rgba(127,29,29,${0.92 * fade})`;
            ctx.beginPath();
            g.blob.forEach((p, i) => {
                const x = g.cx + Math.cos(p.a) * g.r * p.r, y = g.cy + Math.sin(p.a) * g.r * p.r * 0.8;
                if (i === 0) ctx.moveTo(x, y); else ctx.lineTo(x, y);
            });
            ctx.closePath(); ctx.fill();
            for (const p of g.drops) {
                ctx.beginPath(); ctx.arc(g.cx + Math.cos(p.a) * g.r * p.d, g.cy + Math.sin(p.a) * g.r * p.d * 0.8, p.s, 0, Math.PI * 2); ctx.fill();
            }
            ctx.strokeStyle = 'rgba(255,255,255,.12)'; ctx.setLineDash([4, 6]);
            ctx.beginPath(); ctx.ellipse(g.cx, g.cy, g.r * 0.6, g.r * 0.48, 0, 0, Math.PI * 2); ctx.stroke(); ctx.setLineDash([]);
        },
        cursorFill(g) { return clamp(g.progress || 0, 0, 1); },
    };

    // 4. Bullet: steady pull inside the green zone
    GAMES.pull = {
        tool: 'dot', strikes: 3,
        start(g, L) {
            g.surface = makeSurface(['#6b6257', '#4f473e'], ['#d6d3d1', '#292524'], 1600);
            g.t = 0.2; g.zone = 0.24 / L; g.zc = 0.55; g.noise = rand(0, 10); g.prog = 0; g.warnAt = 0;
        },
        update(g, L, dt, now) {
            g.noise += 0.03 * dt * L;
            g.zc = 0.55 + Math.sin(g.noise * 0.6) * 0.14;
            const push = (Math.sin(g.noise * 2.3) + Math.sin(g.noise * 3.7)) * 0.0028 * L;
            g.t = clamp(g.t + (input.down ? 0.011 : -0.012) * dt + push * dt, 0, 1);
            if (g.t > 0.95) { g.t = 0.35; strike('Too hard: it broke off!'); return; }
            const inZone = Math.abs(g.t - g.zc) < g.zone / 2;
            if (inZone) g.prog += 0.0055 * dt;
            else if (g.t < g.zc) { g.prog = Math.max(0, g.prog - 0.002 * dt); if (input.down === false && now > g.warnAt && g.prog > 0) { g.warnAt = now + 1200; flash('It slips back'); } }
            g.progress = g.prog;
            if (g.prog >= 1) finish(true);
        },
        draw(g) {
            ctx.drawImage(g.surface, 0, 0, W, H);
            // hole and bullet coming out
            const out = clamp(g.prog, 0, 1) * 34;
            ctx.fillStyle = '#1c1917'; ctx.beginPath(); ctx.arc(250, 190, 18, 0, Math.PI * 2); ctx.fill();
            ctx.save(); ctx.translate(250 - out, 190);
            const grd = ctx.createLinearGradient(0, -9, 0, 9); grd.addColorStop(0, '#fdba74'); grd.addColorStop(1, '#7c2d12');
            ctx.fillStyle = grd; roundRect(-16, -9, 26, 18, 8); ctx.fill(); ctx.restore();
            // pliers
            ctx.strokeStyle = '#cbd5e1'; ctx.lineWidth = 6; ctx.lineCap = 'round';
            ctx.beginPath(); ctx.moveTo(230 - out, 182); ctx.lineTo(120 - out, 150); ctx.moveTo(230 - out, 198); ctx.lineTo(120 - out, 230); ctx.stroke();
            ctx.strokeStyle = '#dc2626'; ctx.lineWidth = 10;
            ctx.beginPath(); ctx.moveTo(150 - out, 158); ctx.lineTo(70 - out, 130); ctx.moveTo(150 - out, 222); ctx.lineTo(70 - out, 250); ctx.stroke();
            // tension meter
            const mx = 520, my = 40, mh = 300;
            ctx.fillStyle = 'rgba(0,0,0,.45)'; roundRect(mx - 18, my - 10, 36, mh + 20, 10); ctx.fill();
            ctx.fillStyle = 'rgba(239,68,68,.55)'; ctx.fillRect(mx - 10, my, 20, mh * 0.05);
            ctx.fillStyle = 'rgba(74,222,128,.55)';
            ctx.fillRect(mx - 10, my + mh * (1 - g.zc - g.zone / 2), 20, mh * g.zone);
            const ny = my + mh * (1 - g.t);
            ctx.fillStyle = '#fff'; roundRect(mx - 16, ny - 3, 32, 6, 3); ctx.fill();
            text('PULL', mx, my + mh + 30, 12, 'rgba(255,255,255,.6)');
        },
    };

    // 5. Vehicle fragments: click every shard
    GAMES.shards = {
        tool: 'dot', strikes: 5,
        start(g, L) {
            g.surface = makeSurface(['#2f3237', '#24272b'], ['#a1a1aa', '#71717a', '#e4e4e7'], 2600);
            const n = L >= 1.6 ? 6 : (L >= 1.3 ? 5 : 4);
            g.shards = [];
            while (g.shards.length < n) {
                const s = { x: rand(40, W - 40), y: rand(40, H - 40), a: rand(0, 6), size: rand(7, 11), glint: rand(0, 6), red: Math.random() < 0.3, got: 0 };
                if (g.shards.every((o) => dist(o.x, o.y, s.x, s.y) > 70)) g.shards.push(s);
            }
            g.hitR = 12 / Math.sqrt(L) + 8;
        },
        update(g, L, dt) {
            for (const s of g.shards) { s.glint += 0.03 * dt; if (s.got) s.got = Math.min(1, s.got + 0.08 * dt); }
            if (input.pressed) {
                const s = g.shards.find((o) => !o.got && dist(o.x, o.y, input.x, input.y) < g.hitR);
                if (s) { s.got = 0.01; flash('Fragment bagged', '#4ade80'); } else strike('Nothing there');
            }
            const got = g.shards.filter((s) => s.got).length;
            g.progress = got / g.shards.length;
            if (got === g.shards.length) finish(true);
        },
        draw(g) {
            ctx.drawImage(g.surface, 0, 0, W, H);
            for (const s of g.shards) {
                if (s.got >= 1) continue;
                ctx.save(); ctx.translate(s.x, s.y); ctx.rotate(s.a); ctx.scale(1 - s.got, 1 - s.got);
                ctx.fillStyle = s.red ? 'rgba(185,28,28,.9)' : 'rgba(186,230,253,.7)';
                ctx.strokeStyle = 'rgba(255,255,255,.35)'; ctx.lineWidth = 1;
                ctx.beginPath(); ctx.moveTo(-s.size, 0); ctx.lineTo(0, -s.size * 0.7); ctx.lineTo(s.size * 0.8, s.size * 0.3); ctx.lineTo(-s.size * 0.2, s.size * 0.6); ctx.closePath(); ctx.fill(); ctx.stroke();
                const gl = Math.max(0, Math.sin(s.glint * 1.7)) ** 12;
                if (gl > 0.02) { ctx.fillStyle = `rgba(255,255,255,${gl})`; ctx.beginPath(); ctx.arc(0, 0, 2 + gl * 3, 0, Math.PI * 2); ctx.fill(); }
                ctx.restore();
            }
        },
    };

    // 6. GSR: hold the swab on each glowing spot, right hand first
    GAMES.gsrswab = {
        tool: 'swab', strikes: 0,
        start(g, L) {
            g.surface = makeSurface(['#24303a', '#1b232b'], ['#64748b'], 300);
            const spots = (cx) => [{ x: cx, y: 230 }, { x: cx + (cx < 300 ? 42 : -42), y: 190 }, { x: cx, y: 120 }];
            g.spots = [...spots(170), ...spots(430)].map((s) => ({ ...s, hold: 0 }));
            g.i = 0; g.holdNeed = 30 * Math.sqrt(L); g.r = 20 / Math.sqrt(L) + 6;
        },
        hand(cx, label) {
            ctx.fillStyle = 'rgba(232,190,160,.9)';
            roundRect(cx - 52, 160, 104, 110, 30); ctx.fill();
            for (let f = 0; f < 4; f++) { roundRect(cx - 48 + f * 26, 70 - (f === 1 || f === 2 ? 14 : 0), 20, 100, 10); ctx.fill(); }
            ctx.save(); ctx.translate(cx + (cx < 300 ? 52 : -52), 200); ctx.rotate(cx < 300 ? -0.7 : 0.7);
            roundRect(-10, -50, 20, 60, 10); ctx.fill(); ctx.restore();
            text(label, cx, 300, 13, 'rgba(255,255,255,.6)');
        },
        update(g, L, dt) {
            const s = g.spots[g.i];
            if (input.down && dist(input.x, input.y, s.x, s.y) < g.r) {
                s.hold += dt;
                if (s.hold >= g.holdNeed) {
                    g.i++;
                    if (g.i === 3) flash('Now the left hand', '#4ade80');
                    if (g.i >= g.spots.length) { g.progress = 1; finish(true); return; }
                }
            } else s.hold = Math.max(0, s.hold - dt * 2);
            g.progress = (g.i + (g.spots[g.i] ? g.spots[g.i].hold / g.holdNeed : 0)) / g.spots.length;
        },
        draw(g, now) {
            ctx.drawImage(g.surface, 0, 0, W, H);
            this.hand(170, 'RIGHT HAND');
            this.hand(430, 'LEFT HAND');
            g.spots.forEach((s, i) => {
                if (i < g.i) { ctx.fillStyle = 'rgba(55,65,81,.8)'; ctx.beginPath(); ctx.arc(s.x, s.y, 7, 0, Math.PI * 2); ctx.fill(); return; }
                if (i !== g.i) return;
                const pulse = 0.5 + 0.5 * Math.sin(now / 160);
                ctx.strokeStyle = `rgba(253,224,71,${0.5 + pulse * 0.5})`; ctx.lineWidth = 3;
                ctx.beginPath(); ctx.arc(s.x, s.y, g.r, 0, Math.PI * 2); ctx.stroke();
                ctx.strokeStyle = '#4ade80'; ctx.lineWidth = 4;
                ctx.beginPath(); ctx.arc(s.x, s.y, g.r + 6, -Math.PI / 2, -Math.PI / 2 + Math.PI * 2 * (s.hold / g.holdNeed)); ctx.stroke();
            });
        },
        cursorFill(g) { return 0.15 + 0.5 * (g.i / g.spots.length); },
    };

    // ---------------------------------------------------------------- loop
    function frame(now) {
        if (!G) return;
        const dt = clamp((now - (G.last || now)) / 16.67, 0, 3);   // 1 = one 60 fps frame
        G.last = now;
        const def = GAMES[G.name];
        if (!G.done) {
            const left = G.endsAt - now;
            if (left <= 0) finish(false, 'timeout');
            else def.update(G, G.L, dt || 1, now);
            $('mgTime').style.width = `${clamp(left / (G.seconds * 1000), 0, 1) * 100}%`;
            $('mgTimeBar').classList.toggle('low', left < 4000);
        }
        $('mgProg').style.width = `${clamp(G.progress || 0, 0, 1) * 100}%`;
        ctx.clearRect(0, 0, W, H);
        def.draw(G, now);
        const tool = TOOLS[def.tool] || TOOLS.dot;
        tool(input.x, input.y, input.down, def.cursorFill ? def.cursorFill(G) : 0);
        if (G.flash && now < G.flash.until) {
            const a = clamp((G.flash.until - now) / 300, 0, 1);
            ctx.globalAlpha = a;
            ctx.fillStyle = 'rgba(0,0,0,.55)'; roundRect(W / 2 - 140, 16, 280, 34, 10); ctx.fill();
            text(G.flash.text, W / 2, 39, 17, G.flash.color);
            ctx.globalAlpha = 1;
        }
        input.px = input.x; input.py = input.y; input.pressed = false; input.released = false;
        raf = requestAnimationFrame(frame);
    }

    function open(msg) {
        const def = GAMES[msg.game];
        if (!def) {
            fetch(`https://${RES}/gameDone`, { method: 'POST', body: JSON.stringify({ token: msg.token, passed: false, why: 'failed' }) }).catch(() => {});
            return;
        }
        const level = LEVEL[msg.difficulty] ? msg.difficulty : 'easy';
        G = { name: msg.game, token: msg.token, L: LEVEL[level], seconds: SECONDS[level], strikes: 0, maxStrikes: def.strikes, progress: 0 };
        G.endsAt = performance.now() + G.seconds * 1000;
        input.x = input.px = W / 2; input.y = input.py = H / 2; input.down = false;
        def.start(G, G.L);
        const [title, hint] = TITLES[msg.game];
        $('mgTitle').textContent = title;
        $('mgHint').textContent = hint;
        $('mgKeys').textContent = msg.pad ? 'Right stick: move  ·  A: hold / grab  ·  B: give up' : 'Mouse: move  ·  Left button: hold / grab  ·  Esc: give up';
        drawStrikes();
        root.classList.add('open');
        cancelAnimationFrame(raf);
        raf = requestAnimationFrame(frame);
    }

    function close() {
        G = null;
        cancelAnimationFrame(raf);
        root.classList.remove('open');
    }

    window.addEventListener('message', (e) => {
        const d = e.data || {};
        if (d.action === 'game') open(d);
        else if (d.action === 'gameClose') close();
        else if (d.action === 'gameStick' && G) {
            input.x = clamp(input.x + d.dx * 9, 0, W);
            input.y = clamp(input.y + d.dy * 9, 0, H);
        } else if (d.action === 'gameButton' && G && d.cmd === 'a') {
            if (d.down) { input.down = true; input.pressed = true; } else { input.down = false; input.released = true; }
        }
    });

    // for the browser preview
    window.__whipEvidenceGames = { open, close, GAMES };
})();
