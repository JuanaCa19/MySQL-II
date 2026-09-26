-- ==============================================================================
-- TALLER PRÁCTICO: OPTIMIZACIÓN DE CONSULTAS Y RENDIMIENTO EN MYSQL (BancoDB)
-- SOLUCIONARIO
-- ==============================================================================

CREATE DATABASE IF NOT EXISTS BancoDB;
USE BancoDB;

-- ------------------------------------------------------------------------------
-- PARTE 0: ESTRUCTURA DE TABLAS Y POBLAMIENTO DE DATOS MASIVOS
-- ------------------------------------------------------------------------------

DROP TABLE IF EXISTS historial_transferencias;
DROP TABLE IF EXISTS cuentas;

CREATE TABLE cuentas (
    id_cuenta INT PRIMARY KEY AUTO_INCREMENT,
    titular VARCHAR(100) NOT NULL,
    tipo_cuenta VARCHAR(20) NOT NULL DEFAULT 'Ahorros',
    saldo DECIMAL(12,2) NOT NULL DEFAULT 0.00,
    estado VARCHAR(20) NOT NULL DEFAULT 'Activa',
    fecha_apertura DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE historial_transferencias (
    id_transferencia INT AUTO_INCREMENT PRIMARY KEY,
    cuenta_origen INT NOT NULL,
    cuenta_destino INT NOT NULL,
    monto DECIMAL(12, 2) NOT NULL,
    estado_transferencia VARCHAR(20) NOT NULL DEFAULT 'Exitosa',
    fecha DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (cuenta_origen) REFERENCES cuentas(id_cuenta),
    FOREIGN KEY (cuenta_destino) REFERENCES cuentas(id_cuenta)
);

DELIMITER //
CREATE PROCEDURE CargarDatosPrueba()
BEGIN
    DECLARE i INT DEFAULT 1;

    WHILE i <= 1000 DO
        INSERT INTO cuentas (titular, tipo_cuenta, saldo, estado, fecha_apertura)
        VALUES (
            CONCAT('Cliente_', i),
            IF(i % 2 = 0, 'Ahorros', 'Corriente'),
            ROUND(RAND() * 10000000, 2),
            IF(i % 10 = 0, 'Bloqueada', 'Activa'),
            DATE_SUB(NOW(), INTERVAL FLOOR(RAND() * 365) DAY)
        );
        SET i = i + 1;
    END WHILE;

    SET i = 1;
    WHILE i <= 10000 DO
        INSERT INTO historial_transferencias (cuenta_origen, cuenta_destino, monto, estado_transferencia, fecha)
        VALUES (
            FLOOR(1 + RAND() * 999),
            FLOOR(1 + RAND() * 999),
            ROUND(1000 + RAND() * 500000, 2),
            IF(i % 15 = 0, 'Fallida', 'Exitosa'),
            DATE_SUB(NOW(), INTERVAL FLOOR(RAND() * 180) DAY)
        );
        SET i = i + 1;
    END WHILE;
END //
DELIMITER ;

CALL CargarDatosPrueba();
DROP PROCEDURE IF EXISTS CargarDatosPrueba;

-- ==============================================================================
-- PARTE 1: DEMOSTRACIÓN GUIADA EN CLASE (PROFESOR)
-- ==============================================================================

EXPLAIN ANALYZE
SELECT id_transferencia, cuenta_origen, monto, fecha
FROM historial_transferencias
WHERE estado_transferencia = 'Exitosa'
  AND fecha >= '2026-01-01 00:00:00';

CREATE INDEX idx_transf_estado_fecha ON historial_transferencias(estado_transferencia, fecha);

EXPLAIN ANALYZE
SELECT id_transferencia, cuenta_origen, monto, fecha
FROM historial_transferencias
WHERE estado_transferencia = 'Exitosa'
  AND fecha >= '2026-01-01 00:00:00';

-- ==============================================================================
-- PARTE 2: EJERCICIOS PRÁCTICOS - SOLUCIÓN
-- ==============================================================================

-- ------------------------------------------------------------------------------
-- EJERCICIO 1: Diagnóstico de "Non-Sargable Query" (Uso de Funciones en WHERE)
-- ------------------------------------------------------------------------------

-- BASE INEFICIENTE (dada en el enunciado):
EXPLAIN ANALYZE
SELECT *
FROM historial_transferencias
WHERE DATE(fecha) = '2026-02-15';

-- 1. POR QUÉ NO SE USA idx_transf_estado_fecha:
--    a) El índice compuesto tiene como columna líder 'estado_transferencia'. Como esta
--       consulta no filtra por 'estado_transferencia', MySQL no puede aprovechar ese
--       índice para buscar por 'fecha' (solo podría usarlo si el filtro incluyera
--       la columna líder o se hiciera un index skip scan, no soportado por defecto).
--    b) Adicionalmente, envolver la columna 'fecha' en la función DATE() la vuelve
--       "no sargable": MySQL debe calcular DATE(fecha) fila por fila antes de poder
--       comparar, así que no puede usar ningún índice sobre 'fecha' para hacer una
--       búsqueda por rango; termina en un Table Scan completo.

