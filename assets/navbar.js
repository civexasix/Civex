// Navbar "focus lens": el enlace más cercano al cursor se enfoca,
// los demás se atenúan y unos corchetes de visor se deslizan hasta él.
(() => {
  const nav = document.querySelector(".nav-links");
  if (!nav) return;

  const links = [...nav.querySelectorAll("a")];
  const lens = document.createElement("span");
  lens.className = "lens";
  nav.appendChild(lens);

  function focusLink(active) {
    links.forEach((a) => {
      a.classList.toggle("is-focus", a === active);
      a.classList.toggle("is-dim", !!active && a !== active);
    });

    if (!active) {
      lens.classList.remove("show");
      return;
    }
    const n = nav.getBoundingClientRect();
    const r = active.getBoundingClientRect();
    lens.style.width = r.width + 16 + "px";
    lens.style.height = r.height + 12 + "px";
    lens.style.transform = `translate(${r.left - n.left - 8}px, ${r.top - n.top - 6}px)`;
    lens.classList.add("show");
  }

  nav.addEventListener("pointermove", (e) => {
    if (e.pointerType === "touch") return; // sin efecto persistente en táctil
    // Sobre el botón Log In no se enfoca ningún enlace
    if (e.target.closest(".btn-log")) {
      focusLink(null);
      return;
    }
    let nearest = null;
    let best = Infinity;
    links.forEach((a) => {
      const r = a.getBoundingClientRect();
      const d = Math.abs(e.clientX - (r.left + r.width / 2));
      if (d < best) {
        best = d;
        nearest = a;
      }
    });
    focusLink(nearest);
  });

  nav.addEventListener("pointerleave", () => focusLink(null));
})();
