// Dashboard CIVEX.
// Todo lo que se pinta sale del objeto DATOS. Ahora son datos de ejemplo,
// con la MISMA forma que devolverá la API en PHP (basada en las vistas de
// civex.sql). Para conectar la base de datos solo habrá que sustituir DATOS
// por el resultado de fetch("api/datos.php").

(() => {
  // ---------- Datos de ejemplo ----------
  const ahora = Date.now();
  const hace = (min) => new Date(ahora - min * 60000);

  const DATOS = {
    usuario: "Usuario",
    cliente: "Clínica Dental SonrisaViva",

    // v_kpis_cliente
    kpis: {
      maquinas_total: 6,
      maquinas_activas: 5,
      alertas_total: 6,
      alertas_resueltas: 2,
      vuln_total: 5,
      vuln_corregidas: 1,
      backups_total: 8,
      backups_correctos: 7,
    },

    // v_vuln_por_riesgo
    vulnPorRiesgo: { critica: 1, alta: 2, media: 1, baja: 1 },

    // media de CPU y RAM por hora (metricas_historico)
    rendimiento: {
      horas: ["10:00", "11:00", "12:00", "13:00", "14:00", "15:00", "16:00"],
      cpu: [22, 28, 35, 31, 42, 38, 33],
      ram: [48, 50, 53, 55, 58, 57, 56],
    },

    // v_alertas_detalle (las 5 más recientes)
    alertas: [
      { maquina: "FW-01", descripcion: "Intentos de autenticación SSH fallidos", gravedad: "alta", fecha: hace(20) },
      { maquina: "WEB-01", descripcion: "Escaneo de puertos detectado", gravedad: "media", fecha: hace(55) },
      { maquina: "CLINICA-01", descripcion: "Servicio MariaDB detenido", gravedad: "media", fecha: hace(180) },
      { maquina: "DNS-01", descripcion: "Cambio en la configuración del DNS", gravedad: "baja", fecha: hace(300) },
    ],

    // servicios
    servicios: [
      { nombre: "Proxmox", estado: "disponible" },
      { nombre: "DNS", estado: "disponible" },
      { nombre: "Web HTTPS", estado: "disponible" },
      { nombre: "MariaDB", estado: "caido" },
      { nombre: "Wazuh", estado: "disponible" },
      { nombre: "Prometheus", estado: "disponible" },
    ],

    // backups (los más recientes)
    backups: [
      { maquina: "CLINICA-01", resultado: "correcto", fecha: hace(1440), tamanoMb: 2400 },
      { maquina: "WEB-01", resultado: "correcto", fecha: hace(1440), tamanoMb: 860 },
      { maquina: "DNS-01", resultado: "correcto", fecha: hace(1440), tamanoMb: 120 },
      { maquina: "CLINICA-01", resultado: "fallido", fecha: hace(2880), tamanoMb: null },
    ],
  };

  // ---------- Utilidades ----------
  // Se usa textContent siempre: las descripciones de alertas vendrán de logs
  // externos y nunca deben interpretarse como HTML.
  function el(tag, clase, texto) {
    const nodo = document.createElement(tag);
    if (clase) nodo.className = clase;
    if (texto !== undefined) nodo.textContent = texto;
    return nodo;
  }

  const pct = (valor, total) => (total > 0 ? Math.round((valor / total) * 100) : 0);

  const GRAVEDAD = { critica: "Crítica", alta: "Alta", media: "Media", baja: "Baja" };
  const SERVICIO = { disponible: "Disponible", degradado: "Degradado", caido: "Caído" };
  const BACKUP = { correcto: "Correcto", fallido: "Fallido" };

  function fechaCorta(fecha) {
    return new Date(fecha).toLocaleString("es-ES", {
      day: "2-digit",
      month: "2-digit",
      hour: "2-digit",
      minute: "2-digit",
    });
  }

  function tamano(mb) {
    if (mb == null) return "–";
    return mb >= 1024 ? (mb / 1024).toFixed(1) + " GB" : mb + " MB";
  }

  // ---------- Cabecera, usuario y fecha ----------
  document.getElementById("saludo").textContent = `Bienvenido, ${DATOS.usuario}!`;
  document.getElementById("cliente-nombre").textContent = DATOS.cliente;
  document.getElementById("usuario-nombre").textContent = DATOS.usuario;
  document.getElementById("usuario-inicial").textContent = DATOS.usuario.charAt(0).toUpperCase();

  const fecha = document.getElementById("fecha-hoy");
  if (fecha) {
    const hoy = new Date();
    fecha.dateTime = hoy.toISOString().slice(0, 10);
    fecha.textContent = hoy.toLocaleDateString("es-ES", {
      day: "numeric",
      month: "long",
      year: "numeric",
    });
  }

  // ---------- KPIs ----------
  const k = DATOS.kpis;
  document.getElementById("kpi-maquinas").textContent = `${k.maquinas_activas}/${k.maquinas_total}`;
  document.getElementById("kpi-alertas").textContent = k.alertas_total - k.alertas_resueltas;
  document.getElementById("kpi-vulnerabilidades").textContent = k.vuln_total - k.vuln_corregidas;
  document.getElementById("kpi-backups").textContent = pct(k.backups_correctos, k.backups_total) + "%";

  // ---------- Listas ----------
  const listaAlertas = document.getElementById("lista-alertas");
  DATOS.alertas.forEach((a) => {
    const li = el("li", "item");
    li.appendChild(el("span", `badge badge--${a.gravedad}`, GRAVEDAD[a.gravedad]));
    const texto = el("div", "item__texto");
    texto.appendChild(el("strong", "", a.maquina));
    texto.appendChild(el("span", "", a.descripcion));
    li.appendChild(texto);
    li.appendChild(el("time", "item__fecha", fechaCorta(a.fecha)));
    listaAlertas.appendChild(li);
  });

  const listaServicios = document.getElementById("lista-servicios");
  DATOS.servicios.forEach((s) => {
    const li = el("li", "item item--servicio");
    li.appendChild(el("span", `dot dot--${s.estado}`));
    li.appendChild(el("strong", "", s.nombre));
    li.appendChild(el("span", `estado estado--${s.estado}`, SERVICIO[s.estado]));
    listaServicios.appendChild(li);
  });

  const listaBackups = document.getElementById("lista-backups");
  DATOS.backups.forEach((b) => {
    const li = el("li", "item");
    li.appendChild(el("span", `badge badge--${b.resultado}`, BACKUP[b.resultado]));
    const texto = el("div", "item__texto");
    texto.appendChild(el("strong", "", b.maquina));
    texto.appendChild(el("span", "", tamano(b.tamanoMb)));
    li.appendChild(texto);
    li.appendChild(el("time", "item__fecha", fechaCorta(b.fecha)));
    listaBackups.appendChild(li);
  });

  // ---------- Menú lateral ----------
  const app = document.getElementById("app");
  const overlay = document.getElementById("overlay");
  const esMovil = () => window.matchMedia("(max-width: 900px)").matches;

  function cerrarMenuMovil() {
    app.classList.remove("menu-abierto");
    overlay.hidden = true;
  }

  document.querySelectorAll("[data-toggle-menu]").forEach((btn) => {
    btn.addEventListener("click", () => {
      if (esMovil()) {
        const abierto = app.classList.toggle("menu-abierto");
        overlay.hidden = !abierto;
      } else {
        app.classList.toggle("mini-menu");
      }
    });
  });

  overlay.addEventListener("click", cerrarMenuMovil);
  document.addEventListener("keydown", (e) => {
    if (e.key === "Escape") cerrarMenuMovil();
  });
  window.addEventListener("resize", () => {
    if (!esMovil()) cerrarMenuMovil();
  });

  // ---------- Exportar PDF (de momento, imprime la página) ----------
  document
    .getElementById("btn-export")
    ?.addEventListener("click", () => window.print());

  // ---------- Gráficos ----------
  if (typeof Chart === "undefined") return;

  const LILA = "#8b5cf6";
  const VERDE = "#b2ff8d";
  const LILA_CLARO = "#c9b8fb";
  const GRIS = "#4a4f5c";
  const PISTA = "#2b2f39";
  const TEXTO = "#e5e7eb";

  Chart.defaults.color = TEXTO;
  Chart.defaults.font.family = "'Manrope', sans-serif";
  Chart.defaults.font.size = 12;

  // Plugin: texto en el centro de los circulares
  const textoCentro = {
    id: "textoCentro",
    afterDraw(chart) {
      const texto = chart.options.plugins.textoCentro?.texto;
      if (!texto) return;
      const { ctx, chartArea } = chart;
      const x = (chartArea.left + chartArea.right) / 2;
      const y = (chartArea.top + chartArea.bottom) / 2;
      ctx.save();
      ctx.fillStyle = "#f3f3f3";
      ctx.font = `800 ${chart.options.plugins.textoCentro.tamano || 16}px Orbitron, sans-serif`;
      ctx.textAlign = "center";
      ctx.textBaseline = "middle";
      ctx.fillText(texto, x, y);
      ctx.restore();
    },
  };
  Chart.register(textoCentro);

  // Líneas: CPU y RAM medias
  const lineas = document.getElementById("chart-lineas");
  if (lineas) {
    new Chart(lineas, {
      type: "line",
      data: {
        labels: DATOS.rendimiento.horas,
        datasets: [
          {
            label: "CPU (%)",
            data: DATOS.rendimiento.cpu,
            borderColor: LILA,
            backgroundColor: "rgba(139, 92, 246, 0.12)",
            fill: true,
            tension: 0.25,
            borderWidth: 3,
            pointRadius: 0,
            pointHoverRadius: 6,
          },
          {
            label: "RAM (%)",
            data: DATOS.rendimiento.ram,
            borderColor: VERDE,
            tension: 0.25,
            borderWidth: 3,
            pointRadius: 0,
            pointHoverRadius: 6,
          },
        ],
      },
      options: {
        responsive: true,
        maintainAspectRatio: false,
        interaction: { mode: "index", intersect: false },
        plugins: { legend: { display: false } },
        scales: {
          x: { grid: { display: false }, border: { display: false } },
          y: {
            beginAtZero: true,
            max: 100,
            grid: { color: "rgba(255,255,255,0.06)" },
            border: { display: false },
          },
        },
      },
    });
  }

  // Circular grande: vulnerabilidades por riesgo
  const riesgo = DATOS.vulnPorRiesgo;
  const totalVuln = riesgo.critica + riesgo.alta + riesgo.media + riesgo.baja;
  const severidad = document.getElementById("chart-severidad");
  if (severidad) {
    new Chart(severidad, {
      type: "doughnut",
      data: {
        labels: ["Crítica", "Alta", "Media", "Baja"],
        datasets: [
          {
            data: [riesgo.critica, riesgo.alta, riesgo.media, riesgo.baja],
            backgroundColor: [LILA, VERDE, LILA_CLARO, GRIS],
            borderWidth: 0,
            hoverOffset: 6,
          },
        ],
      },
      options: {
        responsive: true,
        maintainAspectRatio: false,
        cutout: "68%",
        plugins: {
          legend: { display: false },
          textoCentro: { texto: String(totalVuln), tamano: 26 },
        },
      },
    });
  }

  // 4 circulares pequeños: porcentajes calculados desde los KPIs
  const resumen = [
    { id: "mini-1", valor: pct(k.maquinas_activas, k.maquinas_total), color: LILA },
    { id: "mini-2", valor: pct(k.alertas_resueltas, k.alertas_total), color: VERDE },
    { id: "mini-3", valor: pct(k.vuln_corregidas, k.vuln_total), color: LILA },
    { id: "mini-4", valor: pct(k.backups_correctos, k.backups_total), color: VERDE },
  ];

  resumen.forEach(({ id, valor, color }) => {
    const canvas = document.getElementById(id);
    if (!canvas) return;
    new Chart(canvas, {
      type: "doughnut",
      data: {
        datasets: [
          {
            data: [valor, 100 - valor],
            backgroundColor: [color, PISTA],
            borderWidth: 0,
          },
        ],
      },
      options: {
        responsive: true,
        maintainAspectRatio: true,
        cutout: "70%",
        plugins: {
          legend: { display: false },
          tooltip: { enabled: false },
          textoCentro: { texto: `${valor}%`, tamano: 15 },
        },
      },
    });
  });
})();