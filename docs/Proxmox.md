# Práctica de Proxmox VE: clúster y redes internas

Aquí dejo recogido lo que he ido haciendo para la práctica de Proxmox, tanto la parte de teoría como las configuraciones que he montado en el laboratorio.

## Índice

- [Cuestiones teóricas](#cuestiones-teóricas)
- [Clúster en Proxmox](#clúster-en-proxmox)
- [Red interna con IPTables en VirtualBox / VMware](#red-interna-con-iptables-en-virtualbox--vmware)
- [Red interna en Proxmox](#red-interna-en-proxmox)

---

## Cuestiones teóricas

### ¿Qué es un clúster de Proxmox?

Un clúster de Proxmox es un grupo de servidores físicos (los llamados nodos) que se gestionan como si fueran uno solo. Desde la interfaz web del nodo maestro puedes ver y administrar todos los recursos del conjunto: CPU, RAM, discos, VMs y contenedores.

Lo interesante del clúster es que permite alta disponibilidad y migración de máquinas virtuales entre nodos. Si un nodo se cae, sus VMs pueden pasar a otro nodo sin cortar el servicio, siempre que tengamos almacenamiento compartido y la HA configurada.

### ¿De qué otro modo se puede emular un clúster de Proxmox?

La forma más típica para practicar en casa o en el aula es la virtualización anidada. Es decir, instalar Proxmox dentro de una VM de VirtualBox o VMware, y crear varios de esos nodos virtuales para formar el clúster entre ellos. Es lo que hice yo en esta práctica.

Se podría hacer también con contenedores, pero la anidación con VMs se parece más a un entorno real porque se trabaja igual que con hardware físico.

### Tecnologías para crear un clúster de alta disponibilidad

Básicamente se juntan varias piezas:

- **Corosync**, que se encarga de la comunicación entre nodos y del famoso quórum. Si no hay quórum, el clúster no arranca.
- **Pacemaker / PVE HA Manager**, que decide dónde va cada recurso y qué hacer si un nodo falla.
- **Almacenamiento compartido**: Ceph, NFS, iSCSI... sin esto no puedes migrar una VM en caliente porque su disco está en un nodo concreto.
- Y algo de **fencing o watchdog** para aislar nodos que no responden y evitar que dos nodos se peleen por el mismo recurso.

### ¿Qué es un hipervisor? Tipos y ejemplos

Un hipervisor es el software que crea y gestiona las máquinas virtuales, repartiendo los recursos del hardware real entre ellas.

Se dividen en dos tipos:

- **Tipo 1 (bare-metal)**: se instala directamente sobre el hardware, sin sistema operativo anfitrión. Es más eficiente. Ejemplos: Proxmox VE, VMware ESXi, Hyper-V Server.
- **Tipo 2 (hosted)**: se instala como un programa dentro de un sistema operativo normal. Es más cómodo para escritorio pero menos eficiente. Ejemplos: VirtualBox, VMware Workstation.

### ¿En qué sistema operativo se basa Proxmox?

Proxmox VE está basado en **Debian Linux**. Su sistema base es una Debian personalizada con un kernel adaptado para virtualización.

### Tipos de virtualización en Proxmox

Por defecto tenemos dos:

1. **Máquinas virtuales completas**, usando KVM.
2. **Contenedores LXC**, que son más ligeros porque comparten el kernel del host.

### QEMU, KVM, noVNC y Ceph

- **QEMU** es el emulador de hardware. Simula discos, tarjetas de red, controladoras, etc.
- **KVM** es el módulo del kernel de Linux que permite usar las extensiones de virtualización del procesador. Trabaja junto a QEMU: uno pone el rendimiento y el otro los dispositivos virtuales.
- **noVNC** es un cliente VNC basado en HTML5. Es lo que permite abrir la consola gráfica de una VM en el navegador sin instalar nada.
- **Ceph** es un sistema de almacenamiento distribuido. Agrupa los discos de varios nodos en un pool común y replica los datos entre ellos. Si un nodo se cae, los datos siguen accesibles desde los otros.

### Roles de usuario y grupos en Proxmox

Proxmox usa control de acceso basado en roles (RBAC). Algunos de los roles por defecto son:

- **Administrator**: control total.
- **PVEAdmin**: administración casi completa, pero sin tocar ciertas partes críticas.
- **PVEAuditor**: solo lectura.
- **PVEVMAdmin** y **PVEVMUser**: administrar o simplemente usar VMs.
- **PVEDatastoreAdmin** y **PVEDatastoreUser**: para el almacenamiento.

Aparte de los roles, se pueden crear usuarios locales, usuarios de LDAP o Active Directory, y agruparlos para asignarles permisos por rutas o por pools de recursos.

### ¿Dónde se guardan las ISOs y templates?

En los **datastores** configurados. En una instalación estándar, el datastore `local` suele tener las rutas:

- ISOs: `/var/lib/vz/template/iso`
- Templates LXC: `/var/lib/vz/template/cache`

---

## Clúster en Proxmox

### Hardware usado

Monté **3 nodos anidados** en VirtualBox, que es el mínimo razonable para tener quórum sin sustos. Cada nodo con:

- 2 vCPUs.
- 4 GB de RAM.
- 20 GB de disco.
- Adaptador de red en modo puente, para que los tres se vean entre ellos en la misma subred.

### Cómo lo configuré

Instalé Proxmox VE en los tres nodos virtuales. Desde la web del primero (el que va a ser el maestro) fui a:

**Datacenter → Cluster → Create Cluster**

Le puse un nombre al clúster. Después, desde los otros dos nodos, entré en:

**Datacenter → Cluster → Join Cluster**

Metí la IP del primer nodo y la información de unión que me generó el maestro. A los pocos segundos aparecían los tres nodos en la vista de Datacenter.

Antes de unirlos comprobé dos cosas que suelen dar guerra: que todos resolvieran bien los nombres por `/etc/hosts` y que tuvieran la hora sincronizada.

<!-- Captura: vista del Datacenter con los 3 nodos en verde -->

### Incidencias y cómo las resolví

**El segundo nodo no se unía.** Me daba un error de conexión rechazada. Después de mirar un rato, el problema estaba en `/etc/hosts`: el nombre del nodo maestro apuntaba a `127.0.0.1` en vez de a su IP real. Lo corregí, reinicié la red y ya entró sin problema.

**Un nodo se me puso en rojo.** Había apagado otro nodo para probar y claro, perdimos el quórum. Al volver a encenderlo y esperar unos segundos, se recuperó solo. Para comprobar el estado usé:

```bash
pvecm status
```

<!-- Captura opcional: salida de pvecm status o el nodo recuperado -->

### Cómo eliminaría un clúster

No hay un botón de "borrar clúster". Hay que desmontarlo nodo a nodo y con cuidado, porque si lo haces mal puedes dejar configuraciones huérfanas o romper el quórum. El orden que seguiría sería:

1. **Migrar o destruir las cargas de trabajo** del nodo que voy a quitar. Si se queda alguna VM ahí, luego cuesta más limpiarlo.
2. **Eliminar los trabajos de replicación** en **Datacenter → Replication** que impliquen a ese nodo. Si no, Proxmox seguirá intentando replicar a un nodo fantasma.
3. **Limpiar Ceph** si lo estamos usando: sacar los OSD y los MON del nodo antes de borrarlo del clúster de Proxmox. Son dos clústeres distintos y hay que limpiar los dos.
4. **Quitar referencias de HA** en **Datacenter → HA**.
5. **Apagar el nodo**, para que no intente reincorporarse a mitad del proceso.
6. **Ejecutar `pvecm delnode`** desde otro nodo que siga en el clúster:

```bash
pvecm delnode nombre-del-nodo
```

El motivo de este orden es sencillo: primero quitas todo lo que depende del nodo, después lo apagas y, por último, lo borras del clúster. Si lo borras antes de mover las VMs, te puedes quedar con discos o configuraciones colgando.

---

## Red interna con IPTables en VirtualBox / VMware

### Montaje de las VMs

Creé dos VMs:

- **VM Router**: Linux con dos adaptadores. Uno en NAT (para salir a Internet) y otro en red interna.
- **VM Cliente**: solo con el adaptador de red interna.

En VirtualBox la red interna se pone en **Configuración → Red → Adaptador 2 → Red interna**, y le das un nombre (por ejemplo `intnet`). En VMware el equivalente más parecido es un **LAN Segment**, porque la host-only te deja ver al host y aquí queríamos aislar.

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

Y para que se quede tras reiniciar:

```bash
echo "net.ipv4.ip_forward=1" | sudo tee -a /etc/sysctl.conf
```

Después las reglas:

```bash
sudo iptables -t nat -A POSTROUTING -o enp0s3 -j MASQUERADE
sudo iptables -A FORWARD -i enp0s8 -o enp0s3 -j ACCEPT
sudo iptables -A FORWARD -i enp0s3 -o enp0s8 -m state --state RELATED,ESTABLISHED -j ACCEPT
```

Qué hace cada una:

- `POSTROUTING ... MASQUERADE`: enmascara el tráfico de la red interna cuando sale por la interfaz NAT.
- `FORWARD -i enp0s8 -o enp0s3`: deja pasar el tráfico que va de la red interna hacia Internet.
- `FORWARD -i enp0s3 -o enp0s8 ... RELATED,ESTABLISHED`: permite que vuelvan las respuestas de conexiones ya abiertas.

Para no perderlas al reiniciar:

```bash
sudo apt install iptables-persistent
sudo netfilter-persistent save
```

### Comprobación

Desde la VM cliente probé con:

```bash
ping 8.8.8.8
curl https://www.google.com
```

Respondió sin problemas, así que la red interna tenía salida a Internet a través del router.

<!-- Captura: ping desde el cliente + curl funcionando -->

---

## Red interna en Proxmox

### Crear el bridge interno

Para aislar la red interna creé un segundo bridge sin puerto físico. En Proxmox eso se hace en `/etc/network/interfaces`:

```bash
auto vmbr1
iface vmbr1 inet static
    address 10.10.10.1/24
    bridge-ports none
    bridge-stp off
    bridge-fd 0
```

El `vmbr1` hace de switch virtual interno. La IP `10.10.10.1` será la puerta de enlace de esa red.

El contenedor LXC que hace de router tiene dos interfaces:

- En `vmbr0`, para salir a Internet.
- En `vmbr1`, con IP `10.10.10.2` (la puerta de enlace de la red interna).

La VM Alpine cliente tiene:

- Interfaz en `vmbr1`.
- IP `10.10.10.10/24`.
- Gateway `10.10.10.2`.

<!-- Captura: pestaña Network de Proxmox con vmbr0 y vmbr1 -->

### Configuración de red (netplan / interfaces)

Aquí hago un inciso: en Proxmox **no se usa netplan**, porque eso es más de Ubuntu. Proxmox va con Debian y se configura en `/etc/network/interfaces`. En la VM Alpine usé `setup-interfaces` para generar ese mismo archivo.

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

Para que el LXC pueda usar IPTables sin problemas lo creé privilegiado y con `nesting=1`. Dentro del contenedor activé el reenvío:

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

Qué hace cada una:

- `POSTROUTING ... MASQUERADE`: enmascara el tráfico de `10.10.10.0/24` cuando sale por `vmbr0`, para que llegue a Internet.
- `FORWARD -s 10.10.10.0/24`: deja salir el tráfico de la red interna.
- `FORWARD -d 10.10.10.0/24`: deja entrar el tráfico que va hacia la red interna.

No usé OpenWRT. Tiré directamente con IPTables en el contenedor LXC.

### Instalación de Nginx en la VM Alpine

Dentro de la VM Alpine:

```bash
apk update
apk add nginx
rc-service nginx start
rc-update add nginx default
```

Por defecto Nginx ya sirve una página de bienvenida en el puerto 80.

### Abrir el acceso desde la WAN

Para poder ver esa página desde fuera de la red interna añadí una regla DNAT en el router LXC:

```bash
iptables -t nat -A PREROUTING -i vmbr0 -p tcp --dport 8080 -j DNAT --to-destination 10.10.10.10:80
iptables -A FORWARD -p tcp -d 10.10.10.10 --dport 80 -j ACCEPT
```

- `PREROUTING ... DNAT`: redirige las peticiones TCP que llegan al router por el puerto `8080` hacia la VM Alpine en el puerto `80`.
- `FORWARD ... ACCEPT`: permite que ese tráfico reenviado llegue hasta la VM cliente.

### Acceso desde fuera

Desde mi equipo externo no puedo ir directamente a `10.10.10.10` porque es una IP privada de la red interna. Lo que hago es entrar a la IP del router LXC con el puerto mapeado:

```text
http://IP_DEL_ROUTER_LXC:8080
```

El router recibe la petición, aplica el DNAT y la manda a la VM Alpine en `10.10.10.10:80`. La respuesta vuelve por donde vino y la veo como si el router mismo fuera el servidor web.

<!-- Captura: navegador con el "Welcome to nginx!" accediendo a IP_DEL_ROUTER_LXC:8080 -->

---

Con esto doy por cerrada la práctica. Lo que más me ha servido ha sido montar el router con IPTables y ver que una VM aislada en la red interna puede tener salida a Internet y recibir tráfico de fuera mediante DNAT.
