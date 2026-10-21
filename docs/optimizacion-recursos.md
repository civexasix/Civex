# Optimización de recursos del PC 1 (Proxmox)

El PC 1 tiene **8 GB de RAM**. Hemos investigado cómo repartirlos entre las máquinas del cliente (SonrisaViva) y hemos llegado a la conclusión de que Wazuh no cabe cómodamente ahí, así que **hemos decidido poner WAZUH-01 en el PC 2**.

> ⚠️ **Todavía no hemos montado ni medido nada.** Las cifras con fuente salen de documentación y artículos que hemos leído (apartado 7). Las marcadas como **(estimación)** son cálculos nuestros. Habrá que comprobarlas cuando tengamos las máquinas en marcha.
>
> Los términos que pueden resultar nuevos (KSM, ballooning, ARC...) están en el [glosario](#6-glosario).

---

## 1. Qué hemos investigado

| Dato | Valor | Fuente |
|------|-------|--------|
| Proxmox VE en reposo (sin VMs) | ~1,5 – 2 GB | computingforgeeks |
| Contenedor LXC Ubuntu en reposo | ~68 MiB | computingforgeeks |
| VM Ubuntu de 2 GB en reposo | ~1.941 MiB | computingforgeeks |
| Wazuh todo-en-uno (1-25 agentes) | 8 GiB de RAM, 4 vCPU, 50 GB de disco | documentación oficial de Wazuh |
| KSM con 8 VMs parecidas | de 13,1 GB a 6,8 GB (-48 %) | credativ |

> 💡 **Ejemplo:** un LXC es un piso que comparte instalaciones con el edificio (el kernel del host); una VM es una casa independiente con su propia cocina y su propia caldera. La casa cuesta mucho más aunque esté vacía.

**Conclusión:** Wazuh por sí solo pide tanta RAM como todo el PC 1. Con 8 GB no cabría junto al resto sin recortes arriesgados, así que lo movemos al PC 2 (apartado 5). Cambiar el esquema de red no ahorra memoria, porque los bridges no consumen.

## 2. Decisiones por máquina (PC 1)

| Máquina | Decisión | Motivo |
|---------|----------|--------|
| **FW-01** | VM Debian 12 | Es el perímetro: mejor aislado en VM. Quizá se pueda bajar a ~1 GB ajustando Suricata (habrá que probarlo). |
| **CLINICA-01** | VM Ubuntu 24.04 | Con Wazuh fuera sobra RAM, así que no hace falta pasarla a LXC. |
| **WEB-01** | VM pequeña (512 MB – 1 GB) | Es el objetivo de los ataques de Kali; un LXC comparte kernel con el host. |
| **DNS-01, MON-01** | LXC | Gastan poca memoria. |
| **WAZUH-01** | En el PC 2 | Ver apartado 5. |

**Descartado:**

- **Alpine:** Wazuh no lo soporta (recomienda Ubuntu, entre otros), y en contenedores la diferencia con Debian es pequeña. Además da más problemas de compatibilidad con algunos programas.
- **Docker:** no ahorra RAM. El Wazuh en Docker pide como mínimo 8 GB y 4 cores.

## 3. Presupuesto de RAM del PC 1 (estimación)

Solo lo que correría en este PC: Proxmox, FW-01, CLINICA-01, WEB-01, DNS-01 y MON-01.

| Componente | Tipo | RAM asignada (GB) |
|------------|------|-------------------|
| Host Proxmox | — | 2 |
| FW-01 | VM | 2 |
| CLINICA-01 | VM | 1 |
| WEB-01 | VM | 0,75 |
| DNS-01 | LXC | 0,25 |
| MON-01 | LXC | 0,75 |
| **Total asignado** | | **6,75** |
| **Libre de los 8 GB** | | **1,25 (~16 %)** |

- **Sin Wazuh en este PC sobra margen.** La tabla es el peor caso, con FW-01 en 2 GB como indica el esquema. Aun así quedan unos 1,25 GB sin asignar, por encima del 10-15 % que se recomienda dejar libre. Si FW-01 funciona bien con 1 GB, el margen sube a unos 2,25 GB.
- **El consumo real debería ser menor que lo asignado,** porque las máquinas no usan toda su RAM a la vez.
- **Puede haber menos margen** si la RAM utilizable resulta algo menor que 8 GB o si el disco usa ZFS, que también gasta RAM como caché.
- **Son cálculos sobre el papel.** Hay que medirlo con las máquinas encendidas antes de darlo por bueno.

## 4. Ideas para ahorrar memoria

Son cosas que pensamos probar. Todavía no están aplicadas.

- **KSM:** hace que el sistema guarde una sola copia de la memoria idéntica entre VMs. Proxmox lo permite por defecto en cada VM (lo hemos visto en su documentación) y creemos que viene activado en el host, aunque habrá que confirmarlo. Nuestra idea es dejarlo activado por el ahorro de RAM. Si alguna VM diera problemas, se puede excluir con `qm set <vmid> --allow-ksm 0`, donde `<vmid>` es el número de la VM.
- **Ballooning:** una VM devuelve al host la RAM que no usa. Se configura con un mínimo y un máximo. Pensamos usarlo solo en las VMs ligeras y **no** en CLINICA-01, porque una fuente avisa de que puede perjudicar a las bases de datos.
- **No asignar toda la RAM:** dejar libre un 10-15 %. Una fuente lo recomienda para que el host tenga sitio al hacer backups, y en una prueba de credativ asignar más memoria de la que había hizo saltar el OOM killer del host.
- **Suricata (FW-01):** su documentación dice que la memoria que reserva depende de cuántos hilos y qué tamaño de buffer se le configuren. Se podrá reducir, con cuidado de no perder paquetes. Lo ajustaremos al montarlo.

## 5. WAZUH-01 en el PC 2

WAZUH-01 estará en el **PC 2** (CIVEX, VirtualBox), en la red `10.10.20.0/24` (IP `10.10.20.30`). Los agentes del PC 1 (LAN-CLIENTE, DMZ y FW-01) enviarán los logs **a través de FW-01**, que los sacará hacia CIVEX-01, y este los reenviará a WAZUH-01. El detalle está en [`arquitectura.md`](arquitectura.md).

A tener presente:

- La documentación oficial recomienda para 1-25 agentes 8 GiB de RAM, 4 vCPU y 50 GB de disco. El PC 2 también aloja CIVEX-01, y **no hemos comprobado** que le quepan las dos VMs. Si va justo, habrá que darle menos memoria a WAZUH-01 o ajustar su configuración, y eso está por investigar.
- Si el PC 2 se apaga, el SOC deja de funcionar. Además, WAZUH-01 no entrará en los backups de Proxmox.

## 6. Glosario

| Término | Qué es, con palabras sencillas |
|---------|--------------------------------|
| **Host** | El PC físico donde está instalado Proxmox. Las VMs y los contenedores son sus "invitados". |
| **Kernel** | El núcleo del sistema operativo: la parte que reparte la memoria, el procesador y los discos entre los programas. |
| **vCPU** | Un núcleo de procesador virtual que se le da a una VM. |
| **GB y GiB** | 1 GB son 1.000 MB y 1 GiB son 1.024 MiB. La diferencia es pequeña, pero algunas fuentes usan GiB. |
| **KSM** | *Kernel Samepage Merging*. Si varias VMs tienen en memoria trozos idénticos, solo se guarda una copia compartida. 💡 Como tres alumnos con el mismo libro: en vez de tres copias, hay una y los tres la consultan. Gasta algo de CPU, y una fuente avisa de posibles riesgos de seguridad en entornos compartidos. |
| **Ballooning** | Un programa dentro de la VM "infla un globo" que ocupa la RAM sin usar para devolvérsela al host. Si se exagera, la VM se queda corta de memoria, por eso se fijan un mínimo y un máximo. |
| **OOM killer** | *Out Of Memory killer*. Cuando a un sistema se le acaba la RAM, el kernel elige un programa y lo mata para no caerse entero. Puede ser justo la base de datos. |
| **ZFS y ARC** | ZFS es un sistema de archivos avanzado. El ARC es la parte de la RAM que usa para recordar lo que ha leído del disco, y por defecto puede ocupar bastante. |
| **IDS y Suricata** | Un IDS vigila el tráfico de red y avisa si ve algo sospechoso, pero no lo bloquea. Suricata es el que usamos, dentro de FW-01. |
| **Agente de Wazuh** | Un programa pequeño instalado en cada máquina que lee sus logs y los envía a Wazuh. |
| **SOC** | Centro de control de seguridad. Aquí es WAZUH-01: recoge y analiza los logs de todas las máquinas. |

## 7. Fuentes

- [Wazuh quickstart (requisitos)](https://documentation.wazuh.com/current/quickstart.html)
- [Wazuh en Docker](https://documentation.wazuh.com/current/deployment-options/docker/wazuh-container.html)
- [KSM y ballooning en Proxmox (credativ)](https://www.credativ.de/en/blog/credativ-inside/evaluate-ksm-and-ballooning-features-in-proxmox-ve/)
- [Proxmox: página del comando `qm` (opción `allow-ksm`)](https://pve.proxmox.com/pve-docs/qm.1.html)
- [RAM en Proxmox homelab](https://computingforgeeks.com/how-much-ram-for-proxmox-homelab/)
- [Suricata: tuning](https://docs.suricata.io/en/latest/performance/tuning-considerations.html)
- [Alpine vs Debian en LXC (foro Proxmox)](https://forum.proxmox.com/goto/post?id=447739)

---

## Pendiente de decidir

- [ ] Cómo hacer copia de seguridad de WAZUH-01 al estar fuera de Proxmox.
- [ ] Probar el presupuesto de RAM del PC 1 cuando esté montado.
- [ ] Comprobar si el disco del PC 1 usa ZFS.
- [ ] Actualizar `img/Esquemadered.png` con la nueva ubicación de WAZUH-01.

*Documento del proyecto CIVEX · Optimización de recursos · Versión 0.1 (provisional)*
