-- ==============================================================================
-- TALLER PRÁCTICO: TRIGGERS Y EVENTOS EN MYSQL (BancoDB) - SOLUCIONARIO
-- ==============================================================================
-- Objetivo: Comprender la creación y funcionamiento de Triggers (reactividad en
-- tiempo real) y Eventos (programación temporal de tareas) sobre la base de datos BancoDB.
-- ==============================================================================

USE BancoDB;

-- ------------------------------------------------------------------------------
-- PARTE 0: TABLAS DE AUDITORÍA Y MÉTRICAS (Estructura de Soporte)
-- ------------------------------------------------------------------------------

-- Tabla para auditar cambios de saldo en tiempo real (Usada por el Trigger)
DROP TABLE IF EXISTS auditoria_saldos;
CREATE TABLE IF NOT EXISTS auditoria_saldos (
    id_log INT AUTO_INCREMENT PRIMARY KEY,
    cuenta_id INT NOT NULL,
    saldo_anterior DECIMAL(10,2) NOT NULL,
    saldo_nuevo DECIMAL(10,2) NOT NULL,
    usuario VARCHAR(100) NOT NULL,
    fecha_modificacion TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (cuenta_id) REFERENCES cuentas(cuenta_id)
);

-- Tabla para guardar métricas consolidadas del sistema (Usada por el Evento)
DROP TABLE IF EXISTS metricas_diarias;
CREATE TABLE IF NOT EXISTS metricas_diarias (
    id_metrica INT AUTO_INCREMENT PRIMARY KEY,
    fecha_metrica DATE NOT NULL,
    total_cuentas INT NOT NULL,
    saldo_total_sistema DECIMAL(12,2) NOT NULL,
    fecha_registro TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Asegurar que el programador de eventos esté encendido en el servidor
SET GLOBAL event_scheduler = ON;

-- Asegurar que 'cuentas' tenga la columna 'estado' que usan los eventos de este taller
-- (si tu tabla ya la tiene, este ALTER no hace nada dañino porque se valida antes)
SET @col_existe := (
    SELECT COUNT(*) FROM INFORMATION_SCHEMA.COLUMNS
    WHERE TABLE_SCHEMA = 'BancoDB' AND TABLE_NAME = 'cuentas' AND COLUMN_NAME = 'estado'
);
SET @sql_alter := IF(@col_existe = 0,
    'ALTER TABLE cuentas ADD COLUMN estado VARCHAR(20) NOT NULL DEFAULT ''Activa''',
    'SELECT ''La columna estado ya existe, no se requiere ALTER'' AS info'
);
PREPARE stmt FROM @sql_alter;
EXECUTE stmt;
DEALLOCATE PREPARE stmt;

-- ==============================================================================
-- PARTE 1: DEMOSTRACIÓN GUIADA EN CLASE (EXPLICACIÓN DEL PROFESOR)
-- ==============================================================================

-- ------------------------------------------------------------------------------
-- 1.1 TRIGGER DEMOSTRACIÓN: Auditoría Automática de Cambios de Saldo
-- ------------------------------------------------------------------------------
DELIMITER //

DROP TRIGGER IF EXISTS trg_auditar_cambio_saldo //

CREATE TRIGGER trg_auditar_cambio_saldo
AFTER UPDATE ON cuentas
FOR EACH ROW
BEGIN
    IF OLD.saldo <> NEW.saldo THEN
        INSERT INTO auditoria_saldos (
            cuenta_id,
            saldo_anterior,
            saldo_nuevo,
            usuario
        )
        VALUES (
            NEW.cuenta_id,
            OLD.saldo,
            NEW.saldo,
            USER()
        );
    END IF;
END //

DELIMITER ;

-- ------------------------------------------------------------------------------
-- 1.2 EVENTO DEMOSTRACIÓN: Resumen Periódico de Métricas del Banco
-- ------------------------------------------------------------------------------
DELIMITER //

DROP EVENT IF EXISTS evt_registrar_metricas_diarias //

CREATE EVENT evt_registrar_metricas_diarias
ON SCHEDULE EVERY 1 DAY
STARTS CURRENT_TIMESTAMP
ON COMPLETION PRESERVE
COMMENT 'Consolida el saldo total y cantidad de cuentas activas diariamente'
DO
BEGIN
    INSERT INTO metricas_diarias (fecha_metrica, total_cuentas, saldo_total_sistema)
    SELECT
        CURDATE(),
        COUNT(cuenta_id),
        IFNULL(SUM(saldo), 0.00)
    FROM cuentas
    WHERE estado = 'Activa';
END //

DELIMITER ;

-- ==============================================================================
-- PARTE 2: RETO AUTÓNOMO - SOLUCIÓN
-- ==============================================================================

-- ------------------------------------------------------------------------------
-- EJERCICIO 1 (TRIGGER): Validación de Transferencias (BEFORE INSERT)
-- ------------------------------------------------------------------------------
DELIMITER //

DROP TRIGGER IF EXISTS trg_validar_transferencia //

CREATE TRIGGER trg_validar_transferencia
BEFORE INSERT ON historial_transferencias
FOR EACH ROW
BEGIN
    -- Regla 1: el monto debe ser estrictamente mayor a cero
    IF NEW.monto <= 0 THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'El monto de la transferencia debe ser mayor a cero';
    END IF;

    -- Regla 2: la cuenta origen y destino no pueden ser la misma
    IF NEW.cuenta_origen = NEW.cuenta_destino THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'La cuenta de origen y destino no pueden ser iguales';
    END IF;
END //

DELIMITER ;

-- PRUEBAS DEL TRIGGER trg_validar_transferencia
-- Caso 1 - Fallido: monto igual a cero (debe lanzar el error de SIGNAL)
-- INSERT INTO historial_transferencias (cuenta_origen, cuenta_destino, monto) VALUES (1, 2, 0);

-- Caso 2 - Fallido: cuenta origen igual a cuenta destino (debe lanzar el error de SIGNAL)
-- INSERT INTO historial_transferencias (cuenta_origen, cuenta_destino, monto) VALUES (1, 1, 500);

-- Caso 3 - Exitoso: cumple ambas reglas de negocio
INSERT INTO historial_transferencias (cuenta_origen, cuenta_destino, monto) VALUES (1, 2, 500);
SELECT * FROM historial_transferencias;


-- ------------------------------------------------------------------------------
-- EJERCICIO 2 (EVENTO): Inactivación Automática de Cuentas en Cero
-- ------------------------------------------------------------------------------
DELIMITER //

DROP EVENT IF EXISTS evt_inactivar_cuentas_vacias //

CREATE EVENT evt_inactivar_cuentas_vacias
ON SCHEDULE EVERY 1 DAY
STARTS CURRENT_TIMESTAMP
ON COMPLETION PRESERVE
COMMENT 'Inactiva automáticamente las cuentas con saldo en cero'
DO
BEGIN
    UPDATE cuentas
    SET estado = 'Inactiva'
    WHERE saldo = 0.00
      AND estado = 'Activa';
END //

DELIMITER ;

-- VERIFICACIÓN DEL EVENTO
SHOW EVENTS FROM BancoDB;

-- Para probar el efecto sin esperar el intervalo programado, se puede ejecutar
-- manualmente la misma lógica que ejecuta el evento:
-- UPDATE cuentas SET saldo = 0.00 WHERE cuenta_id = 2;   -- deja una cuenta en cero
-- UPDATE cuentas SET estado = 'Inactiva' WHERE saldo = 0.00 AND estado = 'Activa';
-- SELECT * FROM cuentas;