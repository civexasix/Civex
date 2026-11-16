// Lenis (smooth scroll) + GSAP ScrollTrigger (parallax y galería horizontal)
gsap.registerPlugin(ScrollTrigger);

const reduceMotion = window.matchMedia("(prefers-reduced-motion: reduce)").matches;

// ---------- Lenis ----------
if (!reduceMotion) {
  const lenis = new Lenis({
    duration: 1.2,
    easing: (t) => Math.min(1, 1.001 - Math.pow(2, -10 * t)),
    smoothWheel: true,
    anchors: true, // los enlaces #nosotros, #metodologia... hacen scroll suave
  });

  // Sincroniza Lenis con ScrollTrigger usando el ticker de GSAP
  lenis.on("scroll", ScrollTrigger.update);
  gsap.ticker.add((time) => lenis.raf(time * 1000));
  gsap.ticker.lagSmoothing(0);
}

// ---------- Parallax hero → nosotros ----------
if (!reduceMotion) {
  const heroScroll = {
    trigger: ".hero",
    start: "top top",
    end: "bottom top",
    scrub: true,
  };

  // El texto del hero baja más despacio que el scroll y se desvanece
  gsap.to(".hero-content", {
    yPercent: 30,
    opacity: 0,
    ease: "none",
    scrollTrigger: heroScroll,
  });

  // El fondo (canvas) se mueve menos que el contenido: sensación de profundidad
  gsap.to("#hero-canvas", {
    yPercent: 15,
    ease: "none",
    scrollTrigger: heroScroll,
  });

  // En "Nosotros": terminal y texto se mueven a distinta velocidad
  const nosotrosScroll = {
    trigger: "#nosotros",
    start: "top bottom",
    end: "bottom top",
    scrub: true,
  };

  gsap.fromTo(
    "#nosotros .terminal",
    { y: 70 },
    { y: -50, ease: "none", scrollTrigger: nosotrosScroll }
  );

  gsap.fromTo(
    "#nosotros .split > div:last-child",
    { y: 30 },
    { y: -20, ease: "none", scrollTrigger: nosotrosScroll }
  );
}

// ---------- Galería con scroll horizontal ----------
const mm = gsap.matchMedia();

// Solo en escritorio/tablet; en móvil las tarjetas se apilan en vertical
mm.add("(min-width: 751px)", () => {
  const section = document.querySelector("#metodologia");
  const track = section.querySelector(".cards");

  // Distancia real que hay que recorrer en horizontal
  const getDistance = () => Math.max(0, track.scrollWidth - window.innerWidth);

  const scrollTween = gsap.to(track, {
    x: () => -getDistance(),
    ease: "none",
    scrollTrigger: {
      trigger: section,
      start: "top top",
      end: () => "+=" + getDistance(),
      pin: true,
      scrub: 1,
      anticipatePin: 1,
      invalidateOnRefresh: true,
    },
  });

  // El número grande de cada tarjeta se desliza un poco al pasar
  if (!reduceMotion) {
    gsap.utils.toArray(".card", track).forEach((card) => {
      const num = card.querySelector(".card-number");
      gsap.fromTo(
        num,
        { xPercent: -20 },
        {
          xPercent: 20,
          ease: "none",
          scrollTrigger: {
            trigger: card,
            containerAnimation: scrollTween,
            start: "left right",
            end: "right left",
            scrub: true,
          },
        }
      );
    });
  }
});

// Recalcula cuando carguen todas las imágenes y fuentes
window.addEventListener("load", () => ScrollTrigger.refresh());
