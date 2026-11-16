// Degradado animado e interactivo para el hero (canvas, sin librerías).
// Varias manchas de color se mueven solas y una sigue al cursor.
(() => {
  const canvas = document.getElementById("hero-canvas");
  if (!canvas) return;

  const ctx = canvas.getContext("2d");
  const hero = canvas.parentElement;
  const reduceMotion = window.matchMedia(
    "(prefers-reduced-motion: reduce)",
  ).matches;

  // Colores de la paleta del proyecto (rgb) y su tamaño relativo
  const blobs = [
    { color: "91, 52, 190", size: 0.55, speed: 0.0006, phase: 0 }, // lila muy oscuro
    { color: "110, 80, 200", size: 0.45, speed: 0.0009, phase: 2 }, // lila apagado
    { color: "70, 140, 60", size: 0.25, speed: 0.0007, phase: 4 }, // verde oscuro
    { color: "91, 52, 190", size: 0.4, speed: 0.0011, phase: 5.5 }, // lila muy oscuro
  ];

  // El cursor arrastra una mancha extra con suavizado
  const pointer = { x: 0.5, y: 0.5, tx: 0.5, ty: 0.5 };

  let w = 0;
  let h = 0;

  function resize() {
    const dpr = Math.min(window.devicePixelRatio || 1, 2);
    w = hero.clientWidth;
    h = hero.clientHeight;
    canvas.width = w * dpr;
    canvas.height = h * dpr;
    ctx.setTransform(dpr, 0, 0, dpr, 0, 0);
  }

  function drawBlob(x, y, radius, color, alpha) {
    const g = ctx.createRadialGradient(x, y, 0, x, y, radius);
    g.addColorStop(0, `rgba(${color}, ${alpha})`);
    g.addColorStop(1, `rgba(${color}, 0)`);
    ctx.fillStyle = g;
    ctx.fillRect(0, 0, w, h);
  }

  function frame(t) {
    ctx.globalCompositeOperation = "source-over";
    ctx.fillStyle = "#111111";
    ctx.fillRect(0, 0, w, h);
    ctx.globalCompositeOperation = "lighter";

    const base = Math.max(w, h);

    blobs.forEach((b) => {
      const a = t * b.speed + b.phase;
      const x = w * (0.5 + 0.35 * Math.cos(a));
      const y = h * (0.5 + 0.3 * Math.sin(a * 1.3));
      drawBlob(x, y, base * b.size, b.color, 0.45);
    });

    // Mancha que sigue al cursor
    pointer.x += (pointer.tx - pointer.x) * 0.06;
    pointer.y += (pointer.ty - pointer.y) * 0.06;
    drawBlob(pointer.x * w, pointer.y * h, base * 0.3, "178, 255, 141", 0.35);

    if (!reduceMotion) requestAnimationFrame(frame);
  }

  hero.addEventListener("pointermove", (e) => {
    const r = hero.getBoundingClientRect();
    pointer.tx = (e.clientX - r.left) / r.width;
    pointer.ty = (e.clientY - r.top) / r.height;
  });

  window.addEventListener("resize", resize);
  resize();
  requestAnimationFrame(frame);
})();
