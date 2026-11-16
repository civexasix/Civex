-- =====================================================================
-- CIVEX · Base de datos del dashboard
-- MySQL 8.x (compatible con MariaDB 10.5+)
-- OJO: al principio borra y recrea la base de datos "civex".
-- Los datos de las secciones 3 y 4 son de EJEMPLO, para probar el dashboard.
-- =====================================================================

DROP DATABASE IF EXISTS civex;
CREATE DATABASE civex CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
USE civex;

-- =====================================================================
-- 1. TABLAS
-- =====================================================================

-- Clientes (organizaciones a las que CIVEX presta servicio)
CREATE TABLE clientes (
  id          INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  nombre      VARCHAR(120) NOT NULL,
  descripcion TEXT NULL,
  estado      ENUM('activo','inactivo') NOT NULL DEFAULT 'activo',
  creado_en   DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP
) ENGINE=InnoDB;

-- Usuarios de la plataforma. cliente_id NULL = personal de CIVEX
CREATE TABLE usuarios (
  id             INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  cliente_id     INT UNSIGNED NULL,
  nombre         VARCHAR(120) NOT NULL,
  apellido         VARCHAR(120) NOT NULL,
  email          VARCHAR(160) NOT NULL UNIQUE,
  password_hash  VARCHAR(255) NOT NULL,          -- password_hash() de PHP, nunca en claro
  rol            ENUM('admin_civex','cliente') NOT NULL DEFAULT 'cliente',
  activo         TINYINT(1) NOT NULL DEFAULT 1,
  creado_en      DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  ultimo_acceso  DATETIME NULL,
  CONSTRAINT chk_usuario_rol_cliente CHECK (
    (rol = 'admin_civex' AND cliente_id IS NULL)
    OR
    (rol = 'cliente' AND cliente_id IS NOT NULL)),
  CONSTRAINT fk_usuarios_cliente FOREIGN KEY (cliente_id) REFERENCES clientes(id)
) ENGINE=InnoDB;



-- Infraestructura. cliente_id NULL = máquina propia de CIVEX (Kali, Wazuh, plataforma)
CREATE TABLE maquinas (
  id                    INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  cliente_id            INT UNSIGNED NOT NULL,
  nombre                VARCHAR(60) NOT NULL UNIQUE,
  ip_principal          VARCHAR(45) NOT NULL,
  ip_secundaria         VARCHAR(45) NULL,
  sistema_operativo     VARCHAR(60) NOT NULL,
  tipo                  ENUM('host','vm','lxc') NOT NULL DEFAULT 'vm',
  red                   VARCHAR(40) NULL,
  funcion               VARCHAR(120) NULL,
  estado                ENUM('encendida','apagada','desconectada') NOT NULL DEFAULT 'encendida',
  ultima_actualizacion  DATETIME NULL,
  CONSTRAINT fk_maquinas_cliente FOREIGN KEY (cliente_id) REFERENCES clientes(id)
) ENGINE=InnoDB;

-- Estado de los servicios (DNS, web, MariaDB, Wazuh, Prometheus...)
CREATE TABLE servicios (
  id                  INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  maquina_id          INT UNSIGNED NOT NULL,
  nombre              VARCHAR(60) NOT NULL,
  estado              ENUM('disponible','degradado','caido') NOT NULL DEFAULT 'disponible',
  ultima_comprobacion DATETIME NULL,
  UNIQUE KEY uq_servicio (maquina_id, nombre),
  CONSTRAINT fk_servicios_maquina FOREIGN KEY (maquina_id) REFERENCES maquinas(id) ON DELETE CASCADE
) ENGINE=InnoDB;

-- Últimas métricas: UNA fila por máquina (se sobrescribe cada vez)
CREATE TABLE metricas_actuales (
  maquina_id         INT UNSIGNED PRIMARY KEY,
  cpu_pct            DECIMAL(5,2) NOT NULL,
  ram_usada_mb       INT UNSIGNED NOT NULL,
  ram_total_mb       INT UNSIGNED NOT NULL,
  disco_pct          DECIMAL(5,2) NOT NULL,
  red_entrada_bytes  BIGINT UNSIGNED NOT NULL DEFAULT 0,
  red_salida_bytes   BIGINT UNSIGNED NOT NULL DEFAULT 0,
  uptime_seg         BIGINT UNSIGNED NULL,
  actualizado_en     DATETIME NOT NULL,
  CONSTRAINT fk_metact_maquina FOREIGN KEY (maquina_id) REFERENCES maquinas(id) ON DELETE CASCADE
) ENGINE=InnoDB;

