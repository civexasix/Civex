# Arquitectura de red (versión provisional)

Resumen del diseño técnico de CIVEX. Es la **versión 1**: puede cambiar durante el montaje.

> `<RED_AULA>` = prefijo de la red real de clase (por ejemplo `192.168.1`). Se confirmará al montar los equipos.

## 1. Idea general

- La **red del aula** hace de "Internet" del proyecto.
- Cada PC tiene su **propia red de laboratorio**, separada de las demás.
- En el PC 1, **todo** lo que entra o sale pasa por un firewall (**FW-01**). Es el único punto visible desde fuera, y por tanto el objetivo de las pruebas de Kali.

> 💡 **Ejemplo:** es como un edificio con un único portal y un portero (FW-01). Quien viene de fuera solo puede hablar con el portero; no puede ir directamente a la puerta de cada vivienda.

## 2. Redes

| Red | Rango | Dónde está | Gateway |
|-----|-------|-----------|---------|
| Aula (Internet) | `<RED_AULA>.0/24` | Switch de clase | Router del aula |
| LAN-CLIENTE | `10.10.10.0/24` | PC 1 (Proxmox) | `10.10.10.1` (FW-01) |
| DMZ | `10.10.11.0/24` | PC 1 (Proxmox) | `10.10.11.1` (FW-01) |
| RED-CIVEX | `10.10.20.0/24` | PC 2 (VirtualBox) | — |
| RED-KALI | `10.10.30.0/24` | PC 3 (VirtualBox) | — |

## 3. Máquinas

| Nombre | PC | Tipo | SO | IP | Función |
|--------|----|------|----|----|---------|
| pve01 | PC 1 | Host físico | Proxmox VE 8 | `<RED_AULA>.201` | Gestiona las VMs |
| FW-01 | PC 1 | VM | Debian 12 | WAN `<RED_AULA>.202` · `10.10.10.1` · `10.10.11.1` | Firewall (nftables) + Suricata |
| DNS-01 | PC 1 | LXC | Debian 12 | `10.10.10.10` | Servidor DNS (`sonrisaviva.local`) |
| CLINICA-01 | PC 1 | VM | Ubuntu Server 24.04 | `10.10.10.20` | Servidor interno con base de datos (datos ficticios) |
| WEB-01 | PC 1 | VM | Ubuntu Server 24.04 | `10.10.11.10` | Web de citas (en la DMZ) |
| WAZUH-01 | PC 1 | VM | Ubuntu Server 24.04 | `10.10.10.30` | SOC / Wazuh |
| MON-01 | PC 1 | LXC | Debian 12 | `10.10.10.40` | Prometheus + Grafana |
| CIVEX-01 | PC 2 | VM | Ubuntu Server 24.04 | `<RED_AULA>.211` · `10.10.20.10` | Plataforma web, Firebase, informes, backups |
| KALI-01 | PC 3 | VM | Kali Linux | `<RED_AULA>.221` · `10.10.30.10` | Pruebas de seguridad |

## 4. Firewall (FW-01): reglas principales

Política por defecto: **bloquear todo lo que no esté permitido** y registrar lo bloqueado.

| Qué se permite | Para qué |
|----------------|----------|
| Aula → FW-01 puertos 80/443, redirigido a WEB-01 | Que la web de citas sea pública |
| Administrador → FW-01 puerto 22 | Gestionar el firewall |
| LAN-CLIENTE y DMZ → Internet (80/443) | Actualizaciones |
| LAN-CLIENTE y DMZ → DNS-01 (53) | Resolución de nombres |
| LAN-CLIENTE y DMZ → WAZUH-01 (1514/1515) | Que los agentes envíen logs |
| WEB-01 → CLINICA-01 (3306) | La web consulta la base de datos |
| MON-01 → todas las VMs (9100) | Monitorización |
| **DMZ → LAN-CLIENTE: BLOQUEADO** | Si la web se compromete, no llega a los datos internos |

## 5. Pruebas previstas para validar el diseño

1. Desde Kali, `curl http://<RED_AULA>.202` debe mostrar la web de WEB-01.
2. Desde Kali, un escaneo (`nmap`) solo debe ver los puertos 22, 80 y 443.
3. Desde Kali, `ping 10.10.10.20` debe **fallar**: la red del cliente no está expuesta.
4. Las alertas de las pruebas deben aparecer en el dashboard de Wazuh.

https://github.com/civexasix/Civex/blob/main/img/Esquema%20de%20red.png
