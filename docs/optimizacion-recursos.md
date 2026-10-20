# Optimización de recursos del PC 1 (Proxmox)

Propuesta para que todo el cliente (SonrisaViva) funcione con la menor RAM posible. **Es una propuesta: el esquema de red y `arquitectura.md` siguen sin cambios** hasta que el equipo decida.

> ⚠️ Las cifras marcadas como **(estimación)** son aproximaciones nuestras, no mediciones. Hay que comprobarlas en el PC real.

---

## 1. Primero: medir el PC

En el host Proxmox (PC 1):

```bash
free -h
lscpu | grep -E "Model name|^CPU\(s\)"
lsblk
df -h
```

Con esos datos se elige entre las opciones de abajo. La RAM total (8 GB o 16 GB) es lo que decide.

## 2. Qué consume la RAM

| Dato | Valor | Fuente |
|------|-------|--------|
| Proxmox VE en reposo (sin VMs) | ~1,5 – 2 GB | computingforgeeks |
| Contenedor LXC Ubuntu en reposo | ~68 MiB | computingforgeeks |
| VM Ubuntu de 2 GB en reposo | ~1.941 MiB | computingforgeeks |
| Wazuh todo-en-uno (1-25 agentes) | **8 GiB RAM, 4 vCPU, 50 GB disco** | documentación oficial de Wazuh |
| KSM con 8 VMs parecidas | de 13,1 GB a 6,8 GB (-48 %) | credativ |

> 💡 **Ejemplo:** un LXC es un piso que comparte instalaciones con el edificio (kernel del host); una VM es una casa independiente con su propia cocina y su propia caldera. La casa cuesta mucho más aunque esté vacía.

**Conclusión:** casi toda la RAM la gasta **WAZUH-01**. El resto de máquinas pesa poco. Cambiar el esquema de red no ahorra memoria, porque los bridges no consumen.

## 3. Decisiones por máquina

| Máquina | Propuesta | Motivo |
|---------|-----------|--------|
| **WAZUH-01** | Seguir como **VM Ubuntu 24.04** | Ubuntu está en la lista recomendada de Wazuh. Alpine no. En LXC exigiría ajustar `vm.max_map_count` en el host y hay problemas sin resolver. |
| **FW-01** | Seguir como VM Debian 12 | Es el perímetro: mejor aislado en VM. Bajar a ~1 GB con Suricata ajustado. |
| **WEB-01** | Seguir como **VM** pequeña (512 MB – 1 GB) | Es el objetivo de los ataques de Kali; un LXC comparte kernel con el host. |
| **CLINICA-01** | Opción: pasar a **LXC sin privilegios** | Base de datos interna; ahorra bastante RAM. Es una opción, no obligatoria. |
| **DNS-01, MON-01** | Se quedan como LXC | Ya son baratos. |

**Descartado:**

- **Alpine:** Wazuh no lo soporta, y en contenedores la diferencia con Debian es pequeña. Además usa musl, que da problemas de compatibilidad.
- **Docker:** no ahorra RAM. El Wazuh en Docker pide como mínimo 8 GB y 4 cores.

## 4. Ajustes concretos

### Host Proxmox

- **KSM** (deduplica memoria entre VMs parecidas):
  ```bash
  echo "scan-time" > /sys/kernel/mm/ksm/advisor_mode
  echo 1 > /sys/kernel/mm/ksm/run
  ```
  Es una red de seguridad, no un plan. Solo conviene si controlamos todas las VMs.
- **Ballooning:** activar con mínimo y máximo en las VMs ligeras. **No** en WAZUH-01 ni en CLINICA-01: si falta memoria, el sistema puede matar la base de datos o el indexer.
- **No asignar el 100 % de la RAM:** dejar libre un 10-15 %. Con sobreasignación, el host puede activar el OOM killer.
- **ZFS (solo si se usa):** limitar el ARC en `/etc/modprobe.d/zfs.conf`, por ejemplo `options zfs zfs_arc_max=2147483648`. Después, `update-initramfs -u -k all`.

### WAZUH-01