-- Histórico RESUMIDO (para las gráficas de líneas). No guardar cada muestra de Prometheus
CREATE TABLE metricas_historico (
  id          BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  maquina_id  INT UNSIGNED NOT NULL,
  fecha       DATETIME NOT NULL,
  cpu_pct     DECIMAL(5,2) NOT NULL,
  ram_pct     DECIMAL(5,2) NOT NULL,
  disco_pct   DECIMAL(5,2) NOT NULL,
  KEY idx_hist_maquina_fecha (maquina_id, fecha),
  CONSTRAINT fk_hist_maquina FOREIGN KEY (maquina_id) REFERENCES maquinas(id) ON DELETE CASCADE
) ENGINE=InnoDB;

-- Alertas de seguridad (Wazuh y Suricata): son EVENTOS detectados
CREATE TABLE alertas (
  id               INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  maquina_id       INT UNSIGNED NOT NULL,
  origen           ENUM('wazuh','suricata') NOT NULL,
  regla_id         VARCHAR(40) NULL,
  tipo             VARCHAR(60) NULL,
  descripcion      VARCHAR(255) NOT NULL,
  gravedad         ENUM('baja','media','alta','critica') NOT NULL,
  ip_origen        VARCHAR(45) NULL,
  ip_destino       VARCHAR(45) NULL,
  puerto_origen    INT UNSIGNED NULL,
  puerto_destino   INT UNSIGNED NULL,
  fecha            DATETIME NOT NULL,
  estado           ENUM('nueva','investigando','resuelta') NOT NULL DEFAULT 'nueva',
  KEY idx_alertas_estado (estado),
  KEY idx_alertas_fecha (fecha),
  CONSTRAINT fk_alertas_maquina FOREIGN KEY (maquina_id) REFERENCES maquinas(id)
) ENGINE=InnoDB;

-- Escaneos realizados desde Kali u otras herramientas
CREATE TABLE escaneos (
  id          INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  herramienta VARCHAR(60) NOT NULL,
  objetivo    VARCHAR(120) NOT NULL,
  maquina_id  INT UNSIGNED NULL,
  fecha       DATETIME NOT NULL,
  resumen     TEXT NULL,
  CONSTRAINT fk_escaneos_maquina FOREIGN KEY (maquina_id) REFERENCES maquinas(id) ON DELETE SET NULL
) ENGINE=InnoDB;

-- Vulnerabilidades: problemas CONFIRMADOS y evaluados (pueden nacer de una alerta o de un escaneo)
CREATE TABLE vulnerabilidades (
  id              INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  codigo          VARCHAR(20) NOT NULL UNIQUE,        -- VULN-001...
  maquina_id      INT UNSIGNED NOT NULL,
  escaneo_id      INT UNSIGNED NULL,
  alerta_id       INT UNSIGNED NULL,
  nombre          VARCHAR(160) NOT NULL,
  descripcion     TEXT NULL,
  riesgo          ENUM('baja','media','alta','critica') NOT NULL,
  evidencia       TEXT NULL,
  recomendacion   TEXT NULL,
  estado          ENUM('pendiente','en_correccion','corregida','verificada') NOT NULL DEFAULT 'pendiente',
  detectada_en    DATETIME NOT NULL,
  verificada_en   DATETIME NULL,                       -- fecha de la nueva comprobación
  KEY idx_vuln_estado (estado),
  CONSTRAINT fk_vuln_maquina FOREIGN KEY (maquina_id) REFERENCES maquinas(id),
  CONSTRAINT fk_vuln_escaneo FOREIGN KEY (escaneo_id) REFERENCES escaneos(id) ON DELETE SET NULL,
  CONSTRAINT fk_vuln_alerta  FOREIGN KEY (alerta_id)  REFERENCES alertas(id)  ON DELETE SET NULL
) ENGINE=InnoDB;