-- 2. REESCRITURA SARGABLE (rango de fechas sin envolver la columna en funciones):
EXPLAIN ANALYZE
SELECT *
FROM historial_transferencias
WHERE fecha >= '2026-02-15 00:00:00'
  AND fecha <  '2026-02-16 00:00:00';

-- Índice dedicado a 'fecha' para que la reescritura sargable pueda usarlo:
CREATE INDEX idx_transf_fecha ON historial_transferencias(fecha);

-- 3. COMPARACIÓN DE PLANES: re-ejecutar y comparar el costo/tipo de acceso
EXPLAIN ANALYZE
SELECT *
FROM historial_transferencias
WHERE fecha >= '2026-02-15 00:00:00'
  AND fecha <  '2026-02-16 00:00:00';
-- Se espera pasar de "Table scan" a un acceso por rango (range scan) sobre idx_transf_fecha.


-- ------------------------------------------------------------------------------
-- EJERCICIO 2: Optimización mediante Índices Cubrientes (Covering Index)
-- ------------------------------------------------------------------------------

-- BASE INEFICIENTE (dada en el enunciado):
EXPLAIN ANALYZE
SELECT titular, saldo, tipo_cuenta
FROM cuentas
WHERE estado = 'Activa';

-- 1. SELECT * vs columnas específicas:
--    SELECT * obliga a MySQL a leer todas las columnas de cada fila desde la tabla
--    base (incluyendo columnas no usadas), lo que aumenta E/S y descarta cualquier
--    posibilidad de que un índice cubra la consulta por sí solo. Seleccionar solo
--    los campos necesarios permite que, si existe el índice adecuado, la consulta
--    se resuelva completamente desde el índice sin tocar la tabla.

-- 2. ÍNDICE CUBRIENTE: incluye la columna del WHERE y las columnas retornadas
CREATE INDEX idx_cuentas_estado_covering
    ON cuentas(estado, titular, saldo, tipo_cuenta);

-- 3. VERIFICACIÓN: debe aparecer "Using index" (no necesita ir a la tabla base)
EXPLAIN ANALYZE
SELECT titular, saldo, tipo_cuenta
FROM cuentas
WHERE estado = 'Activa';


-- ------------------------------------------------------------------------------
-- EJERCICIO 3: Optimización de Filtros Combinados y JOINs
-- ------------------------------------------------------------------------------

-- BASE INEFICIENTE (dada en el enunciado):
EXPLAIN ANALYZE
SELECT c.id_cuenta, c.titular, ht.id_transferencia, ht.monto, ht.fecha
FROM cuentas c
JOIN historial_transferencias ht ON c.id_cuenta = ht.cuenta_origen
WHERE c.estado = 'Activa'
  AND ht.monto > 300000.00;

-- 1. TABLA CON FULL TABLE SCAN:
--    'historial_transferencias' es la tabla más grande (10,000 filas) y no tiene
--    ningún índice que combine 'cuenta_origen' (columna del JOIN) con 'monto'
--    (columna del filtro), por lo que MySQL termina escaneándola por completo
--    para cada cuenta activa evaluada en el JOIN.

-- 2. ÍNDICES NECESARIOS:
-- a) Índice en 'cuentas' para filtrar rápido las cuentas activas (columna del WHERE)
CREATE INDEX idx_cuentas_estado ON cuentas(estado);

-- b) Índice compuesto en 'historial_transferencias' para soportar el JOIN y el filtro
CREATE INDEX idx_transf_origen_monto ON historial_transferencias(cuenta_origen, monto);

-- 3. JUSTIFICACIÓN DEL ORDEN DE COLUMNAS:
--    'cuenta_origen' va primero porque es la columna de igualdad usada en el JOIN
--    (c.id_cuenta = ht.cuenta_origen): al ubicarla primero, MySQL puede saltar
--    directamente al bloque de filas de cada cuenta origen. 'monto' va segundo
--    porque sobre él se aplica un filtro de rango (> 300000.00); en un índice
--    compuesto, las columnas de igualdad deben preceder a las columnas de rango
--    para que ambas condiciones se aprovechen en una sola búsqueda por el índice.

-- VERIFICACIÓN FINAL
EXPLAIN ANALYZE
SELECT c.id_cuenta, c.titular, ht.id_transferencia, ht.monto, ht.fecha
FROM cuentas c
JOIN historial_transferencias ht ON c.id_cuenta = ht.cuenta_origen
WHERE c.estado = 'Activa'
  AND ht.monto > 300000.00;

-- ==============================================================================
-- FIN DEL TALLER
-- ==============================================================================