- En `/etc/wazuh-indexer/jvm.options`, poner `-Xms` y `-Xmx` con el **mismo valor**, como máximo la mitad de la RAM de la VM (regla de la comunidad de Wazuh, no de la documentación oficial).
- Si se usa Docker en algún momento: `vm.max_map_count=262144` en el host.

### FW-01 (Suricata)

Según la documentación de Suricata, estos valores multiplican la memoria:

- `af-packet.threads` (menos hilos, menos memoria)
- `af-packet.ring-size`
- `max-pending-packets`

Bajarlos reduce RAM, pero un ring pequeño provoca pérdida de paquetes. Ajustar midiendo.

## 5. Presupuesto de RAM (estimación)

| | 16 GB | 8 GB |
|---|---|---|
| Host Proxmox | 2 | 2 |
| WAZUH-01 | 6 | 3 |
| FW-01 | 2 | 1 |
| CLINICA-01 | 1,5 | 0,5 (LXC) |
| WEB-01 | 1 | 0,5 |
| DNS-01 + MON-01 | 1 | 0,6 |
| **Total** | **~13,5** | **~7,6** |

- **16 GB:** cabe con margen. Wazuh queda por debajo de los 8 GiB oficiales, así que hay que probarlo.
- **8 GB:** sin holgura. Habría que apagar MON-01 cuando no se use, o mover Wazuh a otro PC (siguiente apartado).

## 6. Opción: Wazuh en otro PC

Es viable y encaja con el proyecto: CIVEX es la empresa de seguridad y vigila al cliente desde fuera. Lo razonable sería el **PC 2 (Marc)**, junto a CIVEX-01. **No** en el PC 3: el atacante no debería alojar el SOC.

**Ventajas**

- Proxmox queda mucho más aliviado (unos 3-6 GB menos).
- Wazuh puede usar los 8 GiB recomendados, sin recortes.

**Cambios necesarios**

- WAZUH-01 pasa a tener IP en la red del aula (por ejemplo `<RED_AULA>.231`), con adaptador puente en VirtualBox.
- Los agentes de LAN-CLIENTE y DMZ salen por FW-01 hacia esa IP (puertos 1514 y 1515). Hoy la regla apunta a `10.10.10.30`.
- CIVEX-01 envía sus logs directamente, sin pasar por el redirect del firewall.
- Actualizar esquema, `arquitectura.md`, `explicacion-flujo-red.md` y las notas de backups.

**Inconvenientes**

- El PC 2 necesita RAM para CIVEX-01 (4 GB en el esquema) más Wazuh, y unos 50 GB de disco.
- Los logs dependen de la red del aula. Si el modo puente falla, hay que usar Red NAT y añadir los puertos de Wazuh.
- Se pierde el aislamiento "todo dentro del PC 1".
- Si el PC 2 se apaga, el SOC deja de funcionar.

**Recomendación:** moverlo solo si el PC 2 tiene al menos 16 GB. Si no, dejarlo en Proxmox con los ajustes del apartado 4.

## 7. Pendiente de decidir

- [ ] RAM real del PC 1 y del PC 2.
- [ ] ¿Wazuh se queda en Proxmox o pasa al PC 2?
- [ ] ¿CLINICA-01 como VM o como LXC?
- [ ] Probar el presupuesto de RAM con las máquinas encendidas.

## 8. Fuentes

- [Wazuh quickstart (requisitos)](https://documentation.wazuh.com/current/quickstart.html)
- [Wazuh en Docker](https://documentation.wazuh.com/current/deployment-options/docker/wazuh-container.html)
- [KSM y ballooning en Proxmox (credativ)](https://www.credativ.de/en/blog/credativ-inside/evaluate-ksm-and-ballooning-features-in-proxmox-ve/)
- [RAM en Proxmox homelab](https://computingforgeeks.com/how-much-ram-for-proxmox-homelab/)
- [Heap del Wazuh indexer (comunidad)](https://groups.google.com/g/wazuh/c/BF_FScLZrH8)
- [Suricata: tuning](https://docs.suricata.io/en/latest/performance/tuning-considerations.html)
- [Alpine vs Debian en LXC (foro Proxmox)](https://forum.proxmox.com/goto/post?id=447739)

---

*Documento del proyecto CIVEX · Propuesta de optimización · Versión 0.1 (provisional)*
