# Informe Técnico: Proxmox VE y Redes Internas

## Índice

1. [Cuestiones teóricas](#1-cuestiones-teóricas)
2. [Configuración de un clúster en Proxmox](#2-configuración-de-un-clúster-en-proxmox)
3. [Red interna con IPTables en VirtualBox/VMware](#3-red-interna-con-iptables-en-virtualboxvmware)
4. [Red interna en Proxmox](#4-red-interna-en-proxmox)

---

## 1. Cuestiones teóricas

### ¿Qué es un clúster de Proxmox?

Un clúster de Proxmox es un conjunto de servidores físicos, llamados nodos, que se gestionan como una única entidad. Desde una sola interfaz web puedes administrar todos los recursos: CPU, RAM, almacenamiento, VMs y contenedores.

La ventaja principal es que permite alta disponibilidad y migración de máquinas virtuales entre nodos. Si un nodo falla, las VMs pueden moverse a otro nodo si el almacenamiento es compartido y la HA está configurada.

### ¿De qué otro modo se puede emular un clúster de Proxmox?

La forma más habitual para practicar es la virtualización anidada. Es decir, instalar Proxmox VE como una máquina virtual dentro de VirtualBox o VMware, y crear varios de esos nodos virtuales para formar el clúster.

También se podría hacer con contenedores, pero la anidación con VMs es más realista porque trabaja con el mismo esquema de red y almacenamiento que un clúster físico.

### ¿Qué tipo de tecnologías nos permite crear un clúster de alta disponibilidad?

Principalmente:

- **Corosync:** comunicación y consenso entre nodos. Es el que mantiene el quórum.
- **Pacemaker / PVE HA Manager:** decide dónde se ejecuta cada recurso y qué hacer si un nodo falla.
- **Almacenamiento compartido:** Ceph, NFS, iSCSI, etc. Sin almacenamiento compartido, una VM no puede migrar en caliente de un nodo a otro.
- **Fencing / watchdog:** mecanismos para aislar un nodo que no responde y evitar que dos nodos intenten usar el mismo recurso.

### ¿Qué son los hipervisores? ¿Qué significa que sean de tipo 1 o tipo 2? Ejemplos

Un hipervisor es el software que crea y gestiona máquinas virtuales, repartiendo los recursos del hardware real entre las VMs.

- **Tipo 1 o bare-metal:** se instala directamente sobre el hardware, sin un sistema operativo anfitrión por medio. Es más eficiente.
  - Ejemplos: **Proxmox VE**, VMware ESXi, Microsoft Hyper-V Server.
- **Tipo 2 o hosted:** se instala como un programa dentro de un sistema operativo.
  - Ejemplos: **VirtualBox**, VMware Workstation.

### ¿En qué sistema operativo se basa Proxmox?

Proxmox VE está basado en **Debian Linux**. Usa un kernel de Linux adaptado para virtualización y su sistema base es una Debian personalizada.

### ¿Qué tipos de virtualización están disponibles por defecto en Proxmox?

Dos:

1. **Máquinas virtuales completas:** mediante **KVM**.
2. **Contenedores:** mediante **LXC**. Son más ligeros porque comparten el kernel del host.

### ¿Qué es QEMU, KVM, noVNC y Ceph? Características principales

- **QEMU:** emulador de hardware. Se encarga de simular discos, tarjetas de red, controladoras, etc.
- **KVM:** módulo del kernel de Linux que permite usar las extensiones de virtualización del procesador. QEMU y KVM trabajan juntos: KVM aporta el rendimiento y QEMU los dispositivos virtuales.
- **noVNC:** cliente VNC basado en HTML5. Permite abrir la consola gráfica de una VM directamente en el navegador, sin instalar nada.
- **Ceph:** sistema de almacenamiento distribuido. Agrupa los discos de varios nodos en un pool común y replica los datos. Si un nodo cae, los datos siguen disponibles desde los otros nodos.

### ¿Qué tipos de roles de usuarios y grupos podemos configurar en Proxmox?

Proxmox usa control de acceso basado en roles (RBAC). Algunos roles por defecto son:

- **Administrator:** control total.
- **PVEAdmin:** administración casi completa, pero sin tocar ciertas partes críticas del sistema.
- **PVEAuditor:** solo lectura.
- **PVEVMAdmin:** administrar VMs.
- **PVEVMUser:** usar VMs, encender, apagar y consola.
- **PVEDatastoreAdmin:** administrar almacenamiento.
- **PVEDatastoreUser:** solo ver/usar almacenamiento.

Además se pueden crear usuarios locales, usuarios de LDAP/Active Directory y agruparlos para asignar permisos por rutas o por pools de recursos.

### ¿Dónde se almacenan las ISOs y templates para crear VM o contenedores en Proxmox?

En los **datastores** configurados. En una instalación estándar, el datastore `local` suele tener:

- ISOs: `/var/lib/vz/template/iso`
- Templates de contenedores LXC: `/var/lib/vz/template/cache`

---

## 2. Configuración de un clúster en Proxmox

### 1. Hardware especificado

Para la práctica monté **3 nodos anidados** en VirtualBox. Cada nodo con:

- **CPU:** 2 vCPUs.
- **RAM:** 4 GB.
- **Disco:** 20 GB.
- **Red:** adaptador puente en la misma subred para que los nodos se vean entre ellos.

### 2. Breve explicación de cómo lo configuré

Instalé Proxmox VE en los tres nodos virtuales. Desde la interfaz web del primer nodo fui a:

**Datacenter → Cluster → Create Cluster**

Le puse un nombre al clúster. Después, desde los otros dos nodos, usé:

**Datacenter → Cluster → Join Cluster**

Introduje la IP del primer nodo y la información de unión que genera el nodo maestro. Tras unos segundos, los tres nodos aparecieron en la vista de Datacenter.

Antes de unirlos comprobé que todos resolvían correctamente los nombres por `/etc/hosts` y que tenían la hora sincronizada.

### 3. Incidencias técnicas y solución

**Incidencia 1:** El segundo nodo no se unía al clúster. Daba un error de conexión rechazada.

**Solución:** En `/etc/hosts` el nombre del nodo maestro apuntaba a `127.0.0.1` en lugar de a su IP real. Lo corregí, reinicié la red y volvió a funcionar.

**Incidencia 2:** Un nodo aparecía en rojo porque había apagado otro nodo para probar.

**Solución:** Era un problema de quórum. Al volver a encender el nodo apagado y esperar unos segundos, el quórum se recuperó solo. Para comprobarlo usé:

```bash
pvecm status
```

### 4. ¿Cómo eliminaría un clúster? Pasos y justificación

No se elimina con un solo botón. Hay que desmontarlo nodo a nodo y con cuidado para no romper el quórum ni dejar datos huérfanos.

1. **Migrar o destruir las cargas de trabajo:** mover todas las VMs y contenedores fuera del nodo que se va a eliminar.
2. **Eliminar trabajos de replicación:** en **Datacenter → Replication**, borrar los trabajos que impliquen al nodo que se va.
3. **Limpiar Ceph si se usa:** sacar los OSD y MON del nodo del clúster de Ceph antes de eliminarlo de Proxmox.
4. **Quitar referencias de HA:** en **Datacenter → HA**, sacar el nodo de cualquier grupo de alta disponibilidad.
5. **Apagar el nodo:** para que no intente reincorporarse a mitad del proceso.
6. **Ejecutar `pvecm delnode`:** desde otro nodo que siga en el clúster:

```bash
pvecm delnode nombre-del-nodo
```

La justificación es hacerlo en ese orden: primero se quitan las cargas y referencias, luego se apaga el nodo y finalmente se elimina del clúster. Si se borra antes de migrar las VMs, se pueden quedar discos o configuraciones huérfanas.

---

## 3. Red interna con IPTables en VirtualBox/VMware

### Crear la red interna entre dos VMs

Monté dos máquinas virtuales:

- **VM Router:** Linux con dos adaptadores de red.
  - Adaptador 1: NAT, para tener salida a Internet.
  - Adaptador 2: Red interna, por ejemplo `intnet`.
- **VM Cliente:** solo con adaptador en la red interna `intnet`.

En VirtualBox, la red interna se configura en **Configuración → Red → Adaptador 2 → Red interna**. En VMware se puede usar un **LAN Segment** o una red host-only, pero para aislar del host lo más parecido es un LAN Segment.

### Configuración de IPs

En la VM Router:

- Interfaz NAT: `enp0s3` (por DHCP).
- Interfaz interna: `enp0s8` con IP `192.168.50.1/24`.

En la VM Cliente:

- IP: `192.168.50.10/24`
- Gateway: `192.168.50.1`
- DNS: `8.8.8.8`

### Reglas IPTables en la VM Router

Primero activé el reenvío de paquetes:

```bash
sudo sysctl -w net.ipv4.ip_forward=1
```

Para dejarlo permanente:

```bash
echo "net.ipv4.ip_forward=1" | sudo tee -a /etc/sysctl.conf
```

Luego apliqué las reglas:

```bash
sudo iptables -t nat -A POSTROUTING -o enp0s3 -j MASQUERADE
sudo iptables -A FORWARD -i enp0s8 -o enp0s3 -j ACCEPT
sudo iptables -A FORWARD -i enp0s3 -o enp0s8 -m state --state RELATED,ESTABLISHED -j ACCEPT
```

Función de cada regla:

- `POSTROUTING ... MASQUERADE`: enmascara el tráfico de la red interna cuando sale por la interfaz NAT.
- `FORWARD -i enp0s8 -o enp0s3 -j ACCEPT`: permite que el tráfico vaya desde la red interna hacia Internet.
- `FORWARD -i enp0s3 -o enp0s8 ... RELATED,ESTABLISHED`: permite que vuelvan las respuestas de conexiones ya iniciadas.

Para guardar las reglas:

```bash
sudo apt install iptables-persistent
sudo netfilter-persistent save
```

### Prueba

Desde la VM cliente:

```bash
ping 8.8.8.8
curl https://www.google.com
```

Si responde, la red interna tiene salida a Internet a través del router con IPTables.

---

## 4. Red interna en Proxmox

### 4.1. Configuración de la red interna en Proxmox

Creé un segundo bridge sin puerto físico para aislar la red interna. En Proxmox se configura en `/etc/network/interfaces`. Añadí:

```bash
auto vmbr1
iface vmbr1 inet static
    address 10.10.10.1/24
    bridge-ports none
    bridge-stp off
    bridge-fd 0
```

Este `vmbr1` hace de switch virtual interno. La IP `10.10.10.1` será la puerta de enlace de la red interna.

El contenedor LXC que hace de router tiene:

- Una interfaz en `vmbr0`, la red con salida a Internet.
- Una interfaz en `vmbr1`, la red interna, con IP `10.10.10.2`.

La VM Alpine cliente tiene:

- Una interfaz en `vmbr1`.
- IP `10.10.10.10/24`.
- Gateway `10.10.10.2`.

### 4.2. Especificaciones técnicas de la red

En Proxmox **no se usa netplan**. Proxmox se basa en Debian y la configuración de red se hace en `/etc/network/interfaces`. En el cliente Alpine también se puede usar `setup-interfaces`, que genera ese mismo archivo.

Configuración del cliente Alpine en `/etc/network/interfaces`:

```bash
auto lo
iface lo inet loopback

auto eth0
iface eth0 inet static
    address 10.10.10.10/24
    gateway 10.10.10.2
```

DNS en `/etc/resolv.conf`:

```bash
nameserver 8.8.8.8
```

### 4.3. Contenedor LXC como router con IPTables

Creé un contenedor LXC privilegiado y con `nesting=1` para poder usar IPTables y el reenvío de paquetes sin problemas.

Dentro del LXC activé el reenvío:

```bash
echo "net.ipv4.ip_forward=1" >> /etc/sysctl.conf
sysctl -p
```

Reglas aplicadas:

```bash
iptables -t nat -A POSTROUTING -s 10.10.10.0/24 -o vmbr0 -j MASQUERADE
iptables -A FORWARD -s 10.10.10.0/24 -j ACCEPT
iptables -A FORWARD -d 10.10.10.0/24 -j ACCEPT
```

Función de cada una:

- `POSTROUTING ... MASQUERADE`: permite que la red interna `10.10.10.0/24` salga a Internet por `vmbr0`.
- `FORWARD -s 10.10.10.0/24 -j ACCEPT`: permite el tráfico que sale de la red interna.
- `FORWARD -d 10.10.10.0/24 -j ACCEPT`: permite el tráfico que entra hacia la red interna.

### 4.4. Instalación de Nginx en la VM Alpine

Dentro de la VM Alpine:

```bash
apk update
apk add nginx
rc-service nginx start
rc-update add nginx default
```

Por defecto, Nginx sirve una página de bienvenida en el puerto 80.

### 4.5. Regla IPTables para acceder desde la WAN a Nginx

Para que se pueda ver la web desde fuera de la red interna, añadí una regla DNAT en el router LXC:

```bash
iptables -t nat -A PREROUTING -i vmbr0 -p tcp --dport 8080 -j DNAT --to-destination 10.10.10.10:80
iptables -A FORWARD -p tcp -d 10.10.10.10 --dport 80 -j ACCEPT
```

Función:

- `PREROUTING ... DNAT`: redirige las peticiones TCP que llegan al router por el puerto `8080` hacia la VM Alpine en el puerto `80`.
- `FORWARD ... ACCEPT`: permite que ese tráfico reenviado llegue a la VM cliente.

No usé OpenWRT. Usé IPTables directamente en el contenedor LXC.

### 4.6. Acceso desde la red externa

Desde mi equipo externo no puedo entrar directamente a `10.10.10.10`, porque es una IP privada de la red interna. Lo que hago es acceder a la IP del router LXC en el puerto mapeado:

```text
http://IP_DEL_ROUTER_LXC:8080
```

El router recibe la petición, aplica DNAT y la reenvía a la VM Alpine en `10.10.10.10:80`. La respuesta vuelve al router y el router la devuelve a mi equipo.

---

## Conclusión

Con estas prácticas he aprendido a montar un clúster de Proxmox, a entender cómo funciona el quórum y el almacenamiento compartido, y a crear redes internas aisladas tanto en VirtualBox/VMware como en Proxmox. La parte más útil fue configurar el router con IPTables y comprobar que una VM de la red interna puede tener salida a Internet y recibir acceso desde fuera mediante DNAT.
