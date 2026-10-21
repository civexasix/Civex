# Optimización de recursos del PC 1 (Proxmox)

El PC 1 tiene **8 GB de RAM confirmados**. Este documento explica cómo repartirlos entre las máquinas del cliente (SonrisaViva) y por qué **WAZUH-01 se ha movido al PC 2**.

> ⚠️ Las cifras marcadas como **(estimación)** son aproximaciones nuestras, no mediciones. Hay que comprobarlas con las máquinas encendidas.

---

## 1. Punto de partida

- **RAM del PC 1:** 8 GB (confirmado).
- Para ver el resto del hardware, en el host Proxmox:

```bash
free -h
lscpu | grep -E "Model name|^CPU\(s\)"
lsblk
df -h
```

## 2. Qué consume la RAM

| Dato | Valor | Fuente |
|------|-------|--------|
| Proxmox VE en reposo (sin VMs) | ~1,5 – 2 GB | computingforgeeks |
| Contenedor LXC Ubuntu en reposo | ~68 MiB | computingforgeeks |
| VM Ubuntu de 2 GB en reposo | ~1.941 MiB | computingforgeeks |
| Wazuh todo-en-uno (1-25 agentes) | **8 GiB RAM, 4 vCPU, 50 GB disco** | documentación oficial de Wazuh |
| KSM con 8 VMs parecidas | de 13,1 GB a 6,8 GB (-48 %) | credativ |

> 💡 **Ejemplo:** un LXC es un piso que comparte instalaciones con el edificio (kernel del host); una VM es una casa independiente con su propia cocina y su propia caldera. La casa cuesta mucho más aunque esté vacía.

**Conclusión:** Wazuh por sí solo pide tanta RAM como todo el PC 1. Con 8 GB no cabía junto al resto sin recortes arriesgados, así que se mueve al PC 2 (apartado 6). Cambiar el esquema de red no ahorra memoria, porque los bridges no consumen.

## 3. Decisiones por máquina (PC 1)

| Máquina | Decisión | Motivo |
|---------|----------|--------|
| **FW-01** | VM Debian 12 | Es el perímetro: mejor aislado en VM. Se puede bajar a ~1 GB ajustando Suricata. |
| **CLINICA-01** | VM Ubuntu 24.04 | Con Wazuh fuera sobra RAM, así que no hace falta pasarla a LXC. |
| **WEB-01** | VM pequeña (512 MB – 1 GB) | Es el objetivo de los ataques de Kali; un LXC comparte kernel con el host. |
| **DNS-01, MON-01** | LXC | Son baratos en memoria. |
| **WAZUH-01** | Se traslada al **PC 2** | Ver apartado 6. |

**Descartado:**

- **Alpine:** Wazuh no lo soporta (recomienda Ubuntu, entre otros), y en contenedores la diferencia con Debian es pequeña. Además usa musl, que da problemas de compatibilidad.
- **Docker:** no ahorra RAM. El Wazuh en Docker pide como mínimo 8 GB y 4 cores.

## 4. Presupuesto de RAM del PC 1 (estimación)

Sin Wazuh en este PC:

| Componente | Tipo | RAM asignada (GB) |
|------------|------|-------------------|
| Host Proxmox | — | 2 |
| FW-01 | VM | 1 – 2 |
| CLINICA-01 | VM | 1 |
| WEB-01 | VM | 0,75 |
| DNS-01 | LXC | 0,25 |
| MON-01 | LXC | 0,75 |
| **Total asignado** | | **5,75 – 6,75** |
| **Libre de los 8 GB** | | **2,25 – 1,25** |

- **Sobra margen.** Incluso en el peor caso (FW-01 con 2 GB, como indica el esquema) quedan unos 1,25 GB libres, un ~16 %, por encima del 10-15 % que se recomienda dejar sin asignar. Si Suricata cabe en 1 GB, el margen sube a ~2,25 GB.
- Con Wazuh dentro de este PC habría hecho falta sumar entre 3 GB (muy recortado) y 8 GiB (lo recomendado), y el total habría superado los 8 GB.
- El consumo real será menor que lo asignado, porque las máquinas no usan toda su RAM a la vez.

## 5. Ajustes concretos

### Host Proxmox

- **KSM:** Proxmox lo trae **activado por defecto**. En CIVEX lo dejamos activado por el ahorro de RAM entre VMs parecidas. Si hiciera falta excluir una VM concreta:
  ```bash
  qm set <vmid> --allow-ksm 0
  ```
  Es una red de seguridad, no un plan. Según la fuente, conviene tenerlo activado cuando controlamos todas las VMs, que es nuestro caso.
