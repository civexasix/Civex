# 🛡️ CIVEX — Empresa de ciberseguridad (Proyecto ASIX)

> Proyecto de 2.º de ASIX · **Versión provisional (primera entrega)**
> Equipo: **Alejandro**, **Marc** y **Felipe**

---

## 1. ¿Qué es CIVEX?

CIVEX es una **empresa ficticia de ciberseguridad**. Su trabajo es analizar y proteger la infraestructura informática de otras empresas, **antes y después** de un posible ataque.

> 💡 **Ejemplo para entenderlo rápido:** imagina que un cerrajero revisa las puertas de tu casa. Intenta abrirlas (con tu permiso) para ver cuáles son débiles, te dice cuáles hay que cambiar y, cuando las has cambiado, vuelve a probar. Nosotros hacemos lo mismo, pero con servidores y redes.

Todo el proyecto se hace en un **entorno controlado y ficticio**: no se ataca nada real ni se usan datos reales.

## 2. Cliente de ejemplo: Clínica Dental SonrisaViva

Para simular el servicio hemos inventado un cliente: **Clínica Dental SonrisaViva**, un centro médico privado ficticio que:

- Guarda historiales clínicos y datos de pacientes (ficticios).
- Tiene una web de citas online.
- Necesita backups críticos.
- Tiene poco personal de informática, así que necesita ayuda externa.

Lo hemos elegido porque maneja información sensible y varios tipos de servicios, lo que lo hace muy didáctico para practicar.

## 3. Objetivo del servicio

```
Analizar → Prevenir → Atacar → Detectar → Informar → Corregir → Recuperar
```

| Fase | Qué hacemos |
|------|-------------|
| **Analizar** | Estudiamos la red, los sistemas operativos y la configuración del cliente para encontrar puntos débiles. |
| **Prevenir** | Proponemos medidas de protección (firewall, monitorización, etc.). |
| **Atacar** | Hacemos pruebas de seguridad **controladas** desde Kali Linux para comprobar si los puntos débiles son reales. |
| **Detectar** | Wazuh (SOC) registra y avisa de lo que ocurre durante las pruebas. |
| **Informar** | Por cada vulnerabilidad generamos un informe: problema, riesgo, sistemas afectados y solución. |
| **Corregir** | Aplicamos las medidas correctivas y preventivas. |
| **Recuperar** | Repetimos las pruebas para confirmar que todo está arreglado y mantenemos backups. |

## 4. Los 3 PCs del proyecto

| PC | Responsable | Qué representa | Tecnologías principales |
|----|-------------|----------------|-------------------------|
| **PC 1** | Felipe | Infraestructura del **cliente** (SonrisaViva) | Proxmox VE, Linux, DNS, DMZ, nftables, Suricata, Wazuh, Prometheus/Grafana |
| **PC 2** | Marc | **Nuestra empresa** (CIVEX) | VirtualBox, Ubuntu Server, plataforma web, Firebase, informes y backups |
| **PC 3** | Alejandro | El **atacante** | VirtualBox, Kali Linux |

### Esquema simplificado

```
                  RED DEL AULA (hace de "Internet")
        ┌──────────────────┼──────────────────┐
        │                  │                  │
     PC 1 (Felipe)      PC 2 (Marc)       PC 3 (Alejandro)
   Cliente SonrisaViva   CIVEX            Kali (atacante)
        │
     ┌──┴── FW-01 (firewall) ──┐
     │                         │
 RED CLIENTE                  DMZ
 DNS · Clínica               Web de citas
 Wazuh · Monitorización
```

> 💡 **¿Qué es una DMZ?** Es una zona intermedia donde se pone lo que tiene que ser visible desde fuera (la web de citas), para que, si alguien la hackea, **no llegue directamente** a los datos de los pacientes.

Más detalle:

- 📖 [`docs/explicacion-flujo-red.md`](docs/explicacion-flujo-red.md): explicación paso a paso de cómo viaja el tráfico por la red, con ejemplos fáciles.
- 🔧 [`docs/arquitectura.md`](docs/arquitectura.md): redes, IPs, máquinas y reglas de firewall.

## 5. Herramientas que usaremos

| Herramienta | Para qué sirve (explicado fácil) |
|-------------|----------------------------------|
| **Proxmox VE** | Programa para crear y gestionar muchas máquinas virtuales en un solo PC. |
| **VirtualBox** | Lo mismo, pero más sencillo, para los PCs 2 y 3. |
| **nftables** | El firewall: decide qué tráfico de red pasa y cuál se bloquea. |
| **Suricata** | Vigilante de red (IDS): avisa si ve tráfico sospechoso. |
| **Wazuh** | El "centro de control" de seguridad (SOC): recoge logs y alertas de todas las máquinas. |
| **Prometheus + Grafana** | Monitorizan el estado de los servidores (CPU, memoria, etc.) con gráficas. |
| **Kali Linux** | Sistema con herramientas para hacer pruebas de seguridad. |
| **Firebase** | Base de datos en tiempo real para mostrar resultados en la web. |
| **GitHub** | Guardar y compartir documentación y scripts. |

## 6. Plataforma web y automatizaciones

- **Dashboard para el cliente:** tras iniciar sesión, podrá ver el estado de sus sistemas, alertas, incidencias y vulnerabilidades, actualizado en tiempo real gracias a Firebase.
- **Playbook:** documento que estandariza el servicio (qué analizar, qué pruebas hacer, cómo detectar los ataques, cómo hacer los informes y cómo verificar las soluciones).
- **Automatizaciones previstas:**
  - Recogida de logs con Wazuh.
  - Envío de alertas a Firebase y actualización del dashboard.
  - Generación de informes con plantillas y scripts.
  - Escaneos programados.
  - Backups automáticos.

## 7. Reparto del trabajo

| Persona | Responsabilidades |
|---------|-------------------|
| **Alejandro** | Coordinación, documentación, pruebas de seguridad (Kali). |
| **Marc** | Plataforma web, backend e integración con Firebase. |
| **Felipe** | Sistemas: Proxmox, máquinas virtuales, redes, DNS, firewall y backups. |

## 8. Estado del proyecto

Esta es una **primera entrega provisional**: presentamos la idea y el diseño. La implementación está en marcha.

- [x] Idea y alcance del proyecto
- [x] Diseño de redes y direccionamiento (v1)
- [ ] Montaje de PC 1 (Proxmox y máquinas del cliente)
- [ ] Montaje de PC 2 (CIVEX) y PC 3 (Kali)
- [ ] Firewall, Wazuh y monitorización
- [ ] Plataforma web + Firebase
- [ ] Pruebas de seguridad controladas
- [ ] Informes y playbook
- [ ] Correcciones y nueva comprobación

## 9. Estructura del repositorio

```
CIVEX/
├── README.md                 ← Estás aquí: presentación del proyecto
└── docs/
    ├── explicacion-flujo-red.md   ← Cómo funciona la red, paso a paso
    ├── arquitectura.md       ← Redes, IPs, máquinas y firewall
```

## 10. Aviso

Todo el entorno es **ficticio y de laboratorio**. Las pruebas de seguridad solo se realizan sobre nuestras propias máquinas virtuales, con fines educativos. No hay datos reales de personas.

---

*Proyecto de ASIX · CIVEX · Versión 0.1 (provisional)*
