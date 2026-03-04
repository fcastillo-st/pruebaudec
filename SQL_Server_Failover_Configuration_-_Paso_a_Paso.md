# Configuración de FAILURE_CONDITION_LEVEL en SQL Server AlwaysOn - Guía Paso a Paso

## Resumen Ejecutivo

Esta guía proporciona un procedimiento paso a paso para configurar el parámetro `FAILURE_CONDITION_LEVEL` en SQL Server AlwaysOn Availability Groups, especialmente crucial para entornos con alta latencia o WAN donde los failovers prematuros por congestión de red de 5 segundos causan interrupciones innecesarias.

## Tabla de Contenidos

1. [Problema Identificado](#problema-identificado)
2. [Entendiendo FAILURE_CONDITION_LEVEL](#entendiendo-failure_condition_level)
3. [Diagnóstico Previo](#diagnóstico-previo)
4. [Procedimiento Paso a Paso](#procedimiento-paso-a-paso)
5. [Verificación y Validación](#verificación-y-validación)
6. [Monitoreo Post-Configuración](#monitoreo-post-configuración)
7. [Troubleshooting](#troubleshooting)

## Problema Identificado

### Síntoma Principal
- **Failovers inesperados** en SQL Server AlwaysOn cada 5 segundos durante congestión de red
- Los parámetros de red del clúster (`CrossSubnetThreshold`, `HealthCheckTimeout`) están configurados correctamente
- El problema persiste a pesar de configuraciones de red optimizadas

### Causa Root
El parámetro **`FAILURE_CONDITION_LEVEL`** está configurado en un nivel demasiado sensible, causando que SQL Server interprete congestiones temporales de red como fallos críticos.

## Entendiendo FAILURE_CONDITION_LEVEL

### Definición
El `FAILURE_CONDITION_LEVEL` determina qué tipos de eventos dentro del motor de SQL Server se consideran "fallos" suficientemente graves para iniciar un failover automático.

### Tabla de Niveles de Sensibilidad

| Nivel | Sensibilidad | Eventos que Gatillan Failover |
|-------|--------------|-------------------------------|
| **1** | **Baja** | Solo fallo del proceso de servidor (SQL Server Service stopped) |
| **2** | **Moderada** (Default) | Nivel 1 + Lease timeout + HealthCheckTimeout |
| **3** | **Media** | Nivel 2 + Fallos de procesos críticos (log writer, etc.) |
| **4** | **Alta** | Nivel 3 + Deadlocks + problemas de spinlocks |
| **5** | **Máxima** | Nivel 4 + Latencias de I/O + problemas de respuesta de red |

### ⚠️ Impacto por Nivel

- **Nivel 5**: Una congestión de red de 5 segundos = Failover inmediato
- **Nivel 4**: Deadlocks frecuentes pueden causar failovers innecesarios
- **Nivel 2**: Balance entre detección de fallos y estabilidad
- **Nivel 1**: Solo failovers por fallos catastróficos del servicio

## Diagnóstico Previo

### Paso 1: Verificar Configuración Actual

```sql
-- Consultar la configuración actual del Availability Group
SELECT 
    ag.name AS AvailabilityGroupName,
    ag.failure_condition_level,
    ag.health_check_timeout,
    ag.automated_backup_preference_desc
FROM sys.availability_groups ag;
```

### 📝 **Nota Importante sobre las Vistas del Sistema**

**Estructura correcta de las vistas de SQL Server AlwaysOn:**

- **`sys.availability_groups`**: Información básica de los Availability Groups
- **`sys.availability_replicas`**: Configuración estática de réplicas (contiene `replica_server_name`)
- **`sys.dm_hadr_availability_replica_states`**: Estado dinámico de réplicas (NO contiene `replica_server_name`)

**⚠️ IMPORTANTE:** Para obtener información completa, es necesario hacer JOIN entre `sys.availability_replicas` y `sys.dm_hadr_availability_replica_states` usando `replica_id`:

```sql
-- Estructura correcta del JOIN
FROM sys.availability_groups ag
INNER JOIN sys.availability_replicas ar ON ag.group_id = ar.group_id
INNER JOIN sys.dm_hadr_availability_replica_states ars ON ar.replica_id = ars.replica_id
```

**Columnas importantes:**
- `ar.replica_server_name` → Nombre del servidor (tabla estática)
- `ars.role_desc` → Rol actual PRIMARY/SECONDARY (vista dinámica)
- `ars.operational_state_desc` → Estado operacional actual (vista dinámica)

### 🔍 **Queries de Verificación Básicas (Siempre Funcionan)**

```sql
-- 1. Verificar si existen Availability Groups en esta instancia
SELECT 
    COUNT(*) AS CantidadAGs,
    CASE 
        WHEN COUNT(*) > 0 THEN 'Esta instancia tiene Availability Groups configurados'
        ELSE 'Esta instancia NO tiene Availability Groups'
    END AS Estado
FROM sys.availability_groups;

-- 2. Listar todos los AGs y sus configuraciones básicas
SELECT 
    name AS AvailabilityGroupName,
    failure_condition_level AS NivelCondicionFallo,
    health_check_timeout AS TimeoutSalud
FROM sys.availability_groups;

-- 3. Ver todas las réplicas configuradas (información estática)
SELECT 
    ag.name AS AvailabilityGroup,
    ar.replica_server_name AS Servidor,
    ar.endpoint_url AS Endpoint,
    ar.availability_mode_desc AS ModoDisponibilidad,
    ar.failover_mode_desc AS ModoFailover
FROM sys.availability_groups ag
INNER JOIN sys.availability_replicas ar ON ag.group_id = ar.group_id;
```

### Paso 2: Revisar Historial de Failovers

```sql
-- Revisar eventos de failover recientes
SELECT 
    ar.replica_server_name,
    ar.role_desc,
    ar.operational_state_desc,
    ar.connected_state_desc,
    ar.last_connect_error_description,
    ar.last_connect_error_timestamp
FROM sys.availability_replicas ar
INNER JOIN sys.availability_groups ag ON ar.group_id = ag.group_id;
```

### Paso 3: Analizar Logs de Eventos

```powershell
# PowerShell - Buscar eventos de failover en el log de SQL Server
Get-WinEvent -FilterHashtable @{
    LogName='Application'
    ProviderName='MSSQLSERVER'
    StartTime=(Get-Date).AddHours(-24)
} | Where-Object {$_.Message -like "*failover*" -or $_.Message -like "*availability*"}
```

## Procedimiento Paso a Paso

### Prerequisitos
- [ ] Acceso con privilegios de sysadmin en SQL Server
- [ ] Identificación del nombre del Availability Group
- [ ] Conexión a la instancia **primaria** actual
- [ ] Ventana de mantenimiento planificada (opcional, no requiere downtime)

### Paso 1: Conectar a la Instancia Primaria

```sql
-- Verificar que estás conectado a la instancia primaria (QUERY CORREGIDA)
SELECT 
    ag.name AS AvailabilityGroupName,
    ar.replica_server_name,
    ars.role_desc AS CurrentRole,
    @@SERVERNAME AS ConnectedTo,
    CASE 
        WHEN ars.role_desc = 'PRIMARY' AND ar.replica_server_name = @@SERVERNAME 
        THEN 'Conectado a la instancia primaria ✓'
        WHEN ars.role_desc = 'SECONDARY' AND ar.replica_server_name = @@SERVERNAME 
        THEN 'ADVERTENCIA: Conectado a instancia secundaria - Conectar a la primaria'
        ELSE 'Verificar conexión'
    END AS Status
FROM sys.availability_groups ag
INNER JOIN sys.availability_replicas ar ON ag.group_id = ar.group_id
INNER JOIN sys.dm_hadr_availability_replica_states ars ON ar.replica_id = ars.replica_id
WHERE ar.replica_server_name = @@SERVERNAME;

-- Query alternativa más simple para verificar si eres PRIMARY
SELECT 
    @@SERVERNAME AS ServidorActual,
    CASE 
        WHEN EXISTS (
            SELECT 1 
            FROM sys.availability_replicas ar
            INNER JOIN sys.dm_hadr_availability_replica_states ars ON ar.replica_id = ars.replica_id
            WHERE ars.role_desc = 'PRIMARY' 
            AND ar.replica_server_name = @@SERVERNAME
        ) 
        THEN 'PRIMARIO - Puedes ejecutar ALTER AVAILABILITY GROUP ✓'
        ELSE 'SECUNDARIO - Conectar a la instancia primaria'
    END AS EstadoInstancia;

-- Query simplificada que siempre funciona
SELECT 
    @@SERVERNAME AS MiServidor,
    'Ejecuta ALTER AVAILABILITY GROUP desde cualquier instancia del AG' AS Nota,
    'El comando se ejecutará en la instancia primaria automáticamente' AS Aclaracion;
```

### Paso 2: Documentar Configuración Actual

```sql
-- Backup de configuración actual para rollback
SELECT 
    name,
    failure_condition_level,
    health_check_timeout,
    automated_backup_preference_desc,
    GETDATE() as backup_timestamp
FROM sys.availability_groups
WHERE name = 'TU_AVAILABILITY_GROUP_NAME';  -- Reemplazar con nombre real
```

### Paso 3: Aplicar Nueva Configuración

```sql
-- EJEMPLO: Cambiar a nivel 1 (menos sensible)
-- Reemplazar 'TU_AVAILABILITY_GROUP_NAME' con el nombre real de tu AG

ALTER AVAILABILITY GROUP [TU_AVAILABILITY_GROUP_NAME] 
SET (FAILURE_CONDITION_LEVEL = 1);
GO

-- Mensaje de confirmación
PRINT 'FAILURE_CONDITION_LEVEL cambiado a nivel 1 - Configuración aplicada exitosamente';
```

### Paso 4: Configuración Opcional del Health Check Timeout

```sql
-- Opcional: Ajustar también el health check timeout si es necesario
-- Aumentar de 30000ms (30s) a 60000ms (60s) para mayor tolerancia

ALTER AVAILABILITY GROUP [TU_AVAILABILITY_GROUP_NAME] 
SET (HEALTH_CHECK_TIMEOUT = 60000);
GO

PRINT 'Health Check Timeout ajustado a 60 segundos';
```

## Verificación y Validación

### Paso 1: Confirmar Cambios Aplicados

```sql
-- Verificar que los cambios se aplicaron correctamente
SELECT 
    name AS AvailabilityGroupName,
    failure_condition_level AS NuevoNivel,
    health_check_timeout AS NuevoTimeout,
    GETDATE() AS FechaVerificacion
FROM sys.availability_groups
WHERE name = 'TU_AVAILABILITY_GROUP_NAME';
```

### Paso 2: Verificar Estado del AG

```sql
-- Confirmar que el AG sigue operacional (QUERY CORREGIDA CON JOINS CORRECTOS)
SELECT 
    ag.name AS AvailabilityGroupName,
    ar.replica_server_name AS ServidorReplica,
    ars.role_desc AS RolActual,
    ars.operational_state_desc AS EstadoOperacional,
    ars.connected_state_desc AS EstadoConexion,
    ars.synchronization_state_desc AS EstadoSincronizacion,
    ars.last_connect_error_description AS UltimoError
FROM sys.availability_groups ag
INNER JOIN sys.availability_replicas ar ON ag.group_id = ar.group_id
INNER JOIN sys.dm_hadr_availability_replica_states ars ON ar.replica_id = ars.replica_id
ORDER BY ars.role_desc DESC, ar.replica_server_name;

-- Query simplificada para ver solo información básica del servidor actual
SELECT 
    @@SERVERNAME AS ServidorConectado,
    ag.name AS AvailabilityGroup,
    ars.role_desc AS MiRol,
    ars.operational_state_desc AS EstadoOperacional
FROM sys.availability_groups ag
INNER JOIN sys.availability_replicas ar ON ag.group_id = ar.group_id
INNER JOIN sys.dm_hadr_availability_replica_states ars ON ar.replica_id = ars.replica_id
WHERE ar.replica_server_name = @@SERVERNAME;
```

### Paso 3: Verificar Sincronización de Bases de Datos

```sql
-- Confirmar estado de sincronización de bases de datos
SELECT 
    db.database_name,
    db.synchronization_state_desc,
    db.synchronization_health_desc,
    db.log_send_queue_size,
    db.redo_queue_size
FROM sys.dm_hadr_database_replica_states db
INNER JOIN sys.availability_replicas ar ON db.replica_id = ar.replica_id
WHERE ar.role_desc = 'PRIMARY';
```

## Monitoreo Post-Configuración

### Script de Monitoreo Continuo

```sql
-- Script para monitorear la estabilidad post-configuración
-- Ejecutar periódicamente durante las primeras 24-48 horas

DECLARE @StartTime DATETIME = DATEADD(HOUR, -1, GETDATE());

SELECT 
    'Configuración Actual' AS Categoria,
    name AS AvailabilityGroup,
    failure_condition_level AS Nivel,
    health_check_timeout AS Timeout
FROM sys.availability_groups
WHERE name = 'TU_AVAILABILITY_GROUP_NAME'

UNION ALL

SELECT 
    'Estado de Réplicas' AS Categoria,
    ar.replica_server_name AS AvailabilityGroup,
    CAST(ars.role_desc AS VARCHAR(20)) AS Nivel,
    ars.operational_state_desc AS Timeout
FROM sys.availability_groups ag
INNER JOIN sys.availability_replicas ar ON ag.group_id = ar.group_id
INNER JOIN sys.dm_hadr_availability_replica_states ars ON ar.replica_id = ars.replica_id
WHERE ag.name = 'TU_AVAILABILITY_GROUP_NAME';
```

### Alertas Recomendadas

```sql
-- Crear alerta para monitorear failovers no planificados
-- (Este script debe adaptarse según tu sistema de alertas)

IF NOT EXISTS (SELECT * FROM msdb.dbo.sysalerts WHERE name = 'AG_Failover_Alert')
BEGIN
    EXEC msdb.dbo.sp_add_alert
        @name = 'AG_Failover_Alert',
        @message_id = 1480, -- Availability Group failover
        @severity = 16,
        @notification_message = 'Failover detectado en Availability Group - Revisar causa';
END
```

## Configuraciones Recomendadas por Escenario

### Tabla de Configuraciones Sugeridas

| Escenario | FAILURE_CONDITION_LEVEL | HEALTH_CHECK_TIMEOUT | Justificación |
|-----------|-------------------------|---------------------|---------------|
| **Red Estable (LAN)** | 2 (Default) | 30000ms (30s) | Balance estándar |
| **WAN con Latencia Baja (< 50ms)** | 1 | 45000ms (45s) | Reducir sensibilidad |
| **WAN con Latencia Alta (> 50ms)** | 1 | 60000ms (60s) | Máxima tolerancia |
| **Enlaces Satelitales/Wireless** | 1 | 90000ms (90s) | Tolerancia extrema |
| **Entorno de Desarrollo** | 1 | 30000ms (30s) | Evitar interrupciones |
| **Producción Crítica** | 2 | 45000ms (45s) | Balance seguridad/estabilidad |

### Scripts de Configuración Rápida

```sql
-- Configuración para WAN con Alta Latencia (Recomendado para la mayoría de casos problemáticos)
ALTER AVAILABILITY GROUP [TU_AVAILABILITY_GROUP_NAME] 
SET (
    FAILURE_CONDITION_LEVEL = 1,
    HEALTH_CHECK_TIMEOUT = 60000
);
GO

-- Configuración Conservadora (Máxima Estabilidad)
ALTER AVAILABILITY GROUP [TU_AVAILABILITY_GROUP_NAME] 
SET (
    FAILURE_CONDITION_LEVEL = 1,
    HEALTH_CHECK_TIMEOUT = 90000
);
GO

-- Configuración Balanceada (Producción)
ALTER AVAILABILITY GROUP [TU_AVAILABILITY_GROUP_NAME] 
SET (
    FAILURE_CONDITION_LEVEL = 2,
    HEALTH_CHECK_TIMEOUT = 45000
);
GO
```

## Troubleshooting

### Problemas Comunes y Soluciones

| Problema | Causa Probable | Solución |
|----------|----------------|----------|
| **Error: AG no encontrado** | Nombre incorrecto del AG | Verificar `SELECT name FROM sys.availability_groups` |
| **Error: Permisos insuficientes** | No eres sysadmin | Contactar DBA para permisos |
| **Failovers continúan** | Problema no relacionado con FAILURE_CONDITION_LEVEL | Revisar configuración de red del clúster |
| **Configuración no se aplica** | No conectado a instancia primaria | Conectar a la réplica primaria |

### Script de Diagnóstico Completo

```sql
-- Diagnóstico completo del estado del Availability Group
PRINT '=== DIAGNÓSTICO COMPLETO DEL AVAILABILITY GROUP ==='
PRINT ''

-- 1. Configuración del AG
PRINT '1. CONFIGURACIÓN ACTUAL:'
SELECT 
    name AS AvailabilityGroup,
    failure_condition_level AS NivelCondicionFallo,
    health_check_timeout AS TimeoutSalud,
    automated_backup_preference_desc AS PreferenciaBackup
FROM sys.availability_groups;

PRINT ''
PRINT '2. ESTADO DE RÉPLICAS:'
SELECT 
    ag.name AS AvailabilityGroup,
    ar.replica_server_name AS Servidor,
    ars.role_desc AS Rol,
    ars.operational_state_desc AS EstadoOperacional,
    ars.connected_state_desc AS EstadoConexion,
    ars.synchronization_state_desc AS EstadoSincronizacion
FROM sys.availability_groups ag
INNER JOIN sys.availability_replicas ar ON ag.group_id = ar.group_id
INNER JOIN sys.dm_hadr_availability_replica_states ars ON ar.replica_id = ars.replica_id;

PRINT ''
PRINT '3. ESTADO DE BASES DE DATOS:'
SELECT 
    ag.name AS AvailabilityGroup,
    db.database_name AS BaseDatos,
    ar.replica_server_name AS Servidor,
    db.synchronization_state_desc AS EstadoSincronizacion,
    db.synchronization_health_desc AS SaludSincronizacion,
    db.log_send_queue_size AS ColaEnvioLog,
    db.redo_queue_size AS ColaRedo
FROM sys.availability_groups ag
INNER JOIN sys.availability_replicas ar ON ag.group_id = ar.group_id
INNER JOIN sys.dm_hadr_database_replica_states db ON ar.replica_id = db.replica_id;

PRINT ''
PRINT '4. EVENTOS RECIENTES (Última hora):'
-- Esta consulta puede necesitar ajustes según la versión de SQL Server
SELECT 
    GETDATE() AS FechaConsulta,
    'Revisar SQL Server Error Log y Event Viewer para eventos de failover' AS Recomendacion;
```

### Rollback de Configuración

```sql
-- En caso de necesitar revertir los cambios
-- Usar los valores respaldados en el Paso 2 del procedimiento

-- Ejemplo de rollback a configuración anterior
ALTER AVAILABILITY GROUP [TU_AVAILABILITY_GROUP_NAME] 
SET (
    FAILURE_CONDITION_LEVEL = 2,  -- Valor anterior
    HEALTH_CHECK_TIMEOUT = 30000  -- Valor anterior
);
GO

PRINT 'Configuración revertida a valores anteriores';
```

## Mejores Prácticas

### Antes de la Implementación
- [ ] **Documentar configuración actual** para posible rollback
- [ ] **Probar en entorno de desarrollo** primero
- [ ] **Notificar a stakeholders** sobre el cambio
- [ ] **Planificar monitoreo intensivo** las primeras 48 horas

### Durante la Implementación
- [ ] **Ejecutar solo en instancia primaria** del AG
- [ ] **Verificar aplicación inmediata** de cambios
- [ ] **Confirmar estado operacional** del AG post-cambio
- [ ] **Documentar timestamp** de la implementación

### Post-Implementación
- [ ] **Monitorear frecuencia de failovers** por 1 semana
- [ ] **Revisar logs de eventos** diariamente
- [ ] **Validar rendimiento** de aplicaciones
- [ ] **Documentar resultados** para futuras referencias

## Conclusión

La configuración del `FAILURE_CONDITION_LEVEL` es crucial para la estabilidad de SQL Server AlwaysOn en entornos con latencia de red variable. Al reducir la sensibilidad al **Nivel 1**, se eliminan los failovers causados por congestiones temporales de red, manteniendo la protección contra fallos reales del servicio de SQL Server.

### Beneficios Esperados
- ✅ Eliminación de failovers por congestión de red de 5 segundos
- ✅ Mayor estabilidad del servicio
- ✅ Reducción de interrupciones para usuarios finales
- ✅ Mantenimiento de protección contra fallos catastróficos

### Próximos Pasos
1. Implementar la configuración según este procedimiento
2. Monitorear comportamiento por una semana
3. Ajustar si es necesario basado en observaciones
4. Documentar configuración final para otros entornos

---

**Documento creado el**: 29 de octubre de 2025  
**Basado en**: Resumen de análisis de Gemini IA  
**Versión**: 1.0  
**Aplicable a**: SQL Server 2012, 2014, 2016, 2017, 2019, 2022