- **Ballooning:** activar con mínimo y máximo solo en las VMs ligeras. **No** en CLINICA-01: si falta memoria, el sistema puede matar la base de datos.
- **No asignar el 100 % de la RAM:** dejar libre un 10-15 %. Con sobreasignación, el host puede activar el OOM killer.
- **ZFS (solo si se usa):** limitar el ARC en `/etc/modprobe.d/zfs.conf`, por ejemplo `options zfs zfs_arc_max=2147483648`. Después, `update-initramfs -u -k all`.

### FW-01 (Suricata)

Según la documentación de Suricata, estos valores multiplican la memoria:

- `af-packet.threads` (menos hilos, menos memoria)
- `af-packet.ring-size`
- `max-pending-packets`

Bajarlos reduce RAM, pero un ring pequeño provoca pérdida de paquetes. Ajustar midiendo.

## 6. WAZUH-01 en el PC 2

WAZUH-01 pasa a ser una **VM Ubuntu Server 24.04 en el PC 2 (CIVEX, VirtualBox)**, dentro de **RED-CIVEX** con la IP `10.10.20.30`. Encaja con el proyecto: CIVEX es la empresa de seguridad y vigila al cliente desde su propia red. No va en el PC 3, porque el atacante no debería alojar el SOC.

**Cómo llegan los logs**

1. Los agentes de LAN-CLIENTE y DMZ (y el de FW-01) envían sus logs a `10.10.20.30`, puertos 1514 y 1515.
2. FW-01 los saca por su interfaz WAN, con NAT, hacia `<RED_AULA>.211` (CIVEX-01), que actúa de intermediario.
3. CIVEX-01 reenvía solo esos puertos hacia `10.10.20.30`.
4. CIVEX-01 habla con WAZUH-01 directamente, porque están en la misma red.

El detalle de reglas está en [`arquitectura.md`](arquitectura.md).

**Requisitos**

- La recomendación oficial para 1-25 agentes es **8 GiB de RAM, 4 vCPU y 50 GB de disco**. Con nuestras pocas máquinas debería bastar.
- El PC 2 también aloja CIVEX-01 (4 GB en el esquema). Hay que comprobar que su RAM da para las dos VMs.
- Si la RAM del PC 2 va justa, se puede dar menos a WAZUH-01 y bajar el heap del indexer: en `/etc/wazuh-indexer/jvm.options`, `-Xms` y `-Xmx` con el **mismo valor**, como máximo la mitad de la RAM de la VM (regla de la comunidad de Wazuh, no de la documentación oficial).
- La red RED-CIVEX es solo anfitrión y no tiene salida a Internet. Para instalar y actualizar WAZUH-01 hay que darle un adaptador NAT temporal.

**A tener en cuenta**

- Los logs dependen de la red del aula. Si el modo puente falla, hay que usar Red NAT en VirtualBox y añadir los puertos de Wazuh.
- Si el PC 2 se apaga, el SOC deja de funcionar.
- WAZUH-01 ya no entra en los backups de Proxmox.
- Se pierde el aislamiento "todo dentro del PC 1".

## 7. Pendiente de decidir

- [ ] RAM, CPU y disco reales del PC 2.
- [ ] Cómo hacer copia de seguridad de WAZUH-01 al estar fuera de Proxmox.
- [ ] Probar el presupuesto de RAM del PC 1 con las máquinas encendidas.
- [ ] Actualizar `img/Esquemadered.png` con la nueva ubicación de WAZUH-01.

## 8. Fuentes

- [Wazuh quickstart (requisitos)](https://documentation.wazuh.com/current/quickstart.html)
- [Wazuh en Docker](https://documentation.wazuh.com/current/deployment-options/docker/wazuh-container.html)
- [KSM y ballooning en Proxmox (credativ)](https://www.credativ.de/en/blog/credativ-inside/evaluate-ksm-and-ballooning-features-in-proxmox-ve/)
- [RAM en Proxmox homelab](https://computingforgeeks.com/how-much-ram-for-proxmox-homelab/)
- [Heap del Wazuh indexer (comunidad)](https://groups.google.com/g/wazuh/c/BF_FScLZrH8)
- [Suricata: tuning](https://docs.suricata.io/en/latest/performance/tuning-considerations.html)
- [Alpine vs Debian en LXC (foro Proxmox)](https://forum.proxmox.com/goto/post?id=447739)

---

*Documento del proyecto CIVEX · Optimización de recursos · Versión 0.1 (provisional)*
