# MySQL-II — Talleres Prácticos

Repositorio de talleres prácticos de bases de datos con MySQL, desarrollados sobre el dominio de un sistema bancario (**BancoDB**). Cada carpeta corresponde a un taller independiente, con su script SQL y las capturas de evidencia de su ejecución.

## Contenido

| Carpeta | Taller | Descripción |
|---|---|---|
| `seguridad-permisos/` | Seguridad, Permisos y Prevención de SQL Injection | Gestión de usuarios y roles (`GRANT`/`REVOKE`), privilegios granulares por columna, y uso de sentencias preparadas (`PREPARE`/`EXECUTE`) para prevenir SQL Injection. |
| `reto-1/` | Transferencia Bancaria Segura con Procedimientos Almacenados | Procedimiento `TransferirFondos` con parámetros `IN`/`OUT`, transacciones (`START TRANSACTION`, `COMMIT`, `ROLLBACK`), manejo de errores con `DECLARE EXIT HANDLER` y registro de auditoría. |
| `taller-triggers-eventos/` | Triggers y Eventos | Trigger de auditoría de cambios de saldo (`AFTER UPDATE`), trigger de validación de transferencias con `SIGNAL SQLSTATE '45000'` (`BEFORE INSERT`), evento de métricas diarias y evento de inactivación automática de cuentas en cero. |
| `taller-optimizacion/` | Optimización de Consultas y Rendimiento | Diagnóstico de consultas no-sargables con `EXPLAIN ANALYZE`, índices cubrientes (covering index) e índices compuestos para optimizar JOINs y filtros combinados. |
| `taller-funciones/` | Funciones Definidas por el Usuario | Funciones `DETERMINISTIC` y `READS SQL DATA`: cálculo de impuesto 4x1000, total de retiros por periodo, proyección de rendimientos de CDT, y evaluación de elegibilidad de crédito. |

## Estructura de cada carpeta

```
taller-x/
├── taller-x.sql          # Script SQL completo del taller
└── capturas/              # Evidencias de ejecución
    ├── 01_tablas_creadas.png
    ├── 02_procedimiento_o_funcion.png
    ├── 03_caso_exitoso.png
    ├── 04_caso_fallido.png
    └── 05_auditoria.png
```

## Requisitos

- MySQL 8.0 o superior
- Cliente SQL (se usó **DBeaver** para el desarrollo y las capturas)
- Programador de eventos activo para los talleres que usan `CREATE EVENT`:
  ```sql
  SET GLOBAL event_scheduler = ON;
  ```

## Cómo ejecutar un taller

1. Abrir el script `.sql` de la carpeta correspondiente en el cliente SQL.
2. Ejecutar el script completo de principio a fin (algunos scripts recrean tablas con `DROP TABLE IF EXISTS`, así que el orden importa).
3. Revisar las capturas de la carpeta `capturas/` para ver la evidencia de cada paso.

## Convención de commits

Este repositorio sigue [Conventional Commits](https://www.conventionalcommits.org/):

- `feat`: nuevo taller o funcionalidad SQL agregada
- `fix`: corrección de un error en un script existente
- `docs`: cambios en documentación (README, comentarios)
- `chore`: tareas de mantenimiento (inicialización del repo, configuración)

## Autor

Estudiante — Curso MySQL-II
