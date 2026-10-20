# Explicación del flujo de red de CIVEX

Este documento explica **cómo viaja la información** por la red del proyecto, paso a paso y con ejemplos, pensado para que lo entienda cualquier persona aunque no sepa de redes.

> Los detalles técnicos (IPs completas, tablas de máquinas y reglas) están en [`arquitectura.md`](arquitectura.md).
> `<RED_AULA>` es el prefijo de la red real de clase (por ejemplo `192.168.1`). Se confirmará al montar los equipos.

---

## 1. La idea en una frase

Hemos montado una **mini Internet** con tres ordenadores: uno hace de **cliente** (la clínica), otro de **nuestra empresa** (CIVEX) y otro de **atacante** (Kali). El cliente está protegido por un **firewall** y comprobamos que el atacante solo puede ver lo que debe ver.

## 2. Los tres PCs

| PC | Responsable | Papel | Sistema de virtualización |
|----|-------------|-------|---------------------------|
| **PC 1** | Felipe | Infraestructura del cliente (SonrisaViva) | **Proxmox VE** |
| **PC 2** | Marc | Empresa CIVEX (plataforma web, Firebase) | **VirtualBox** |
| **PC 3** | Alejandro | Atacante (Kali Linux) | **VirtualBox** |

La **red del aula** hace de "Internet": los tres PCs están conectados a ella y es el único punto en común.

```
                 RED DEL AULA  (hace de "Internet")
        ┌─────────────────┼──────────────────┐
        │                 │                  │
     PC 1               PC 2               PC 3
   Cliente              CIVEX              Kali
 (Proxmox)          (VirtualBox)        (VirtualBox)
```

## 3. Mini glosario (con ejemplos)

| Palabra | Qué es | Ejemplo cotidiano |
|---------|--------|-------------------|
| **Máquina virtual (VM)** | Un ordenador simulado dentro de otro. | Un piso dentro de un edificio. |
| **Proxmox / VirtualBox** | Programas que crean y gestionan las VMs. | El constructor del edificio. |
| **IP** | La "dirección" de un equipo en la red. | La dirección postal de una casa. |
| **Gateway (puerta de enlace)** | El equipo por el que se sale a otras redes. | La puerta de la calle. |
| **Firewall** | Decide qué tráfico pasa y cuál se bloquea. | El portero de un edificio. |
| **DMZ** | Zona intermedia para lo que debe verse desde fuera. | El recibidor de un edificio. |
| **NAT** | Los equipos internos salen a Internet con la IP del firewall. | Todos los pisos comparten la dirección del portal. |
| **DNAT** | El firewall redirige las visitas de fuera al equipo correcto. | El portero lleva al visitante al piso adecuado. |
| **Bridge (`vmbr`)** | Switch virtual dentro de Proxmox. | Un enchufe múltiple al que se conectan las VMs. |
| **Puerto (80, 443, 22...)** | "Puerta" concreta de un servicio. | Cada ventanilla de una oficina. |
| **DNS** | Traduce nombres a IPs. | La agenda de contactos del móvil. |
| **IDS (Suricata)** | Detecta tráfico sospechoso y avisa. | Una cámara de seguridad. |
| **SOC / Wazuh** | Recoge los registros (logs) y las alertas de todas las máquinas. | La central de alarmas. |
| **Log** | Registro de lo que ocurre en un equipo. | El diario de un guardia de seguridad. |

## 4. Las redes

| Red | Rango | Dónde está | Quién la gestiona |
|-----|-------|-----------|-------------------|
| **Aula** ("Internet") | `<RED_AULA>.0/24` | Switch de clase | Router del aula |
| **LAN-CLIENTE** | `10.10.10.0/24` | PC 1 (Proxmox) | FW-01 (`10.10.10.1`) |
| **DMZ** | `10.10.11.0/24` | PC 1 (Proxmox) | FW-01 (`10.10.11.1`) |
| **RED-CIVEX** | `10.10.20.0/24` | PC 2 (VirtualBox) | Privada, sin gateway |
| **RED-KALI** | `10.10.30.0/24` | PC 3 (VirtualBox) | Privada, sin gateway |

Cada PC tiene su **red propia y separada**. Las redes `10.10.x.x` son privadas: no se ven entre sí ni desde la red del aula, salvo lo que el firewall permita.

## 5. PC 1 (Proxmox): el cliente

### 5.1 Los tres bridges

Proxmox crea **switches virtuales** llamados bridges. Cada máquina se "enchufa" al que le corresponde.

| Bridge | Conectado a | Función |
|--------|-------------|---------|
| `vmbr0` | La tarjeta física del PC | Salida a la red del aula |
| `vmbr1` | Nada físico | **LAN-CLIENTE** (red interna) |
| `vmbr2` | Nada físico | **DMZ** |

Como `vmbr1` y `vmbr2` no están conectados a ningún cable, son **redes aisladas**. Para salir de ellas hay que pasar por el firewall.

### 5.2 El firewall (FW-01) está en medio de todo