-- Incidencias: seguimiento de problemas
CREATE TABLE incidencias (
  id                INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  maquina_id        INT UNSIGNED NOT NULL,
  titulo            VARCHAR(160) NOT NULL,
  descripcion       TEXT NULL,
  prioridad         ENUM('baja','media','alta','critica') NOT NULL DEFAULT 'media',
  estado            ENUM('abierta','en_curso','cerrada') NOT NULL DEFAULT 'abierta',
  responsable_id    INT UNSIGNED NULL,
  alerta_id         INT UNSIGNED NULL,
  vulnerabilidad_id INT UNSIGNED NULL,
  creada_en         DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  cerrada_en        DATETIME NULL,
  CONSTRAINT fk_inc_maquina
  FOREIGN KEY (maquina_id) REFERENCES maquinas(id),
  CONSTRAINT fk_inc_resp FOREIGN KEY (responsable_id)    REFERENCES usuarios(id)         ON DELETE SET NULL,
  CONSTRAINT fk_inc_ale  FOREIGN KEY (alerta_id)         REFERENCES alertas(id)          ON DELETE SET NULL,
  CONSTRAINT fk_inc_vul  FOREIGN KEY (vulnerabilidad_id) REFERENCES vulnerabilidades(id) ON DELETE SET NULL
) ENGINE=InnoDB;

-- Backups
CREATE TABLE backups (
  id                       INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  maquina_id               INT UNSIGNED NOT NULL,
  fecha                    DATETIME NOT NULL,
  resultado                ENUM('correcto','fallido') NOT NULL,
  tamano_mb                INT UNSIGNED NULL,
  ubicacion                VARCHAR(160) NULL,
  prueba_restauracion_en   DATETIME NULL,
  KEY idx_backups_fecha (fecha),
  CONSTRAINT fk_backups_maquina FOREIGN KEY (maquina_id) REFERENCES maquinas(id)
) ENGINE=InnoDB;

-- Informes de auditoría
CREATE TABLE informes (
  id          INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  cliente_id  INT UNSIGNED NOT NULL,
  titulo      VARCHAR(160) NOT NULL,
  tipo        ENUM('auditoria','vulnerabilidades','mensual') NOT NULL,
  fecha       DATE NOT NULL,
  archivo     VARCHAR(255) NULL,
  estado      ENUM('borrador','publicado') NOT NULL DEFAULT 'borrador',
  CONSTRAINT fk_informes_cliente FOREIGN KEY (cliente_id) REFERENCES clientes(id)
) ENGINE=InnoDB;

-- Registro de acciones en la plataforma
CREATE TABLE registro_auditoria (
  id           BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  usuario_id   INT UNSIGNED NULL,
  accion       VARCHAR(80) NOT NULL,
  recurso      VARCHAR(60) NULL,
  recurso_id   INT UNSIGNED NULL,
  ip           VARCHAR(45) NULL,
  fecha        DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  CONSTRAINT fk_audit_usuario FOREIGN KEY (usuario_id) REFERENCES usuarios(id) ON DELETE SET NULL
) ENGINE=InnoDB;

-- =====================================================================
-- 2. VISTAS (lo que lee el dashboard)
-- =====================================================================

-- Contadores de las tarjetas y de los 4 circulares de abajo (una fila por cliente)
CREATE VIEW v_kpis_cliente AS
SELECT
  c.id AS cliente_id,
  (SELECT COUNT(*) FROM maquinas m WHERE m.cliente_id = c.id)                                   AS maquinas_total,
  (SELECT COUNT(*) FROM maquinas m WHERE m.cliente_id = c.id AND m.estado = 'encendida')        AS maquinas_activas,
  (SELECT COUNT(*) FROM alertas a JOIN maquinas m ON m.id = a.maquina_id
     WHERE m.cliente_id = c.id)                                                                 AS alertas_total,
  (SELECT COUNT(*) FROM alertas a JOIN maquinas m ON m.id = a.maquina_id
     WHERE m.cliente_id = c.id AND a.estado = 'resuelta')                                       AS alertas_resueltas,
  (SELECT COUNT(*) FROM vulnerabilidades v JOIN maquinas m ON m.id = v.maquina_id
     WHERE m.cliente_id = c.id)                                                                 AS vuln_total,
  (SELECT COUNT(*) FROM vulnerabilidades v JOIN maquinas m ON m.id = v.maquina_id
     WHERE m.cliente_id = c.id AND v.estado IN ('corregida','verificada'))                      AS vuln_corregidas,
  (SELECT COUNT(*) FROM backups b JOIN maquinas m ON m.id = b.maquina_id
     WHERE m.cliente_id = c.id)                                                                 AS backups_total,
  (SELECT COUNT(*) FROM backups b JOIN maquinas m ON m.id = b.maquina_id
     WHERE m.cliente_id = c.id AND b.resultado = 'correcto')                                    AS backups_correctos
