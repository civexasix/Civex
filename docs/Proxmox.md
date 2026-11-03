# Práctica de Proxmox VE: clúster y redes internas

Recopilación de la parte teórica y de las configuraciones realizadas en el laboratorio para la práctica de Proxmox.

## Índice

- [Cuestiones teóricas](#cuestiones-teóricas)
- [Clúster en Proxmox](#clúster-en-proxmox)
- [Red interna con IPTables en VirtualBox / VMware](#red-interna-con-iptables-en-virtualbox--vmware)
- [Red interna en Proxmox](#red-interna-en-proxmox)

---

## Cuestiones teóricas

### ¿Qué es un clúster de Proxmox?

Un clúster de Proxmox es un grupo de servidores físicos (los llamados nodos) que se gestionan como una única entidad. Desde la interfaz web del nodo maestro se pueden ver y administrar todos los recursos del conjunto: CPU, RAM, discos, VMs y contenedores.

Su principal utilidad es que permite alta disponibilidad y migración de máquinas virtuales entre nodos. Si un nodo cae, sus VMs pueden pasar a otro nodo sin interrumpir el servicio, siempre que se disponga de almacenamiento compartido y la HA esté configurada.

### ¿De qué otro modo se puede emular un clúster de Proxmox?

La forma más habitual para practicar en casa o en el aula es la virtualización anidada. Consiste en instalar Proxmox dentro de una VM de VirtualBox o VMware y crear varios de esos nodos virtuales para formar el clúster entre ellos. Es el método que he utilizado en esta práctica.

También podría hacerse con contenedores, pero la anidación con VMs se aproxima más a un entorno real, ya que se trabaja igual que con hardware físico.

### Tecnologías para crear un clúster de alta disponibilidad

Intervienen varias piezas:

- **Corosync**, encargado de la comunicación entre nodos y del quórum. Sin quórum, el clúster no arranca.
- **Pacemaker / PVE HA Manager**, que decide dónde se ejecuta cada recurso y qué hacer si un nodo falla.
- **Almacenamiento compartido**: Ceph, NFS, iSCSI, etc. Sin él no es posible migrar una VM en caliente, ya que su disco está asociado a un nodo concreto.
- **Fencing o watchdog**, para aislar nodos que no responden y evitar que dos nodos utilicen el mismo recurso.

### ¿Qué es un hipervisor? Tipos y ejemplos

Un hipervisor es el software que crea y gestiona las máquinas virtuales, repartiendo los recursos del hardware real entre ellas.

Se distinguen dos tipos:

- **Tipo 1 (bare-metal)**: se instala directamente sobre el hardware, sin sistema operativo anfitrión. Es más eficiente. Ejemplos: Proxmox VE, VMware ESXi, Hyper-V Server.
- **Tipo 2 (hosted)**: se instala como un programa dentro de un sistema operativo. Resulta más cómodo en escritorio, pero menos eficiente. Ejemplos: VirtualBox, VMware Workstation.

### ¿En qué sistema operativo se basa Proxmox?

Proxmox VE está basado en **Debian Linux**. Su sistema base es una Debian personalizada con un kernel adaptado para virtualización.

### Tipos de virtualización en Proxmox

Por defecto hay dos:

1. **Máquinas virtuales completas**, mediante KVM.
2. **Contenedores LXC**, más ligeros porque comparten el kernel del host.

### QEMU, KVM, noVNC y Ceph

- **QEMU** es el emulador de hardware. Simula discos, tarjetas de red, controladoras, etc.
- **KVM** es el módulo del kernel de Linux que permite usar las extensiones de virtualización del procesador. Trabaja junto a QEMU: uno aporta el rendimiento y el otro los dispositivos virtuales.
- **noVNC** es un cliente VNC basado en HTML5. Permite abrir la consola gráfica de una VM en el navegador sin instalar nada.
- **Ceph** es un sistema de almacenamiento distribuido. Agrupa los discos de varios nodos en un pool común y replica los datos entre ellos. Si un nodo falla, los datos siguen accesibles desde los demás.

### Roles de usuario y grupos en Proxmox

Proxmox utiliza control de acceso basado en roles (RBAC). Algunos de los roles por defecto son:

- **Administrator**: control total.
- **PVEAdmin**: administración casi completa, sin acceso a ciertas partes críticas.
- **PVEAuditor**: solo lectura.
- **PVEVMAdmin** y **PVEVMUser**: administrar o utilizar VMs.
- **PVEDatastoreAdmin** y **PVEDatastoreUser**: para el almacenamiento.

Además de los roles, se pueden crear usuarios locales, usuarios de LDAP o Active Directory, y agruparlos para asignar permisos por rutas o por pools de recursos.

### ¿Dónde se guardan las ISOs y templates?

En los **datastores** configurados. En una instalación estándar, el datastore `local` suele contener las rutas:

- ISOs: `/var/lib/vz/template/iso`
- Templates LXC: `/var/lib/vz/template/cache`

---

## Clúster en Proxmox

### Hardware utilizado

Monté **3 nodos anidados** en VirtualBox, que es el mínimo recomendado para disponer de quórum. Cada nodo con:

- 2 vCPUs.
- 4 GB de RAM.
- 20 GB de disco.
- Adaptador de red en modo puente, para que los tres se vean entre sí en la misma subred.

### Configuración

Instalé Proxmox VE en los tres nodos virtuales. Desde la web del primero (el que actúa como maestro) accedí a:

**Datacenter → Cluster → Create Cluster**

Asigné un nombre al clúster. Después, desde los otros dos nodos, entré en:

**Datacenter → Cluster → Join Cluster**

Introduje la IP del primer nodo y la información de unión generada por el maestro. En unos segundos aparecieron los tres nodos en la vista de Datacenter.

Antes de unirlos comprobé dos aspectos que suelen dar problemas: que todos resolvieran correctamente los nombres por `/etc/hosts` y que tuvieran la hora sincronizada.

<!-- Captura: vista del Datacenter con los 3 nodos en verde -->

### Incidencias y resolución

**El segundo nodo no se unía.** Devolvía un error de conexión rechazada. Tras revisar la configuración, el problema estaba en `/etc/hosts`: el nombre del nodo maestro apuntaba a `127.0.0.1` en lugar de a su IP real. Lo corregí, reinicié la red y se unió correctamente.

**Un nodo apareció en rojo.** Había apagado otro nodo para probar y se perdió el quórum. Al volver a encenderlo y esperar unos segundos, se recuperó automáticamente. Para comprobar el estado utilicé:

```bash
pvecm status
```

<!-- Captura opcional: salida de pvecm status o el nodo recuperado -->

### Cómo eliminaría un clúster

No existe una opción de "borrar clúster". Hay que desmontarlo nodo a nodo y con cuidado, ya que si se hace mal pueden quedar configuraciones huérfanas o romperse el quórum. El orden que seguiría sería:

1. **Migrar o destruir las cargas de trabajo** del nodo que se va a retirar. Si queda alguna VM ahí, la limpieza posterior resulta más compleja.
2. **Eliminar los trabajos de replicación** en **Datacenter → Replication** que impliquen a ese nodo. De lo contrario, Proxmox seguirá intentando replicar a un nodo inexistente.
3. **Limpiar Ceph** si se está utilizando: retirar los OSD y los MON del nodo antes de eliminarlo del clúster de Proxmox. Son dos clústeres distintos y hay que limpiar ambos.
4. **Quitar referencias de HA** en **Datacenter → HA**.
5. **Apagar el nodo**, para que no intente reincorporarse durante el proceso.
6. **Ejecutar `pvecm delnode`** desde otro nodo que siga en el clúster:

```bash
pvecm delnode nombre-del-nodo
```

El motivo de este orden es sencillo: primero se retira todo lo que depende del nodo, después se apaga y, por último, se elimina del clúster. Si se borra antes de mover las VMs, pueden quedar discos o configuraciones sin referencias.

---

## Red interna con IPTables en VirtualBox / VMware

### Montaje de las VMs

Creé dos VMs:

- **VM Router**: Linux con dos adaptadores. Uno en NAT (para salir a Internet) y otro en red interna.
- **VM Cliente**: únicamente con el adaptador de red interna.

En VirtualBox la red interna se configura en **Configuración → Red → Adaptador 2 → Red interna**, asignándole un nombre (por ejemplo `intnet`). En VMware el equivalente más aproximado es un **LAN Segment**, ya que la red host-only permite ver al host y aquí se buscaba aislar.

### Direccionamiento

En la VM Router:

- `enp0s3`: NAT, por DHCP.
- `enp0s8`: red interna, con IP `192.168.50.1/24`.

En la VM Cliente:

- IP `192.168.50.10/24`.
- Gateway `192.168.50.1`.
- DNS `8.8.8.8`.

### Reglas IPTables en el router

Primero activé el reenvío de paquetes:

```bash
sudo sysctl -w net.ipv4.ip_forward=1
```

Para que se mantenga tras reiniciar:

```bash
echo "net.ipv4.ip_forward=1" | sudo tee -a /etc/sysctl.conf
```

Después apliqué las reglas:

```bash
sudo iptables -t nat -A POSTROUTING -o enp0s3 -j MASQUERADE
sudo iptables -A FORWARD -i enp0s8 -o enp0s3 -j ACCEPT
sudo iptables -A FORWARD -i enp0s3 -o enp0s8 -m state --state RELATED,ESTABLISHED -j ACCEPT
```

Función de cada una:

- `POSTROUTING ... MASQUERADE`: enmascara el tráfico de la red interna al salir por la interfaz NAT.
- `FORWARD -i enp0s8 -o enp0s3`: permite el tráfico desde la red interna hacia Internet.
- `FORWARD -i enp0s3 -o enp0s8 ... RELATED,ESTABLISHED`: permite el retorno de las respuestas de conexiones ya establecidas.

Para conservarlas tras reiniciar:

```bash
sudo apt install iptables-persistent
sudo netfilter-persistent save
```

### Comprobación

Desde la VM cliente ejecuté:

```bash
ping 8.8.8.8
curl https://www.google.com
```

Ambos respondieron correctamente, por lo que la red interna disponía de salida a Internet a través del router.

<!-- Captura: ping desde el cliente + curl funcionando -->

---

## Red interna en Proxmox

### Creación del bridge interno

Para aislar la red interna creé un segundo bridge sin puerto físico. En Proxmox se configura en `/etc/network/interfaces`:

```bash
auto vmbr1
iface vmbr1 inet static
    address 10.10.10.1/24
    bridge-ports none
    bridge-stp off
    bridge-fd 0
```

El `vmbr1` actúa como switch virtual interno. La IP `10.10.10.1` será la puerta de enlace de esa red.

El contenedor LXC que hace de router dispone de dos interfaces:

- En `vmbr0`, para la salida a Internet.
- En `vmbr1`, con IP `10.10.10.2` (puerta de enlace de la red interna).

La VM Alpine cliente tiene:

- Interfaz en `vmbr1`.
- IP `10.10.10.10/24`.
- Gateway `10.10.10.2`.

<!-- Captura: pestaña Network de Proxmox con vmbr0 y vmbr1 -->

### Configuración de red (netplan / interfaces)

Conviene aclarar que en Proxmox **no se utiliza netplan**, ya que es propio de Ubuntu. Proxmox trabaja sobre Debian y se configura en `/etc/network/interfaces`. En la VM Alpine utilicé `setup-interfaces` para generar ese mismo archivo.

Configuración del cliente Alpine en `/etc/network/interfaces`:

```bash
auto lo
iface lo inet loopback

auto eth0
iface eth0 inet static
    address 10.10.10.10/24
    gateway 10.10.10.2
```

Y el DNS en `/etc/resolv.conf`:

```bash
nameserver 8.8.8.8
```

### Contenedor LXC como router

Para que el LXC pudiera utilizar IPTables sin restricciones lo creé privilegiado y con `nesting=1`. Dentro del contenedor activé el reenvío:

```bash
echo "net.ipv4.ip_forward=1" >> /etc/sysctl.conf
sysctl -p
```

Y apliqué las reglas:

```bash
iptables -t nat -A POSTROUTING -s 10.10.10.0/24 -o vmbr0 -j MASQUERADE
iptables -A FORWARD -s 10.10.10.0/24 -j ACCEPT
iptables -A FORWARD -d 10.10.10.0/24 -j ACCEPT
```

Función de cada una:

- `POSTROUTING ... MASQUERADE`: enmascara el tráfico de `10.10.10.0/24` al salir por `vmbr0`, permitiendo la salida a Internet.
- `FORWARD -s 10.10.10.0/24`: permite la salida del tráfico de la red interna.
- `FORWARD -d 10.10.10.0/24`: permite la entrada del tráfico dirigido a la red interna.

No se utilizó OpenWRT; las reglas se aplicaron directamente con IPTables en el contenedor LXC.

### Instalación de Nginx en la VM Alpine

Dentro de la VM Alpine:

```bash
apk update
apk add nginx
rc-service nginx start
rc-update add nginx default
```

Por defecto, Nginx sirve una página de bienvenida en el puerto 80.

### Acceso desde la WAN

Para poder acceder a esa página desde fuera de la red interna añadí una regla DNAT en el router LXC:

```bash
iptables -t nat -A PREROUTING -i vmbr0 -p tcp --dport 8080 -j DNAT --to-destination 10.10.10.10:80
iptables -A FORWARD -p tcp -d 10.10.10.10 --dport 80 -j ACCEPT
```

- `PREROUTING ... DNAT`: redirige las peticiones TCP que llegan al router por el puerto `8080` hacia la VM Alpine en el puerto `80`.
- `FORWARD ... ACCEPT`: permite que ese tráfico reenviado llegue hasta la VM cliente.

### Acceso desde el exterior

Desde un equipo externo no es posible acceder directamente a `10.10.10.10`, al tratarse de una IP privada de la red interna. El acceso se realiza a través de la IP del router LXC con el puerto mapeado:

```text
http://IP_DEL_ROUTER_LXC:8080
```

El router recibe la petición, aplica el DNAT y la redirige a la VM Alpine en `10.10.10.10:80`. La respuesta sigue el camino inverso y llega al equipo externo como si el propio router fuera el servidor web.

<!-- Captura: navegador con el "Welcome to nginx!" accediendo a IP_DEL_ROUTER_LXC:8080 -->

---

Con esto queda cerrada la práctica. La parte que más útil me ha resultado ha sido la configuración del router con IPTables y la comprobación de que una VM aislada en la red interna puede disponer de salida a Internet y recibir tráfico desde el exterior mediante DNAT.