Solo FW-01 está conectado a los tres bridges, con tres tarjetas de red:

```
Red del aula ─ vmbr0 ─┐   (.202)
                      │
                    FW-01 ─ vmbr1 ─ LAN-CLIENTE (10.10.10.1)
                      │               · DNS-01       10.10.10.10
                      │               · CLINICA-01   10.10.10.20
                      │               · WAZUH-01     10.10.10.30
                      │               · MON-01       10.10.10.40
                      │
                      └──── vmbr2 ─ DMZ (10.10.11.1)
                                      · WEB-01       10.10.11.10
```

> 💡 **Ejemplo:** el firewall es el portero de un edificio con dos zonas: las viviendas (LAN-CLIENTE) y el recibidor (DMZ). Quien viene de la calle solo habla con el portero. Él decide a quién deja pasar y adónde.

### 5.3 ¿Por qué Proxmox tiene la `.201` y el firewall la `.202`?

Son **dos equipos distintos**, aunque uno viva dentro del otro.

| | Qué es | IP en el aula | Para qué sirve |
|---|--------|---------------|----------------|
| **pve01** | El PC físico con Proxmox | `.201` | Administrar el servidor |
| **FW-01** | Una VM dentro de Proxmox | `.202` | Cara pública del cliente |

> 💡 **Ejemplo:** Proxmox es el edificio y FW-01 es un inquilino. El edificio tiene su dirección postal y el inquilino tiene su propio buzón, aunque vivan en el mismo sitio.

Visto desde la red del aula, **FW-01 es un equipo más**, como el PC de cualquier compañero. Kali ataca la `.202`, no la `.201`, porque un atacante real solo vería el perímetro de la empresa y no el panel de administración del servidor.

Además, Proxmox **no tiene IP** en `vmbr1` ni `vmbr2`, así que el host tampoco es alcanzable desde las redes internas.

## 6. PC 2 y PC 3 (VirtualBox): CIVEX y Kali

Cada VM tiene **dos adaptadores de red**, y cada uno cumple una función distinta:

| Adaptador | Para qué sirve | Ejemplo cotidiano |
|-----------|----------------|-------------------|
| **Adaptador 1 · Puente** | La VM se conecta a la red real del aula con su propia IP. | La puerta de la calle. |
| **Adaptador 2 · Solo anfitrión** | Red privada entre la VM y su PC. No sale a ningún sitio. | Una puerta interior de la casa. |

| VM | Adaptador 1 (puente) | Adaptador 2 (solo anfitrión) |
|----|----------------------|------------------------------|
| **CIVEX-01** | `<RED_AULA>.211` | `10.10.20.10` |
| **KALI-01** | `<RED_AULA>.221` | `10.10.30.10` |

**Aclaraciones importantes:**

- El modo **solo anfitrión no da salida** a Internet ni a la red del aula. Por eso necesitamos también el puente.
- En modo **puente** el PC **no hace de router**: actúa como un cable. La VM aparece en la red del aula como un equipo más.
- **Solo el adaptador 1 lleva gateway.** Si los dos lo llevaran, el tráfico podría salir por donde no debe.

```
Red del aula
   │
   ├── Adap.1 (puente) ── CIVEX-01 ── Adap.2 (solo anfitrión) ── RED-CIVEX 10.10.20.0/24
   │
   └── Adap.1 (puente) ── KALI-01  ── Adap.2 (solo anfitrión) ── RED-KALI  10.10.30.0/24
```

## 7. Los flujos, paso a paso

### Flujo 1 · Un visitante entra en la web de citas

1. Alguien de la red del aula abre `http://<RED_AULA>.202`.
2. La petición llega a **FW-01** (puerto 80 o 443).
3. FW-01 la **redirige (DNAT)** a **WEB-01** (`10.10.11.10`), en la DMZ.
4. WEB-01 responde y la respuesta vuelve por el mismo camino.

> 💡 El visitante cree que habla con `.202`, pero en realidad le atiende WEB-01. Es el portero llevándole al piso correcto.

### Flujo 2 · La web consulta la base de datos

1. WEB-01 necesita datos de pacientes (ficticios).
2. Pide la información a **CLINICA-01** (`10.10.10.20`) por el puerto **3306** (MariaDB).
3. FW-01 lo permite, porque es la **única conexión autorizada** de la DMZ hacia la red interna.

### Flujo 3 · Una máquina del cliente sale a Internet

1. Por ejemplo, CLINICA-01 quiere descargar actualizaciones.
2. La petición va a FW-01, que la deja salir por los puertos 80/443.
3. FW-01 aplica **NAT**: la petición sale con la IP `.202`.
4. La respuesta vuelve a FW-01, que la entrega a la máquina que la pidió.

### Flujo 4 · Resolución de nombres (DNS)

1. Una máquina quiere hablar con `clinica-01.sonrisaviva.local`.
2. Pregunta a **DNS-01** (`10.10.10.10`), que le dice la IP.
3. Si es un nombre de Internet, DNS-01 pregunta a servidores externos (1.1.1.1 y 9.9.9.9).