FROM clientes c;

-- Circular grande: vulnerabilidades por riesgo
CREATE VIEW v_vuln_por_riesgo AS
SELECT m.cliente_id, v.riesgo, COUNT(*) AS total
FROM vulnerabilidades v
JOIN maquinas m ON m.id = v.maquina_id
GROUP BY m.cliente_id, v.riesgo;

-- Lista de últimas alertas (el PHP añade ORDER BY fecha DESC LIMIT 5)
CREATE VIEW v_alertas_detalle AS
SELECT a.id, m.cliente_id, m.nombre AS maquina, a.origen, a.descripcion,
       a.gravedad, a.estado, a.fecha
FROM alertas a
JOIN maquinas m ON m.id = a.maquina_id;

-- Gráfico de líneas (consulta para el PHP, con :cliente = id del cliente):
-- SELECT
--     DATE(h.fecha) AS dia,
--     HOUR(h.fecha) AS hora,
--     ROUND(AVG(h.cpu_pct), 1) AS cpu,
--     ROUND(AVG(h.ram_pct), 1) AS ram,
--     ROUND(AVG(h.disco_pct), 1) AS disco
-- FROM metricas_historico h
-- JOIN maquinas m ON m.id = h.maquina_id
-- WHERE m.cliente_id = 1
--   AND h.fecha >= NOW() - INTERVAL 7 DAY
-- GROUP BY DATE(h.fecha), HOUR(h.fecha)
-- ORDER BY dia, hora;

-- =====================================================================
-- 3. DATOS DE EJEMPLO · infraestructura (según docs/arquitectura.md)
-- =====================================================================

INSERT INTO clientes (nombre, descripcion) VALUES
  ('Clínica Dental SonrisaViva', 'Centro médico privado ficticio. Caso práctico del proyecto.');

-- Contraseñas: se generan desde PHP con password_hash(); aquí queda un marcador
INSERT INTO usuarios (cliente_id, nombre, email, password_hash, rol) VALUES
  (NULL, 'Admin CIVEX', 'apellido',  'admin@civex.local',        'PENDIENTE_HASH', 'admin_civex'),
  (1,    'Usuario Demo', 'apellido', 'demo@sonrisaviva.local',   'PENDIENTE_HASH', 'cliente');

INSERT INTO maquinas
  (cliente_id, nombre, ip_principal, ip_secundaria, sistema_operativo, tipo, red, funcion, estado, ultima_actualizacion)
VALUES
  (1,    'pve01',      '192.168.111.201', NULL,          'Proxmox VE', 'host', 'Gestión',   'Host Proxmox',                'encendida',    NOW()),
  (1,    'FW-01',      '192.168.111.202', NULL,          'Linux',      'vm',   'Gestión',   'Firewall + Suricata',         'encendida',    NOW()),
  (1,    'DNS-01',     '10.10.10.10',     NULL,          'Linux',      'vm',   'Interna',   'Servidor DNS',                'encendida',    NOW()),
  (1,    'CLINICA-01', '10.10.10.20',     NULL,          'Linux',      'vm',   'Interna',   'Servidor interno MariaDB',    'desconectada', NOW() - INTERVAL 3 HOUR),
  (1,    'WEB-01',     '10.10.11.10',     NULL,          'Linux',      'vm',   'DMZ',       'Servidor web de citas',       'encendida',    NOW()),
  (1,    'MON-01',     '10.10.10.40',     NULL,          'Linux',      'vm',   'Interna',   'Prometheus + Grafana',        'encendida',    NOW());

INSERT INTO servicios (maquina_id, nombre, estado, ultima_comprobacion) VALUES
  (1, 'Proxmox',    'disponible', NOW()),
  (2, 'Suricata',   'disponible', NOW()),
  (3, 'DNS',        'disponible', NOW()),
  (4, 'MariaDB',    'caido',      NOW() - INTERVAL 3 HOUR),
  (5, 'Web HTTPS',  'disponible', NOW()),
  (6, 'Prometheus', 'disponible', NOW());

INSERT INTO metricas_actuales
  (maquina_id, cpu_pct, ram_usada_mb, ram_total_mb, disco_pct, red_entrada_bytes, red_salida_bytes, uptime_seg, actualizado_en)
