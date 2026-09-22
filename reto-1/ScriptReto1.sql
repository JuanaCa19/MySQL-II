-- ============================================================================
-- TALLER: TRANSFERENCIA BANCARIA SEGURA CON PROCEDIMIENTOS ALMACENADOS
-- Base de Datos: BancoDB
-- ============================================================================

-- ----------------------------------------------------------------------------
-- PASO 1: Crear la Base de Datos
-- ----------------------------------------------------------------------------
DROP DATABASE IF EXISTS BancoDB;
CREATE DATABASE BancoDB;
USE BancoDB;

-- ----------------------------------------------------------------------------
-- PASO 2: Crear las Tablas
-- ----------------------------------------------------------------------------

-- Tabla de cuentas bancarias
CREATE TABLE cuentas (
    id_cuenta INT PRIMARY KEY,
    titular VARCHAR(100),
    saldo DECIMAL(10,2)
);

-- Tabla de historial de transferencias
CREATE TABLE historial_transferencias (
    id_transferencia INT AUTO_INCREMENT PRIMARY KEY,
    cuenta_origen INT,
    cuenta_destino INT,
    monto DECIMAL(10,2),
    fecha TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Tabla de auditoría de operaciones
CREATE TABLE auditoria_operaciones (
    id_auditoria INT AUTO_INCREMENT PRIMARY KEY,
    cuenta_origen INT,
    cuenta_destino INT,
    monto DECIMAL(10,2),
    codigo_respuesta INT,
    mensaje VARCHAR(255),
    fecha TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- ----------------------------------------------------------------------------
-- PASO 3: Insertar Datos de Prueba
-- ----------------------------------------------------------------------------
INSERT INTO cuentas (id_cuenta, titular, saldo) VALUES
(1, 'Ana López', 5000.00),
(2, 'Carlos Pérez', 3000.00);

-- ----------------------------------------------------------------------------
-- PASO 4: Procedimiento Almacenado TransferirFondos
-- ----------------------------------------------------------------------------
DROP PROCEDURE IF EXISTS TransferirFondos;


CREATE PROCEDURE TransferirFondos(
    IN p_origen INT,
    IN p_destino INT,
    IN p_monto DECIMAL(10,2),
    OUT p_codigo_respuesta INT
)
BEGIN

    DECLARE v_saldo_origen DECIMAL(10,2) DEFAULT 0;
    DECLARE v_mensaje VARCHAR(255) DEFAULT '';

    -- Manejo de errores de base de datos (cualquier excepción SQL)
    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
        SET p_codigo_respuesta = 500;
        INSERT INTO auditoria_operaciones (cuenta_origen, cuenta_destino, monto, codigo_respuesta, mensaje)
        VALUES (p_origen, p_destino, p_monto, 500, 'Error de base de datos - transacción revertida');
    END;

    -- Inicia la transacción
    START TRANSACTION;

    -- Consulta el saldo disponible de la cuenta origen y bloquea la fila
    SELECT saldo INTO v_saldo_origen
    FROM cuentas
    WHERE id_cuenta = p_origen
    FOR UPDATE;

    -- Validar que la cuenta origen exista
    IF v_saldo_origen IS NULL THEN
        ROLLBACK;
        SET p_codigo_respuesta = 400;
        INSERT INTO auditoria_operaciones (cuenta_origen, cuenta_destino, monto, codigo_respuesta, mensaje)
        VALUES (p_origen, p_destino, p_monto, 400, 'Cuenta origen no existe');
        LEAVE proc;
    END IF;

    -- Validar saldo suficiente
    IF v_saldo_origen >= p_monto THEN

        -- 1. Restar saldo a la cuenta origen
        UPDATE cuentas
        SET saldo = saldo - p_monto
        WHERE id_cuenta = p_origen;

        -- 2. Sumar saldo a la cuenta destino
        UPDATE cuentas
        SET saldo = saldo + p_monto
        WHERE id_cuenta = p_destino;

        -- 3. Registrar la operación en historial_transferencias
        INSERT INTO historial_transferencias (cuenta_origen, cuenta_destino, monto)
        VALUES (p_origen, p_destino, p_monto);

        -- 4. Confirmar la transacción
        COMMIT;

        -- 5. Retornar código 200 (éxito)
        SET p_codigo_respuesta = 200;
        SET v_mensaje = 'Transferencia realizada exitosamente';

        INSERT INTO auditoria_operaciones (cuenta_origen, cuenta_destino, monto, codigo_respuesta, mensaje)
        VALUES (p_origen, p_destino, p_monto, 200, v_mensaje);

    ELSE
        -- Saldo insuficiente
        ROLLBACK;
        SET p_codigo_respuesta = 400;
        SET v_mensaje = 'Saldo insuficiente para realizar la transferencia';

        INSERT INTO auditoria_operaciones (cuenta_origen, cuenta_destino, monto, codigo_respuesta, mensaje)
        VALUES (p_origen, p_destino, p_monto, 400, v_mensaje);
    END IF;

end;



-- ----------------------------------------------------------------------------
-- PASO 5: Pruebas
-- ----------------------------------------------------------------------------

-- Caso Exitoso: transferencia de 1000 de la cuenta 1 a la cuenta 2
CALL TransferirFondos(1, 2, 1000, @codigo);
SELECT @codigo AS codigo_respuesta;

-- Verificar saldos actualizados
SELECT * FROM cuentas;

-- Caso Fallido: transferencia de 10000 (saldo insuficiente)
CALL TransferirFondos(1, 2, 10000, @codigo);
SELECT @codigo AS codigo_respuesta;

-- ----------------------------------------------------------------------------
-- Verificación de Evidencias
-- ----------------------------------------------------------------------------

-- Ver historial de transferencias (solo debe registrar la exitosa)
SELECT * FROM historial_transferencias;

-- Ver registro de auditoría (debe registrar ambas operaciones, éxito y fallo)
SELECT * FROM auditoria_operaciones;