### Flujo 5 · Los logs llegan a Wazuh

1. Todas las máquinas Linux llevan un **agente de Wazuh**.
2. Los agentes envían sus registros a **WAZUH-01** (`10.10.10.30`), puertos 1514 y 1515.
3. FW-01 lleva además **Suricata**, que vigila el tráfico. Sus avisos también los recoge el agente de Wazuh.
4. **CIVEX-01** (PC 2) envía los suyos a la `.202` del firewall, y este los **redirige a WAZUH-01**.

> 💡 Cada máquina es un guardia que apunta lo que pasa en su diario (log). Wazuh es la central que lee todos los diarios a la vez.

### Flujo 6 · Monitorización

**MON-01** (`10.10.10.40`) pregunta cada pocos segundos a todas las máquinas cómo están (CPU, memoria...) por el puerto **9100**, y lo muestra en gráficas con Prometheus y Grafana.

### Flujo 7 · El ataque controlado de Kali

1. Desde **KALI-01** se lanza un escaneo o un ataque contra `<RED_AULA>.202`.
2. Kali **solo ve el firewall**. Las IPs `10.10.10.x` y `10.10.11.x` no son alcanzables desde fuera.
3. Solo puede llegar a la web (80/443) y, si fuera administrador, a SSH (22).
4. Suricata y Wazuh **registran la actividad**.
5. Con esos registros se genera el informe de vulnerabilidades.

> 💡 Un ladrón mirando un edificio solo ve el portal y al portero. No puede ir directamente a las viviendas.

### Flujo 8 · Qué pasa si la web es hackeada

La regla clave del firewall es **DMZ → LAN-CLIENTE: bloqueado** (salvo WEB-01 → CLINICA-01 por el puerto 3306). Si alguien consiguiera controlar WEB-01, no podría moverse libremente por la red interna ni llegar a Wazuh, al DNS ni al resto de servidores.

## 8. Reglas del firewall (resumen)

**Política por defecto:** bloquear todo lo que no esté permitido y registrar lo bloqueado.

| Qué se permite | Para qué |
|----------------|----------|
| Aula → FW-01 (80/443) → WEB-01 | Web pública de citas |
| Administrador → FW-01 (22) | Gestionar el firewall |
| CIVEX-01 → FW-01 (1514/1515) → WAZUH-01 | Logs de CIVEX-01 |
| LAN-CLIENTE y DMZ → Internet (80/443) | Actualizaciones |
| LAN-CLIENTE y DMZ → DNS-01 (53) | Resolución de nombres |
| LAN-CLIENTE y DMZ → WAZUH-01 (1514/1515) | Agentes de Wazuh |
| WEB-01 → CLINICA-01 (3306) | Web contra la base de datos |
| MON-01 → todas las VMs (9100) | Monitorización |
| **DMZ → LAN-CLIENTE** | **Bloqueado** |
| Cualquier otra cosa | **Bloqueado y registrado** |

## 9. Cómo comprobamos que funciona

| Prueba | Resultado esperado |
|--------|--------------------|
| Desde Kali: `curl http://<RED_AULA>.202` | Se muestra la web de WEB-01. |
| Desde Kali: `nmap <RED_AULA>.202` | Solo aparecen los puertos 22, 80 y 443. |
| Desde Kali: `ping 10.10.10.20` | **Falla**: la red del cliente no está expuesta. |
| WEB-01 → CLINICA-01 puerto 3306 | Funciona. |
| WEB-01 → WAZUH-01 puerto 22 | **Bloqueado**. |
| Panel de Wazuh | Aparecen las alertas generadas por las pruebas. |

## 10. Preguntas frecuentes

**¿Por qué una DMZ?**
Porque la web es lo único expuesto. Si la hackean, el atacante queda aislado de la base de datos y de Wazuh.

**¿Por qué Kali no hace ping a `10.10.10.20`?**
Porque esa red es privada y solo se llega a ella a través del firewall. Que falle el ping demuestra que el diseño funciona.

**¿Por qué no usamos VLANs?**
Cada red es un bridge de Proxmox independiente. Es más simple y se ve mejor en el esquema.

**¿Por qué usamos modo puente y no NAT en VirtualBox?**
Es más realista: Kali ataca desde una IP propia de la red del aula, como haría un atacante externo.

**¿Y si la red del aula bloquea el modo puente?**
Se cambia a Red NAT en VirtualBox con reenvío de puertos y se actualiza el esquema.

**¿Suricata bloquea los ataques?**
No, está en modo IDS: solo detecta y avisa. Sus eventos se envían a Wazuh.

**¿Qué pasa con los backups?**
Proxmox hace una copia diaria de las VMs del cliente, guardando 3 diarias y 2 semanales, en un disco distinto al del sistema.

---

<img src="../img/Esquemadered.png" height="600" width="auto">

*Documento del proyecto CIVEX · Versión 0.1 (provisional)*