VALUES
  (1, 18.40, 9800, 16384, 41.00, 5200000, 3100000, 864000, NOW()),
  (2, 12.10,  410,  1024, 35.50,  982000,  760000, 432000, NOW()),
  (3,  4.30,  180,   512, 22.80,  120000,   98000, 432000, NOW()),
  (4, 61.70, 1630,  2048, 74.20, 2400000, 1900000, 100000, NOW() - INTERVAL 3 HOUR),
  (5, 35.70,  620,  1024, 48.20,  152400,   87200, 300000, NOW()),
  (6, 22.90,  900,  2048, 52.60,  310000,  205000, 300000, NOW());

-- Histórico de ejemplo: FW-01, DNS-01 y WEB-01
INSERT INTO metricas_historico (maquina_id, fecha, cpu_pct, ram_pct, disco_pct) VALUES
  (2, NOW() - INTERVAL 180 MINUTE, 10.0, 38.0, 35.0), (2, NOW() - INTERVAL 120 MINUTE, 14.0, 40.0, 35.2),
  (2, NOW() - INTERVAL  60 MINUTE, 22.0, 41.0, 35.4), (2, NOW() - INTERVAL   5 MINUTE, 12.0, 40.0, 35.5),
  (3, NOW() - INTERVAL 180 MINUTE,  3.0, 33.0, 22.5), (3, NOW() - INTERVAL 120 MINUTE,  4.0, 34.0, 22.6),
  (3, NOW() - INTERVAL  60 MINUTE,  5.0, 35.0, 22.7), (3, NOW() - INTERVAL   5 MINUTE,  4.0, 35.0, 22.8),
  (5, NOW() - INTERVAL 180 MINUTE, 28.0, 55.0, 48.0), (5, NOW() - INTERVAL 120 MINUTE, 41.0, 58.0, 48.1),
  (5, NOW() - INTERVAL  60 MINUTE, 52.0, 61.0, 48.1), (5, NOW() - INTERVAL   5 MINUTE, 36.0, 60.0, 48.2);

-- =====================================================================
-- 4. DATOS DE EJEMPLO · seguridad
-- =====================================================================

INSERT INTO alertas
  (maquina_id, origen, regla_id, tipo, descripcion, gravedad, ip_origen, ip_destino, puerto_origen, puerto_destino, fecha, estado)
VALUES
  (2, 'wazuh',    '5710',      'Autenticación', 'Intentos de autenticación SSH fallidos',        'alta',  '192.168.111.221', '192.168.111.202', 50122, 22,  NOW() - INTERVAL 20 MINUTE, 'nueva'),
  (5, 'suricata', 'SURI-1001', 'Red',           'Escaneo de puertos detectado',                  'media', '10.10.30.10',     '10.10.11.10',     44211, 443, NOW() - INTERVAL 55 MINUTE, 'nueva'),
  (4, 'wazuh',    'WAZ-2001',  'Servicio',      'Servicio MariaDB detenido',                     'media', NULL,              NULL,              NULL,  NULL, NOW() - INTERVAL 3 HOUR,    'investigando'),
  (3, 'wazuh',    'WAZ-3001',  'Configuración', 'Cambio en la configuración del servicio DNS',   'baja',  NULL,              NULL,              NULL,  NULL, NOW() - INTERVAL 5 HOUR,    'nueva'),
  (2, 'suricata', 'SURI-1002', 'Red',           'Tráfico bloqueado hacia la DMZ',                'baja',  '10.10.30.10',     '10.10.11.10',     51200, 80,  NOW() - INTERVAL 1 DAY,     'resuelta'),
  (5, 'wazuh',    'WAZ-4001',  'Acceso',        'Inicio de sesión de administrador fuera de horario', 'media', '10.10.10.40', '10.10.11.10',  40022, 22,  NOW() - INTERVAL 2 DAY,     'resuelta');

INSERT INTO escaneos (herramienta, objetivo, maquina_id, fecha, resumen) VALUES
  ('Nmap', '192.168.111.202', 2, NOW() - INTERVAL 2 DAY, 'Puerto 22 accesible desde la red de gestión.'),
  ('Nmap', '10.10.11.10',     5, NOW() - INTERVAL 2 DAY, 'Servicios HTTP y HTTPS expuestos en la DMZ.');

INSERT INTO vulnerabilidades
  (codigo, maquina_id, escaneo_id, alerta_id, nombre, descripcion, riesgo, evidencia, recomendacion, estado, detectada_en, verificada_en)
