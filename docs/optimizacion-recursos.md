# Optimización de recursos del PC 1 (Proxmox)

El PC 1 tiene **8 GB de RAM confirmados**. Este documento explica cómo repartirlos entre las máquinas del cliente (SonrisaViva) y por qué **WAZUH-01 se ha movido al PC 2**.

> ⚠️ **Cómo leer las cifras:** las que llevan fuente salen de documentación o artículos externos (apartado 9), no de nuestras máquinas. Las marcadas como **(estimación)** son aproximaciones nuestras. Nada de esto está medido todavía en el hardware real, así que no se puede asegurar que funcione hasta probarlo.
>
> Si no conoces algún término (KSM, ballooning, ARC...), está explicado en el [glosario](#8-glosario).

---

## 1. Punto de partida

- **RAM del PC 1:** 8 GB (confirmado).
- Para ver el resto del hardware, en el host Proxmox:

```bash
free -h
lscpu | grep -E "Model name|^CPU\(s\)"
lsblk
df -h
zpool list    # si da error, el disco no usa ZFS
```

Usa la RAM que muestre `free -h` para calcular, no la de la etiqueta: una de las fuentes avisa de que la memoria utilizable es algo menor que la nominal.

## 2. Qué consume la RAM

| Dato | Valor | Fuente |
|------|-------|--------|
| Proxmox VE en reposo (sin VMs) | ~1,5 – 2 GB | computingforgeeks |
| Contenedor LXC Ubuntu en reposo | ~68 MiB | computingforgeeks |
| VM Ubuntu de 2 GB en reposo | ~1.941 MiB | computingforgeeks |
| Wazuh todo-en-uno (1-25 agentes) | **8 GiB RAM, 4 vCPU, 50 GB disco** | documentación oficial de Wazuh |
| KSM con 8 VMs parecidas | de 13,1 GB a 6,8 GB (-48 %) | credativ |

> 💡 **Ejemplo:** un LXC es un piso que comparte instalaciones con el edificio (el kernel del host); una VM es una casa independiente con su propia cocina y su propia caldera. La casa cuesta mucho más aunque esté vacía.

**Conclusión:** Wazuh por sí solo pide tanta RAM como todo el PC 1. Con 8 GB no cabía junto al resto sin recortes arriesgados, así que se ha movido al PC 2 (apartado 6). Cambiar el esquema de red no ahorra memoria, porque los bridges no consumen.

## 3. Decisiones por máquina (PC 1)

| Máquina | Decisión | Motivo |
|---------|----------|--------|
| **FW-01** | VM Debian 12 | Es el perímetro: mejor aislado en VM. Se podría bajar a ~1 GB ajustando Suricata (por comprobar). |
| **CLINICA-01** | VM Ubuntu 24.04 | Con Wazuh fuera sobra RAM, así que no hace falta pasarla a LXC. |
| **WEB-01** | VM pequeña (512 MB – 1 GB) | Es el objetivo de los ataques de Kali; un LXC comparte kernel con el host. |
| **DNS-01, MON-01** | LXC | Son baratos en memoria. |
| **WAZUH-01** | Ya no está en el PC 1 | Ver apartado 6. |

**Descartado:**

- **Alpine:** Wazuh no lo soporta (recomienda Ubuntu, entre otros), y en contenedores la diferencia con Debian es pequeña. Además usa musl, una librería base distinta de la habitual, que da problemas de compatibilidad.
- **Docker:** no ahorra RAM. El Wazuh en Docker pide como mínimo 8 GB y 4 cores.

## 4. Presupuesto de RAM del PC 1 (estimación)

Solo lo que corre en este PC: Proxmox, FW-01, CLINICA-01, WEB-01, DNS-01 y MON-01.

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

- **Ahora sobra margen.** Esta tabla es el peor caso: FW-01 con 2 GB, como indica el esquema. Aun así quedan unos 1,25 GB sin asignar, por encima del 10-15 % que se recomienda reservar (0,8-1,2 GB en un PC de 8 GB). Si Suricata funciona bien con 1 GB, FW-01 baja a 1 GB y el margen sube a unos 2,25 GB.
- **El consumo real será menor que lo asignado,** porque las máquinas no usan toda su RAM a la vez.
- **Dos cosas pueden reducir el margen:** que `free -h` muestre menos de 8 GB (con 7,5 GiB, por ejemplo, el peor caso baja a ~0,75 GB y convendría dejar FW-01 en 1 GB) y que el disco use ZFS, porque su caché (ARC) se suma al consumo del host.
- **Son estimaciones.** Hay que medirlo con las máquinas encendidas antes de darlo por bueno.

## 5. Ajustes concretos

### Host Proxmox

- **KSM** (el sistema detecta trozos de memoria idénticos entre VMs y guarda una sola copia compartida).
  - Cada VM lo permite por defecto: la opción `allow-ksm` vale 1 (confirmado en la documentación de `qm`). Según el equipo, Proxmox lo trae activado por defecto en el host; la documentación que hemos revisado no lo confirma, así que conviene comprobarlo. Para ver si está compartiendo memoria: `watch cat /sys/kernel/mm/ksm/pages_sharing` (cada página son 4096 bytes).
  - En CIVEX lo dejamos **activado** por el ahorro de RAM entre VMs parecidas.
  - Si hiciera falta **excluir una VM concreta** del KSM, se hace con:
    ```bash
    qm set <vmid> --allow-ksm 0
    ```
    `<vmid>` es el número de la VM (se ve en la interfaz de Proxmox o con `qm list`).
  - Es una ayuda, no un plan: el ahorro depende de que las VMs se parezcan. Una de las fuentes recomienda tenerlo activado cuando controlamos todas las VMs, que es nuestro caso.
- **Ballooning** (una VM devuelve al host la RAM que no usa).
  - Se configura en la memoria de cada VM, con un mínimo y un máximo. Conviene activarlo solo en las VMs ligeras.
  - **No** en CLINICA-01: si el sistema se queda sin memoria, puede matar la base de datos. Para desactivarlo en una VM: `qm set <vmid> --balloon 0`.
  - En una prueba de credativ solo empezó a recuperar memoria cuando al host le quedaba cerca de un 15 % libre.
- **No asignar el 100 % de la RAM:** dejar libre un 10-15 %. Una fuente lo recomienda para que el host tenga sitio al hacer backups, y en una prueba de credativ sobreasignar memoria hizo saltar el OOM killer del host.
- **ZFS (solo si el disco lo usa):** limitar el ARC, la caché de lectura que ZFS guarda en RAM, en `/etc/modprobe.d/zfs.conf`. Por ejemplo, para 1 GiB: `options zfs zfs_arc_max=1073741824`. Después hay que ejecutar `update-initramfs -u -k all` y reiniciar (si el sistema está instalado sobre ZFS), o el límite se ignora. Ese límite cuenta como consumo del host.

### FW-01 (Suricata)

Suricata captura el tráfico con `af-packet`. Según su documentación, estos valores multiplican la memoria que reserva:

- `af-packet.threads`: cuántos hilos trabajan en paralelo (menos hilos, menos memoria).
- `af-packet.ring-size`: tamaño del buffer de cada hilo, donde esperan los paquetes capturados.
- `max-pending-packets`: cuántos paquetes puede tener en proceso a la vez cada hilo.

Bajarlos reduce la RAM, pero con un buffer pequeño se pueden perder paquetes cuando hay mucho tráfico. Hay que ajustarlo midiendo.

## 6. WAZUH-01 en el PC 2

WAZUH-01 ya **no está en el PC 1**: se ha movido al **PC 2** (CIVEX, VirtualBox), a la red `10.10.20.0/24` (IP `10.10.20.30`). Los agentes del PC 1 (LAN-CLIENTE, DMZ y FW-01) le envían los logs **a través de FW-01**, que los saca hacia CIVEX-01, y este los reenvía a WAZUH-01. El detalle de las reglas está en [`arquitectura.md`](arquitectura.md).

A tener presente:

- La documentación oficial recomienda para 1-25 agentes **8 GiB de RAM, 4 vCPU y 50 GB de disco**. El PC 2 también aloja CIVEX-01, y **no hemos verificado** que le quepan las dos VMs. Si va justo, se puede bajar el heap del indexer (ver glosario).
- Al montarlo, hay que comprobar si el indexer pide `vm.max_map_count`. La documentación de Wazuh lo exige para Docker; no hemos comprobado si lo pide en una instalación normal.
- Si el PC 2 se apaga, el SOC deja de funcionar. WAZUH-01 tampoco entra ya en los backups de Proxmox.

## 7. Pendiente de decidir

- [ ] Cómo hacer copia de seguridad de WAZUH-01 al estar fuera de Proxmox.
- [ ] Probar el presupuesto de RAM del PC 1 con las máquinas encendidas.
- [ ] Comprobar si el disco del PC 1 usa ZFS y, en ese caso, fijar el límite del ARC.
- [ ] Actualizar `img/Esquemadered.png` con la nueva ubicación de WAZUH-01.

## 8. Glosario

| Término | Qué es, con palabras sencillas |
|---------|--------------------------------|
| **Host** | El PC físico donde está instalado Proxmox. Las VMs y los contenedores son sus "invitados". |
| **Kernel** | El núcleo del sistema operativo: la parte que reparte la memoria, el procesador y los discos entre los programas. |
| **vCPU** | Un núcleo de procesador virtual que se le da a una VM. |
| **GB y GiB** | 1 GB son 1.000 MB y 1 GiB son 1.024 MiB. La diferencia es pequeña, pero por eso algunas cifras salen en GiB. |
| **Sobreasignación** | Darles a las VMs más RAM de la que tiene el host, apostando a que no la usarán toda a la vez. Si se equivoca la apuesta, el host se queda sin memoria. |
| **KSM** | *Kernel Samepage Merging*. Si varias VMs tienen en memoria trozos idénticos, solo guarda una copia compartida. 💡 Como tres alumnos con el mismo libro: en vez de tres copias, hay una y los tres la consultan. Gasta algo de CPU, y existe investigación sobre ataques que aprovechan esta deduplicación. |
| **Ballooning** | Un programa dentro de la VM "infla un globo" que ocupa la RAM sin usar para devolvérsela al host. Si se exagera, la VM se queda corta de memoria, por eso se fijan un mínimo y un máximo. |
| **OOM killer** | *Out Of Memory killer*. Cuando a un sistema se le acaba la RAM, el kernel elige un programa y lo mata para no caerse entero. Puede ser justo la base de datos. Pasa tanto en el host como dentro de una VM. |
| **ZFS y ARC** | ZFS es un sistema de archivos avanzado. El ARC es la parte de la RAM que usa para recordar lo que ha leído del disco. Por defecto puede coger mucha, y `zfs_arc_max` le pone un tope en bytes. Si no usamos ZFS, no aplica. |
| **`update-initramfs`** | Regenera la imagen con la que arranca el sistema. Hace falta para que el límite del ARC se aplique cuando el sistema está instalado sobre ZFS. |
| **IDS y Suricata** | Un IDS vigila el tráfico de red y avisa si ve algo sospechoso, pero no lo bloquea. Suricata es el que usamos, dentro de FW-01. |
| **`af-packet`** | La forma que tiene Suricata, en Linux, de leer los paquetes que pasan por una tarjeta de red. Sus ajustes (`threads`, `ring-size`) controlan cuánta memoria reserva. |
| **Buffer (`ring-size`)** | Una cola donde esperan los paquetes capturados hasta que Suricata los procesa. Si se llena, se descartan paquetes. |
| **Agente de Wazuh** | Un programa pequeño instalado en cada máquina que lee sus logs y los envía a Wazuh (puertos 1514 y 1515). |
| **SOC** | Centro de control de seguridad. Aquí es WAZUH-01: recoge y analiza los logs de todas las máquinas. |
| **Indexer** | La parte de Wazuh que guarda las alertas y permite buscar en ellas. Está hecho con Java. |
| **Heap del indexer** | La memoria que reserva un programa Java para sus datos. En `jvm.options`, `-Xms` es el tamaño inicial y `-Xmx` el máximo. Se ponen **iguales**, y como máximo la mitad de la RAM de la VM, para dejar el resto al sistema (regla de la comunidad de Wazuh, no de la documentación oficial). |
| **`vm.max_map_count`** | Un ajuste del kernel que limita cuántas zonas de memoria puede reservar un programa a la vez. Por defecto es 65530 y el indexer necesita más (la documentación de Wazuh indica 262144 para Docker). Se cambia con `sysctl -w vm.max_map_count=262144`, y para que se mantenga tras reiniciar se guarda en un fichero de `/etc/sysctl.d/`. |
| **NAT** | El equipo que enruta cambia la IP de origen de los paquetes por la suya. Al salir por FW-01, los paquetes llevan la IP `.202`. |

## 9. Fuentes

- [Wazuh quickstart (requisitos)](https://documentation.wazuh.com/current/quickstart.html)
- [Wazuh en Docker](https://documentation.wazuh.com/current/deployment-options/docker/wazuh-container.html)
- [KSM y ballooning en Proxmox (credativ)](https://www.credativ.de/en/blog/credativ-inside/evaluate-ksm-and-ballooning-features-in-proxmox-ve/)
- [Proxmox: página del comando `qm` (opciones `allow-ksm` y `balloon`)](https://pve.proxmox.com/pve-docs/qm.1.html)
- [Proxmox: gestión dinámica de memoria (KSM y ballooning)](https://pve.proxmox.com/wiki/Dynamic_Memory_Management)
- [RAM en Proxmox homelab](https://computingforgeeks.com/how-much-ram-for-proxmox-homelab/)
- [Heap del Wazuh indexer (comunidad)](https://groups.google.com/g/wazuh/c/BF_FScLZrH8)
- [Suricata: tuning](https://docs.suricata.io/en/latest/performance/tuning-considerations.html)
- [Alpine vs Debian en LXC (foro Proxmox)](https://forum.proxmox.com/goto/post?id=447739)

---

*Documento del proyecto CIVEX · Optimización de recursos · Versión 0.1 (provisional)*