VALUES
  ('VULN-001', 2, 1, 1,    'Servicio SSH expuesto',
     'Se ha detectado un servicio SSH accesible.', 'media',
     'Puerto 22/tcp abierto.', 'Restringir el acceso SSH a administradores.', 'pendiente', NOW() - INTERVAL 2 DAY, NULL),
  ('VULN-002', 5, 2, NULL, 'Cabeceras de seguridad HTTP ausentes',
     'El servidor web no envía cabeceras de seguridad.', 'baja',
     'Respuesta HTTP sin cabeceras de seguridad.', 'Añadir cabeceras de seguridad en el servidor web.', 'corregida', NOW() - INTERVAL 2 DAY, NULL),
  ('VULN-003', 4, NULL, NULL, 'MariaDB accesible desde la DMZ',
     'La base de datos de la clínica es alcanzable desde la red de la DMZ.', 'critica',
     'Conexión al puerto 3306 desde WEB-01.', 'Limitar el acceso con reglas de firewall.', 'en_correccion', NOW() - INTERVAL 1 DAY, NULL),
  ('VULN-004', 3, NULL, NULL, 'Transferencia de zona DNS sin restringir',
     'El servidor DNS permite transferencias de zona a cualquier equipo.', 'alta',
     'Transferencia de zona completada desde KALI-01.', 'Permitir transferencias solo al servidor esclavo.', 'pendiente', NOW() - INTERVAL 1 DAY, NULL),
  ('VULN-005', 5, NULL, NULL, 'Configuración TLS débil',
     'El servidor web admite protocolos TLS obsoletos.', 'alta',
     'Protocolo TLS antiguo aceptado.', 'Deshabilitar protocolos obsoletos.', 'pendiente', NOW() - INTERVAL 1 DAY, NULL);

INSERT INTO incidencias
(maquina_id, titulo, descripcion, prioridad, estado,
 responsable_id, alerta_id, vulnerabilidad_id)
VALUES
(4, 'MariaDB sin servicio en CLINICA-01',
 'El servicio dejó de responder.',
 'alta', 'en_curso', 1, 3, 3),

(2, 'Acceso SSH expuesto en FW-01',
 'Pendiente de restringir el acceso.',
 'media', 'abierta', 1, 1, 1);

INSERT INTO backups (maquina_id, fecha, resultado, tamano_mb, ubicacion, prueba_restauracion_en) VALUES
  (4, NOW() - INTERVAL 1 DAY,  'correcto', 2400, 'almacen-backups', NOW() - INTERVAL 7 DAY),
  (4, NOW() - INTERVAL 2 DAY,  'fallido',  NULL, 'almacen-backups', NULL),
  (4, NOW() - INTERVAL 3 DAY,  'correcto', 2380, 'almacen-backups', NULL),
  (5, NOW() - INTERVAL 1 DAY,  'correcto',  860, 'almacen-backups', NULL),
  (5, NOW() - INTERVAL 2 DAY,  'correcto',  855, 'almacen-backups', NULL),
  (3, NOW() - INTERVAL 1 DAY,  'correcto',  120, 'almacen-backups', NULL),
  (3, NOW() - INTERVAL 2 DAY,  'correcto',  118, 'almacen-backups', NULL),
  (2, NOW() - INTERVAL 1 DAY,  'correcto',  310, 'almacen-backups', NULL);

INSERT INTO informes (cliente_id, titulo, tipo, fecha, archivo, estado) VALUES
  (1, 'Auditoría inicial SonrisaViva', 'auditoria',        CURDATE() - INTERVAL 7 DAY, 'informes/auditoria-inicial.pdf', 'publicado'),
  (1, 'Informe de vulnerabilidades',   'vulnerabilidades', CURDATE() - INTERVAL 1 DAY, 'informes/vulnerabilidades.pdf',  'publicado'),
  (1, 'Informe mensual',               'mensual',          CURDATE(),                  NULL,                             'borrador');

-- =====================================================================
-- 5. USUARIO DE LA APLICACIÓN (mínimos permisos; NO usar root desde PHP)
--    Cambia la contraseña y descomenta.
-- =====================================================================
-- CREATE USER 'civex_app'@'localhost' IDENTIFIED BY 'CAMBIA_ESTA_CLAVE';
-- GRANT SELECT, INSERT, UPDATE, DELETE ON civex.* TO 'civex_app'@'localhost';
-- FLUSH PRIVILEGES;

-- Comprobación rápida:
-- SELECT * FROM v_kpis_cliente;
-- SELECT * FROM v_vuln_por_riesgo;
