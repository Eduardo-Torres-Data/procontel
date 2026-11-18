/* ============================================================================
   PROYECTO:   PROCONTEL - Sistema de Trazabilidad de Inventario
   VERSION:    2.0 (COMBINADO: Estructura + SP + Cambios V2.0)
   FECHA:      Mayo 2026
   SGBD:       Microsoft SQL Server 2019+
   ARCHIVO:    PROCONTEL_COMPLETO.sql
   ============================================================================
   CONTENIDO (en orden de ejecucion):
     PARTE 1: Estructura  -> BD, tablas, indices, triggers y vistas
     PARTE 2: SP          -> Tipos TVP, datos RBAC y procedimientos base
     PARTE 3: Cambios V2.0 -> Estado Escalada, vencimiento de equipos,
                              traspasos entre tecnicos y SP nuevos/ajustados
   ============================================================================
   USO: Abrir en SSMS y presionar F5. El script es RE-EJECUTABLE: si la base
        [Procontel] ya existe, la elimina y la vuelve a crear desde cero.
        Luego de correr este archivo, ejecutar el de LLENADO por separado.
   ============================================================================ */

-- ----------------------------------------------------------------------------
-- PASO 0: Eliminar la base si ya existe (hace el script re-ejecutable con F5).
-- Se ejecuta desde [master] y fuerza SINGLE_USER para cerrar conexiones.
-- ----------------------------------------------------------------------------
USE [master]
GO

IF DB_ID('Procontel') IS NOT NULL
BEGIN
    ALTER DATABASE [Procontel] SET SINGLE_USER WITH ROLLBACK IMMEDIATE;
    DROP DATABASE [Procontel];
END
GO


/* ############################################################################
   ############################################################################
   PARTE 1 de 3: ESTRUCTURA DE LA BASE DE DATOS
   (Origen: PROCONTEL_DB_LIMPIO.sql)
   - CREATE DATABASE, tablas, indices, triggers y vistas.
   ############################################################################
   ############################################################################ */

CREATE DATABASE [Procontel]
GO

USE [Procontel]
GO

SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO


/* ============================================================================
   SECCION 1: SEGURIDAD Y CONTROL DE ACCESO (RBAC)
   ============================================================================ */

-- Roles
CREATE TABLE [dbo].[Roles] (
    [IDRol]             INT             IDENTITY(1,1)   NOT NULL,
    [NombreRol]         NVARCHAR(50)                    NOT NULL,
    [Descripcion]       NVARCHAR(200)                   NULL,
    [EstadoRol]         NVARCHAR(15)                    NOT NULL    DEFAULT 'Activo',

    CONSTRAINT [PK_Roles] PRIMARY KEY CLUSTERED ([IDRol] ASC),
    CONSTRAINT [UQ_Roles_NombreRol] UNIQUE ([NombreRol]),

    CONSTRAINT [CK_Roles_EstadoRol] CHECK (
        [EstadoRol] IN ('Activo','Inactivo')
    )
) ON [PRIMARY]
GO

-- Permisos (codigo tecnico formato Modulo.Accion, ej: Factura.Anular)
CREATE TABLE [dbo].[Permisos] (
    [IDPermiso]         INT             IDENTITY(1,1)   NOT NULL,
    [CodigoPermiso]     VARCHAR(50)                     NOT NULL,
    [Modulo]            NVARCHAR(50)                    NOT NULL,
    [Descripcion]       NVARCHAR(200)                   NOT NULL,

    CONSTRAINT [PK_Permisos] PRIMARY KEY CLUSTERED ([IDPermiso] ASC),
    CONSTRAINT [UQ_Permisos_CodigoPermiso] UNIQUE ([CodigoPermiso])
) ON [PRIMARY]
GO

-- Relacion N:M entre Roles y Permisos
CREATE TABLE [dbo].[RolesPermisos] (
    [IDRol]             INT                             NOT NULL,
    [IDPermiso]         INT                             NOT NULL,
    [FechaAsignacion]   DATETIME                        NOT NULL    DEFAULT GETDATE(),

    CONSTRAINT [PK_RolesPermisos] PRIMARY KEY CLUSTERED ([IDRol] ASC, [IDPermiso] ASC),

    CONSTRAINT [FK_RolesPermisos_Roles] FOREIGN KEY ([IDRol])
        REFERENCES [dbo].[Roles] ([IDRol]),

    CONSTRAINT [FK_RolesPermisos_Permisos] FOREIGN KEY ([IDPermiso])
        REFERENCES [dbo].[Permisos] ([IDPermiso])
) ON [PRIMARY]
GO

-- Usuarios (autenticacion). La FK a Tecnicos se agrega con ALTER TABLE
-- mas abajo porque Tecnicos aun no existe en este punto del script.
CREATE TABLE [dbo].[Usuarios] (
    [IDUsuario]         INT             IDENTITY(1,1)   NOT NULL,
    [UsuarioLogin]      VARCHAR(20)                     NOT NULL,
    [PasswordHash]      VARCHAR(128)                    NOT NULL,
    [Nombres]           NVARCHAR(50)                    NOT NULL,
    [Apellidos]         NVARCHAR(50)                    NOT NULL,
    [CorreoElectronico] NVARCHAR(100)                   NULL,
    [CodigoTecnico]     INT                             NULL,
    [EstadoUsuario]     NVARCHAR(15)                    NOT NULL    DEFAULT 'Activo',
    [FechaCreacion]     DATETIME                        NOT NULL    DEFAULT GETDATE(),
    [FechaUltimoLogin]  DATETIME                        NULL,

    CONSTRAINT [PK_Usuarios] PRIMARY KEY CLUSTERED ([IDUsuario] ASC),
    CONSTRAINT [UQ_Usuarios_UsuarioLogin] UNIQUE ([UsuarioLogin]),

    CONSTRAINT [CK_Usuarios_EstadoUsuario] CHECK (
        [EstadoUsuario] IN ('Activo','Inactivo','Bloqueado')
    )
) ON [PRIMARY]
GO

-- Relacion N:M entre Usuarios y Roles (permite multiples roles por usuario)
CREATE TABLE [dbo].[UsuariosRoles] (
    [IDUsuario]         INT                             NOT NULL,
    [IDRol]             INT                             NOT NULL,
    [FechaAsignacion]   DATETIME                        NOT NULL    DEFAULT GETDATE(),

    CONSTRAINT [PK_UsuariosRoles] PRIMARY KEY CLUSTERED ([IDUsuario] ASC, [IDRol] ASC),

    CONSTRAINT [FK_UsuariosRoles_Usuarios] FOREIGN KEY ([IDUsuario])
        REFERENCES [dbo].[Usuarios] ([IDUsuario]),

    CONSTRAINT [FK_UsuariosRoles_Roles] FOREIGN KEY ([IDRol])
        REFERENCES [dbo].[Roles] ([IDRol])
) ON [PRIMARY]
GO


/* ============================================================================
   SECCION 2: CATALOGOS MAESTROS
   ============================================================================ */

-- Tecnicos (incluye CodigoCuadrilla PRO01-PRO999)
CREATE TABLE [dbo].[Tecnicos] (
    [CodigoTecnico]     INT             IDENTITY(1,1)   NOT NULL,
    [CodigoCuadrilla]   VARCHAR(10)                     NOT NULL,
    [DUI]               VARCHAR(10)                     NOT NULL,
    [Nombre]            NVARCHAR(50)                    NOT NULL,
    [Apellido]          NVARCHAR(50)                    NOT NULL,
    [Direccion]         NVARCHAR(150)                   NULL,
    [Telefono]          VARCHAR(9)                      NOT NULL,
    [TipoSangre]        VARCHAR(3)                      NOT NULL,
    [EstadoCivil]       NVARCHAR(15)                    NOT NULL,
    [FechaNacimiento]   DATE                            NOT NULL,
    [Genero]            NVARCHAR(10)                    NOT NULL,
    [TipoLicencia]      NVARCHAR(15)                    NULL,
    [EstadoLaboral]     NVARCHAR(15)                    NOT NULL    DEFAULT 'Activo',

    CONSTRAINT [PK_Tecnicos] PRIMARY KEY CLUSTERED ([CodigoTecnico] ASC),

    CONSTRAINT [UQ_Tecnicos_CodigoCuadrilla] UNIQUE ([CodigoCuadrilla]),
    CONSTRAINT [UQ_Tecnicos_DUI]             UNIQUE ([DUI]),
    CONSTRAINT [UQ_Tecnicos_Telefono]        UNIQUE ([Telefono]),

    CONSTRAINT [CK_Tecnicos_FormatoCuadrilla] CHECK (
        [CodigoCuadrilla] LIKE 'PRO[0-9][0-9]'
        OR [CodigoCuadrilla] LIKE 'PRO[0-9][0-9][0-9]'
    ),
    CONSTRAINT [CK_Tecnicos_FormatoDUI] CHECK (
        [DUI] LIKE '[0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9]-[0-9]'
    ),
    CONSTRAINT [CK_Tecnicos_FormatoTelefono] CHECK (
        [Telefono] LIKE '[0-9][0-9][0-9][0-9]-[0-9][0-9][0-9][0-9]'
    ),
    CONSTRAINT [CK_Tecnicos_TipoSangre] CHECK (
        [TipoSangre] IN ('A+','A-','B+','B-','AB+','AB-','O+','O-')
    ),
    CONSTRAINT [CK_Tecnicos_EstadoCivil] CHECK (
        [EstadoCivil] IN ('soltero/a','casado/a','divorciado/a','viudo/a','acompañado/a')
    ),
    CONSTRAINT [CK_Tecnicos_Genero] CHECK (
        [Genero] IN ('Masculino','Femenino')
    ),
    CONSTRAINT [CK_Tecnicos_TipoLicencia] CHECK (
        [TipoLicencia] IN ('Motocicleta','Liviana','Pesada') OR [TipoLicencia] IS NULL
    ),
    CONSTRAINT [CK_Tecnicos_EstadoLaboral] CHECK (
        [EstadoLaboral] IN ('Activo','Inactivo','Incapacitado')
    )
) ON [PRIMARY]
GO

-- Cierra la FK Usuarios -> Tecnicos (forward reference resuelta)
ALTER TABLE [dbo].[Usuarios]
ADD CONSTRAINT [FK_Usuarios_Tecnicos] FOREIGN KEY ([CodigoTecnico])
    REFERENCES [dbo].[Tecnicos] ([CodigoTecnico])
GO

-- Equipos seriados (identidad individual por numero de serie)
CREATE TABLE [dbo].[EquiposSeriados] (
    [NumeroSerie]       VARCHAR(50)                     NOT NULL,
    [Modelo]            NVARCHAR(100)                   NOT NULL,
    [TipoAparato]       NVARCHAR(20)                    NOT NULL,
    [EstadoEquipo]      NVARCHAR(15)                    NOT NULL    DEFAULT 'Bodega',
    [FechaIngreso]      DATE                            NOT NULL    DEFAULT GETDATE(),

    CONSTRAINT [PK_EquiposSeriados] PRIMARY KEY CLUSTERED ([NumeroSerie] ASC),

    CONSTRAINT [CK_EquiposSeriados_TipoAparato] CHECK (
        [TipoAparato] IN ('Módem','ONT','IPTV','STB','Teléfono','Router','Chip','Switch')
    ),
    CONSTRAINT [CK_EquiposSeriados_EstadoEquipo] CHECK (
        [EstadoEquipo] IN ('Bodega','Asignado','Instalado','Dañado','Garantía')
    )
) ON [PRIMARY]
GO

-- Materiales fungibles (no seriados)
CREATE TABLE [dbo].[MaterialesMiscelaneos] (
    [CodigoMaterial]    VARCHAR(15)                     NOT NULL,
    [NombreMaterial]    NVARCHAR(100)                   NOT NULL,
    [UnidadMedida]      NVARCHAR(20)                    NOT NULL,
    [StockBodega]       DECIMAL(10,2)                   NOT NULL    DEFAULT 0.00,

    CONSTRAINT [PK_MaterialesMiscelaneos] PRIMARY KEY CLUSTERED ([CodigoMaterial] ASC),

    CONSTRAINT [CK_MaterialesMiscelaneos_UnidadMedida] CHECK (
        [UnidadMedida] IN ('Metros','Unidades','Cajas','Rollos')
    ),
    CONSTRAINT [CK_MaterialesMiscelaneos_Stock] CHECK ([StockBodega] >= 0)
) ON [PRIMARY]
GO


/* ============================================================================
   SECCION 3: TABLAS TRANSACCIONALES
   ============================================================================ */

-- Ordenes de trabajo (solicitudes de Claro)
CREATE TABLE [dbo].[OrdenesTrabajo] (
    [NumeroSolicitud]       VARCHAR(20)                 NOT NULL,
    [CodigoTecnico]         INT                         NOT NULL,
    [NombreTitular]         NVARCHAR(100)               NOT NULL,
    [ND]                    VARCHAR(15)                  NULL,
    [OrdenServicio]         NVARCHAR(100)               NOT NULL,
    [TipoTecnologia]        NVARCHAR(20)                NOT NULL,
    [ContactoPrincipal]     VARCHAR(9)                  NOT NULL,
    [ContactoSecundario]    VARCHAR(9)                  NULL,
    [DireccionInstalacion]  NVARCHAR(200)               NOT NULL,
    [CobroTecnico]          DECIMAL(10,2)               NOT NULL    DEFAULT 0.00,
    [FechaOrden]            DATE                        NOT NULL    DEFAULT GETDATE(),
    [EstadoOrden]           NVARCHAR(20)                NOT NULL    DEFAULT 'Pendiente',

    CONSTRAINT [PK_OrdenesTrabajo] PRIMARY KEY CLUSTERED ([NumeroSolicitud] ASC),

    CONSTRAINT [FK_OrdenesTrabajo_Tecnicos] FOREIGN KEY ([CodigoTecnico])
        REFERENCES [dbo].[Tecnicos] ([CodigoTecnico]),

    CONSTRAINT [CK_OrdenesTrabajo_FormatoContacto] CHECK (
        [ContactoPrincipal] LIKE '[0-9][0-9][0-9][0-9]-[0-9][0-9][0-9][0-9]'
    ),
    CONSTRAINT [CK_OrdenesTrabajo_FormatoContacto2] CHECK (
        [ContactoSecundario] IS NULL
        OR [ContactoSecundario] LIKE '[0-9][0-9][0-9][0-9]-[0-9][0-9][0-9][0-9]'
    ),
    CONSTRAINT [CK_OrdenesTrabajo_TipoTecnologia] CHECK (
        [TipoTecnologia] IN ('Cobre','HFC','Fibra Óptica','DTH','Satelital')
    ),
    CONSTRAINT [CK_OrdenesTrabajo_CobroTecnico] CHECK ([CobroTecnico] >= 0),
    CONSTRAINT [CK_OrdenesTrabajo_EstadoOrden] CHECK (
        [EstadoOrden] IN ('Pendiente','En Proceso','Completada','Cancelada')
    )
) ON [PRIMARY]
GO

-- Impide dos ordenes activas para el mismo numero de linea
CREATE UNIQUE NONCLUSTERED INDEX [UX_OrdenesTrabajo_ND_Activa]
    ON [dbo].[OrdenesTrabajo] ([ND])
    WHERE [ND] IS NOT NULL AND [EstadoOrden] IN ('Pendiente', 'En Proceso')
GO

-- Facturas (remisiones de bodega)
CREATE TABLE [dbo].[Facturas] (
    [NumeroFactura]     INT             IDENTITY(1,1)   NOT NULL,
    [FechaFactura]      DATE                            NOT NULL    DEFAULT GETDATE(),
    [CodigoTecnico]     INT                             NOT NULL,
    [IDUsuarioBodega]   INT                             NOT NULL,
    [Observaciones]     NVARCHAR(200)                   NULL,

    CONSTRAINT [PK_Facturas] PRIMARY KEY CLUSTERED ([NumeroFactura] ASC),

    CONSTRAINT [FK_Facturas_Tecnicos] FOREIGN KEY ([CodigoTecnico])
        REFERENCES [dbo].[Tecnicos] ([CodigoTecnico]),

    CONSTRAINT [FK_Facturas_Usuarios] FOREIGN KEY ([IDUsuarioBodega])
        REFERENCES [dbo].[Usuarios] ([IDUsuario])
) ON [PRIMARY]
GO

-- Asignacion de equipos seriados (linea 1:1 por equipo)
CREATE TABLE [dbo].[AsignacionEquipos] (
    [IDRegistro]        INT             IDENTITY(1,1)   NOT NULL,
    [NumeroFactura]     INT                             NOT NULL,
    [NumeroSerie]       VARCHAR(50)                     NOT NULL,
    [Cantidad]          INT                             NOT NULL    DEFAULT 1,
    [EstadoAsignacion]  NVARCHAR(10)                    NOT NULL    DEFAULT 'Activa',

    CONSTRAINT [PK_AsignacionEquipos] PRIMARY KEY CLUSTERED ([IDRegistro] ASC),

    CONSTRAINT [FK_AsignacionEquipos_Facturas] FOREIGN KEY ([NumeroFactura])
        REFERENCES [dbo].[Facturas] ([NumeroFactura]),

    CONSTRAINT [FK_AsignacionEquipos_EquiposSeriados] FOREIGN KEY ([NumeroSerie])
        REFERENCES [dbo].[EquiposSeriados] ([NumeroSerie]),

    CONSTRAINT [CK_AsignacionEquipos_Cantidad] CHECK ([Cantidad] = 1),
    CONSTRAINT [CK_AsignacionEquipos_Estado] CHECK (
        [EstadoAsignacion] IN ('Activa','Devuelta')
    )
) ON [PRIMARY]
GO

-- Impide asignar el mismo equipo a dos tecnicos simultaneamente
CREATE UNIQUE NONCLUSTERED INDEX [UX_AsignacionEquipos_SerieActiva]
    ON [dbo].[AsignacionEquipos] ([NumeroSerie])
    WHERE [EstadoAsignacion] = 'Activa'
GO

-- Asignacion de materiales (cantidades variables)
CREATE TABLE [dbo].[AsignacionMateriales] (
    [IDRegistro]        INT             IDENTITY(1,1)   NOT NULL,
    [NumeroFactura]     INT                             NOT NULL,
    [CodigoMaterial]    VARCHAR(15)                     NOT NULL,
    [Cantidad]          DECIMAL(10,2)                   NOT NULL,

    CONSTRAINT [PK_AsignacionMateriales] PRIMARY KEY CLUSTERED ([IDRegistro] ASC),

    CONSTRAINT [FK_AsignacionMateriales_Facturas] FOREIGN KEY ([NumeroFactura])
        REFERENCES [dbo].[Facturas] ([NumeroFactura]),

    CONSTRAINT [FK_AsignacionMateriales_MaterialesMiscelaneos] FOREIGN KEY ([CodigoMaterial])
        REFERENCES [dbo].[MaterialesMiscelaneos] ([CodigoMaterial]),

    CONSTRAINT [CK_AsignacionMateriales_Cantidad] CHECK ([Cantidad] > 0)
) ON [PRIMARY]
GO

-- Detalle de instalacion (cierra el ciclo: Asignacion -> Instalacion -> Descargo)
CREATE TABLE [dbo].[DetalleInstalacion] (
    [IDDetalle]         INT             IDENTITY(1,1)   NOT NULL,
    [NumeroSolicitud]   VARCHAR(20)                     NOT NULL,
    [CodigoTecnico]     INT                             NOT NULL,
    [FechaInstalacion]  DATE                            NOT NULL,
    [NumeroSerie]       VARCHAR(50)                     NULL,
    [CodigoMaterial]    VARCHAR(15)                     NULL,
    [CantidadUtilizada] DECIMAL(10,2)                   NULL,
    [ValidadoBodega]    CHAR(2)                         NOT NULL    DEFAULT 'NO',

    CONSTRAINT [PK_DetalleInstalacion] PRIMARY KEY CLUSTERED ([IDDetalle] ASC),

    CONSTRAINT [FK_DetalleInstalacion_OrdenesTrabajo] FOREIGN KEY ([NumeroSolicitud])
        REFERENCES [dbo].[OrdenesTrabajo] ([NumeroSolicitud]),

    CONSTRAINT [FK_DetalleInstalacion_Tecnicos] FOREIGN KEY ([CodigoTecnico])
        REFERENCES [dbo].[Tecnicos] ([CodigoTecnico]),

    CONSTRAINT [FK_DetalleInstalacion_EquiposSeriados] FOREIGN KEY ([NumeroSerie])
        REFERENCES [dbo].[EquiposSeriados] ([NumeroSerie]),

    CONSTRAINT [FK_DetalleInstalacion_MaterialesMiscelaneos] FOREIGN KEY ([CodigoMaterial])
        REFERENCES [dbo].[MaterialesMiscelaneos] ([CodigoMaterial]),

    CONSTRAINT [CK_DetalleInstalacion_ValidadoBodega] CHECK (
        [ValidadoBodega] IN ('SI','NO')
    ),
    CONSTRAINT [CK_DetalleInstalacion_TieneContenido] CHECK (
        [NumeroSerie] IS NOT NULL OR [CodigoMaterial] IS NOT NULL
    ),
    CONSTRAINT [CK_DetalleInstalacion_CantidadMaterial] CHECK (
        ([CodigoMaterial] IS NULL)
        OR ([CodigoMaterial] IS NOT NULL AND [CantidadUtilizada] > 0)
    )
) ON [PRIMARY]
GO

-- Averia / Garantia (visitas de soporte post-instalacion)
CREATE TABLE [dbo].[AveriaGarantia] (
    [NumeroTicket]          VARCHAR(20)                 NOT NULL,
    [NumeroSolicitud]       VARCHAR(20)                 NOT NULL,
    [CodigoTecnico]         INT                         NOT NULL,
    [FechaVisita]           DATE                        NOT NULL,
    [ProblemaReportado]     NVARCHAR(200)               NOT NULL,
    [ComentarioTecnico]     NVARCHAR(200)               NULL,
    [TipoVisita]            NVARCHAR(20)                NOT NULL,
    [NumeroSerieInstalado]  VARCHAR(50)                 NULL,
    [NumeroSerieRetirado]   VARCHAR(50)                 NULL,
    [CodigoMaterial]        VARCHAR(15)                 NULL,
    [CantidadMaterial]      DECIMAL(10,2)               NULL,

    CONSTRAINT [PK_AveriaGarantia] PRIMARY KEY CLUSTERED ([NumeroTicket] ASC),

    CONSTRAINT [FK_AveriaGarantia_OrdenesTrabajo] FOREIGN KEY ([NumeroSolicitud])
        REFERENCES [dbo].[OrdenesTrabajo] ([NumeroSolicitud]),

    CONSTRAINT [FK_AveriaGarantia_Tecnicos] FOREIGN KEY ([CodigoTecnico])
        REFERENCES [dbo].[Tecnicos] ([CodigoTecnico]),

    CONSTRAINT [FK_AveriaGarantia_EquipoInstalado] FOREIGN KEY ([NumeroSerieInstalado])
        REFERENCES [dbo].[EquiposSeriados] ([NumeroSerie]),

    CONSTRAINT [FK_AveriaGarantia_EquipoRetirado] FOREIGN KEY ([NumeroSerieRetirado])
        REFERENCES [dbo].[EquiposSeriados] ([NumeroSerie]),

    CONSTRAINT [FK_AveriaGarantia_MaterialesMiscelaneos] FOREIGN KEY ([CodigoMaterial])
        REFERENCES [dbo].[MaterialesMiscelaneos] ([CodigoMaterial]),

    CONSTRAINT [CK_AveriaGarantia_TipoVisita] CHECK (
        [TipoVisita] IN ('Soporte Logico','Cambio de Equipo','Uso de Material','Cambio y Material')
    ),

    -- CHECK compuesto: garantiza coherencia entre TipoVisita y campos de inventario
    CONSTRAINT [CK_AveriaGarantia_CoherenciaInventario] CHECK (
        (
            [TipoVisita] = 'Soporte Logico'
            AND [NumeroSerieInstalado] IS NULL
            AND [NumeroSerieRetirado]  IS NULL
            AND [CodigoMaterial]       IS NULL
            AND [CantidadMaterial]     IS NULL
        )
        OR
        (
            [TipoVisita] = 'Cambio de Equipo'
            AND [NumeroSerieInstalado] IS NOT NULL
            AND [CodigoMaterial]       IS NULL
            AND [CantidadMaterial]     IS NULL
        )
        OR
        (
            [TipoVisita] = 'Uso de Material'
            AND [NumeroSerieInstalado] IS NULL
            AND [NumeroSerieRetirado]  IS NULL
            AND [CodigoMaterial]       IS NOT NULL
            AND [CantidadMaterial]     > 0
        )
        OR
        (
            [TipoVisita] = 'Cambio y Material'
            AND [NumeroSerieInstalado] IS NOT NULL
            AND [CodigoMaterial]       IS NOT NULL
            AND [CantidadMaterial]     > 0
        )
    )
) ON [PRIMARY]
GO

-- Devolucion de inventario (reintegro del tecnico a bodega)
CREATE TABLE [dbo].[DevolucionInventario] (
    [IDDevolucion]      INT             IDENTITY(1,1)   NOT NULL,
    [FechaDevolucion]   DATE                            NOT NULL    DEFAULT GETDATE(),
    [CodigoTecnico]     INT                             NOT NULL,
    [IDUsuarioBodega]   INT                             NOT NULL,
    [NumeroSerie]       VARCHAR(50)                     NULL,
    [CodigoMaterial]    VARCHAR(15)                     NULL,
    [CantidadDevuelta]  DECIMAL(10,2)                   NULL,
    [CondicionEntrega]  NVARCHAR(20)                    NOT NULL,

    CONSTRAINT [PK_DevolucionInventario] PRIMARY KEY CLUSTERED ([IDDevolucion] ASC),

    CONSTRAINT [FK_DevolucionInventario_Tecnicos] FOREIGN KEY ([CodigoTecnico])
        REFERENCES [dbo].[Tecnicos] ([CodigoTecnico]),

    CONSTRAINT [FK_DevolucionInventario_Usuarios] FOREIGN KEY ([IDUsuarioBodega])
        REFERENCES [dbo].[Usuarios] ([IDUsuario]),

    CONSTRAINT [FK_DevolucionInventario_EquiposSeriados] FOREIGN KEY ([NumeroSerie])
        REFERENCES [dbo].[EquiposSeriados] ([NumeroSerie]),

    CONSTRAINT [FK_DevolucionInventario_MaterialesMiscelaneos] FOREIGN KEY ([CodigoMaterial])
        REFERENCES [dbo].[MaterialesMiscelaneos] ([CodigoMaterial]),

    CONSTRAINT [CK_DevolucionInventario_TieneContenido] CHECK (
        [NumeroSerie] IS NOT NULL OR [CodigoMaterial] IS NOT NULL
    ),
    CONSTRAINT [CK_DevolucionInventario_CondicionEntrega] CHECK (
        [CondicionEntrega] IN ('Bueno/Sobrante','Dañado de fábrica','Dañado por uso')
    ),
    CONSTRAINT [CK_DevolucionInventario_CantidadMaterial] CHECK (
        ([CodigoMaterial] IS NULL)
        OR ([CodigoMaterial] IS NOT NULL AND [CantidadDevuelta] > 0)
    )
) ON [PRIMARY]
GO


/* ============================================================================
   SECCION 4: AUDITORIA
   ============================================================================ */

-- Bitacora de auditoria (registro historico de acciones en el sistema)
CREATE TABLE [dbo].[BitacoraAuditoria] (
    [IDAuditoria]       BIGINT          IDENTITY(1,1)   NOT NULL,
    [FechaHora]         DATETIME                        NOT NULL    DEFAULT GETDATE(),
    [TablaAfectada]     NVARCHAR(50)                    NOT NULL,
    [TipoOperacion]     CHAR(1)                         NOT NULL,   -- I=Insert, U=Update, D=Delete
    [RegistroID]        NVARCHAR(50)                    NOT NULL,
    [CampoModificado]   NVARCHAR(50)                    NULL,
    [ValorAnterior]     NVARCHAR(500)                   NULL,
    [ValorNuevo]        NVARCHAR(500)                   NULL,
    [UsuarioLogin]      VARCHAR(20)                     NOT NULL,
    [DireccionIP]       VARCHAR(45)                     NULL,

    CONSTRAINT [PK_BitacoraAuditoria] PRIMARY KEY CLUSTERED ([IDAuditoria] ASC),

    CONSTRAINT [CK_BitacoraAuditoria_TipoOperacion] CHECK (
        [TipoOperacion] IN ('I','U','D')
    )
) ON [PRIMARY]
GO


/* ============================================================================
   SECCION 5: INDICES
   ============================================================================ */

-- Bitacora: consultas por tabla/fecha y por usuario/fecha
CREATE NONCLUSTERED INDEX [IX_BitacoraAuditoria_TablaFecha]
    ON [dbo].[BitacoraAuditoria] ([TablaAfectada] ASC, [FechaHora] DESC)
GO

CREATE NONCLUSTERED INDEX [IX_BitacoraAuditoria_Usuario]
    ON [dbo].[BitacoraAuditoria] ([UsuarioLogin] ASC, [FechaHora] DESC)
GO

-- Asignaciones: consultas por factura y por numero de serie
CREATE NONCLUSTERED INDEX [IX_AsignacionEquipos_NumeroFactura]
    ON [dbo].[AsignacionEquipos] ([NumeroFactura] ASC)
GO

CREATE NONCLUSTERED INDEX [IX_AsignacionMateriales_NumeroFactura]
    ON [dbo].[AsignacionMateriales] ([NumeroFactura] ASC)
GO

CREATE NONCLUSTERED INDEX [IX_AsignacionEquipos_NumeroSerie]
    ON [dbo].[AsignacionEquipos] ([NumeroSerie] ASC)
GO

-- Averias: consultas por orden original
CREATE NONCLUSTERED INDEX [IX_AveriaGarantia_NumeroSolicitud]
    ON [dbo].[AveriaGarantia] ([NumeroSolicitud] ASC)
GO

-- Detalles de instalacion
CREATE NONCLUSTERED INDEX [IX_DetalleInstalacion_NumeroSolicitud]
    ON [dbo].[DetalleInstalacion] ([NumeroSolicitud] ASC)
GO

CREATE NONCLUSTERED INDEX [IX_DetalleInstalacion_CodigoTecnico]
    ON [dbo].[DetalleInstalacion] ([CodigoTecnico] ASC)
GO

-- Devoluciones y facturas
CREATE NONCLUSTERED INDEX [IX_DevolucionInventario_CodigoTecnico]
    ON [dbo].[DevolucionInventario] ([CodigoTecnico] ASC)
GO

CREATE NONCLUSTERED INDEX [IX_Facturas_CodigoTecnico]
    ON [dbo].[Facturas] ([CodigoTecnico] ASC)
GO

-- Tablas de seguridad RBAC
CREATE NONCLUSTERED INDEX [IX_UsuariosRoles_IDRol]
    ON [dbo].[UsuariosRoles] ([IDRol] ASC)
GO

CREATE NONCLUSTERED INDEX [IX_RolesPermisos_IDPermiso]
    ON [dbo].[RolesPermisos] ([IDPermiso] ASC)
GO

-- Indice filtrado: solo usuarios que son tecnicos
CREATE NONCLUSTERED INDEX [IX_Usuarios_CodigoTecnico]
    ON [dbo].[Usuarios] ([CodigoTecnico] ASC)
    WHERE [CodigoTecnico] IS NOT NULL
GO

/* ============================================================================
   FIN DEL SCRIPT
   ============================================================================ */

/* ============================================================================
   SECCION 1: TRIGGERS DE AUDITORIA FISICA
   ============================================================================ */

-- ----------------------------------------------------------------------------
-- TRIGGER: Captura cambios de EstadoEquipo en EquiposSeriados.
-- Se dispara en cualquier UPDATE de la columna EstadoEquipo, venga de un
-- SP o de un UPDATE directo. Usa SUSER_SNAME() para identificar al login
-- de SQL Server cuando no hay un usuario de aplicacion identificado.
-- ----------------------------------------------------------------------------
CREATE TRIGGER [dbo].[trg_EquiposSeriados_EstadoEquipo]
ON [dbo].[EquiposSeriados]
AFTER UPDATE
AS
BEGIN
    SET NOCOUNT ON;

    -- Solo procesar si la columna EstadoEquipo realmente cambio
    IF NOT UPDATE([EstadoEquipo])
        RETURN;

    INSERT INTO [dbo].[BitacoraAuditoria] (
        [TablaAfectada], [TipoOperacion], [RegistroID],
        [CampoModificado], [ValorAnterior], [ValorNuevo],
        [UsuarioLogin]
    )
    SELECT
        N'EquiposSeriados',
        'U',
        i.[NumeroSerie],
        N'EstadoEquipo_TRG',
        d.[EstadoEquipo],
        i.[EstadoEquipo],
        SUSER_SNAME()
    FROM inserted i
    INNER JOIN deleted d ON d.[NumeroSerie] = i.[NumeroSerie]
    WHERE i.[EstadoEquipo] <> d.[EstadoEquipo];
END
GO

-- ----------------------------------------------------------------------------
-- TRIGGER: Captura cambios de StockBodega en MaterialesMiscelaneos.
-- Critico para auditoria: el stock es lo que mas cuestiona Claro.
-- ----------------------------------------------------------------------------
CREATE TRIGGER [dbo].[trg_MaterialesMiscelaneos_Stock]
ON [dbo].[MaterialesMiscelaneos]
AFTER UPDATE
AS
BEGIN
    SET NOCOUNT ON;

    IF NOT UPDATE([StockBodega])
        RETURN;

    INSERT INTO [dbo].[BitacoraAuditoria] (
        [TablaAfectada], [TipoOperacion], [RegistroID],
        [CampoModificado], [ValorAnterior], [ValorNuevo],
        [UsuarioLogin]
    )
    SELECT
        N'MaterialesMiscelaneos',
        'U',
        i.[CodigoMaterial],
        N'StockBodega_TRG',
        CAST(d.[StockBodega] AS NVARCHAR(20)),
        CAST(i.[StockBodega] AS NVARCHAR(20)),
        SUSER_SNAME()
    FROM inserted i
    INNER JOIN deleted d ON d.[CodigoMaterial] = i.[CodigoMaterial]
    WHERE i.[StockBodega] <> d.[StockBodega];
END
GO

-- ----------------------------------------------------------------------------
-- TRIGGER: Captura cambios de EstadoOrden en OrdenesTrabajo.
-- Permite reconstruir la linea de tiempo de cada orden a partir de
-- la bitacora, util para reportes de SLA.
-- ----------------------------------------------------------------------------
CREATE TRIGGER [dbo].[trg_OrdenesTrabajo_EstadoOrden]
ON [dbo].[OrdenesTrabajo]
AFTER UPDATE
AS
BEGIN
    SET NOCOUNT ON;

    IF NOT UPDATE([EstadoOrden])
        RETURN;

    INSERT INTO [dbo].[BitacoraAuditoria] (
        [TablaAfectada], [TipoOperacion], [RegistroID],
        [CampoModificado], [ValorAnterior], [ValorNuevo],
        [UsuarioLogin]
    )
    SELECT
        N'OrdenesTrabajo',
        'U',
        i.[NumeroSolicitud],
        N'EstadoOrden_TRG',
        d.[EstadoOrden],
        i.[EstadoOrden],
        SUSER_SNAME()
    FROM inserted i
    INNER JOIN deleted d ON d.[NumeroSolicitud] = i.[NumeroSolicitud]
    WHERE i.[EstadoOrden] <> d.[EstadoOrden];
END
GO


/* ============================================================================
   SECCION 2: VISTAS DE DIMENSION (para slicers/filtros en Power BI)
   ============================================================================
   Estas vistas se conectan a Power BI como tablas de dimension. Son
   "anchas" y desnormalizadas a proposito: Power BI prefiere pocas tablas
   con muchas columnas que muchas tablas con joins.
   ============================================================================ */

-- ----------------------------------------------------------------------------
-- VISTA: Dimension Tecnico enriquecida con campos calculados.
-- Edad y AntiguedadAnios permiten slicers por rango etario o seniority.
-- ----------------------------------------------------------------------------
CREATE VIEW [dbo].[vw_DimTecnico]
AS
SELECT
    T.[CodigoTecnico],
    T.[CodigoCuadrilla],
    T.[DUI],
    T.[Nombre] + ' ' + T.[Apellido]                 AS [NombreCompleto],
    T.[Genero],
    T.[EstadoCivil],
    T.[TipoSangre],
    T.[TipoLicencia],
    T.[EstadoLaboral],
    T.[FechaNacimiento],
    DATEDIFF(YEAR, T.[FechaNacimiento], GETDATE()) AS [Edad],
    CASE
        WHEN DATEDIFF(YEAR, T.[FechaNacimiento], GETDATE()) < 25 THEN '18-24'
        WHEN DATEDIFF(YEAR, T.[FechaNacimiento], GETDATE()) < 35 THEN '25-34'
        WHEN DATEDIFF(YEAR, T.[FechaNacimiento], GETDATE()) < 45 THEN '35-44'
        WHEN DATEDIFF(YEAR, T.[FechaNacimiento], GETDATE()) < 55 THEN '45-54'
        ELSE '55+'
    END AS [RangoEdad],
    T.[Telefono],
    T.[Direccion]
FROM [dbo].[Tecnicos] T;
GO

-- ----------------------------------------------------------------------------
-- VISTA: Dimension Equipo enriquecida con tecnico actual asignado.
-- Hace LEFT JOIN al tecnico solo si el equipo esta en estado Asignado.
-- ----------------------------------------------------------------------------
CREATE VIEW [dbo].[vw_DimEquipo]
AS
SELECT
    ES.[NumeroSerie],
    ES.[Modelo],
    ES.[TipoAparato],
    ES.[EstadoEquipo],
    ES.[FechaIngreso],
    DATEDIFF(DAY, ES.[FechaIngreso], GETDATE()) AS [DiasEnSistema],
    T.[CodigoTecnico]                            AS [TecnicoActualCodigo],
    T.[CodigoCuadrilla]                          AS [TecnicoActualCuadrilla],
    T.[Nombre] + ' ' + T.[Apellido]              AS [TecnicoActualNombre]
FROM [dbo].[EquiposSeriados] ES
LEFT JOIN [dbo].[AsignacionEquipos] AE
    ON AE.[NumeroSerie] = ES.[NumeroSerie]
    AND AE.[EstadoAsignacion] = 'Activa'
LEFT JOIN [dbo].[Facturas] F     ON F.[NumeroFactura] = AE.[NumeroFactura]
LEFT JOIN [dbo].[Tecnicos] T     ON T.[CodigoTecnico] = F.[CodigoTecnico];
GO


/* ============================================================================
   SECCION 3: VISTAS DE HECHOS DETALLADOS (sin agregar)
   ============================================================================
   Una fila = un evento. Power BI agrega dinamicamente con sus medidas.
   Esto es lo que permite drill-down en los dashboards.
   ============================================================================ */

-- ----------------------------------------------------------------------------
-- VISTA DE HECHOS: Cada fila es una orden de trabajo con todos sus campos
-- y dimensiones planas (tecnico, fechas calculadas).
-- ----------------------------------------------------------------------------
CREATE VIEW [dbo].[vw_HechosOrdenes]
AS
SELECT
    O.[NumeroSolicitud],
    O.[FechaOrden],
    YEAR(O.[FechaOrden])                            AS [Anio],
    MONTH(O.[FechaOrden])                           AS [Mes],
    DATENAME(MONTH, O.[FechaOrden])                 AS [NombreMes],
    DATEPART(QUARTER, O.[FechaOrden])               AS [Trimestre],
    DATENAME(WEEKDAY, O.[FechaOrden])               AS [DiaSemana],
    O.[EstadoOrden],
    O.[TipoTecnologia],
    O.[CobroTecnico],
    O.[NombreTitular],
    O.[DireccionInstalacion],
    T.[CodigoTecnico],
    T.[CodigoCuadrilla],
    T.[Nombre] + ' ' + T.[Apellido]                 AS [NombreTecnico],
    -- Campos para medidas en Power BI
    CASE WHEN O.[EstadoOrden] = 'Completada' THEN 1 ELSE 0 END AS [EsCompletada],
    CASE WHEN O.[EstadoOrden] = 'Cancelada'  THEN 1 ELSE 0 END AS [EsCancelada],
    CASE WHEN O.[EstadoOrden] IN ('Pendiente','En Proceso') THEN 1 ELSE 0 END AS [EsAbierta]
FROM [dbo].[OrdenesTrabajo] O
INNER JOIN [dbo].[Tecnicos] T ON T.[CodigoTecnico] = O.[CodigoTecnico];
GO

-- ----------------------------------------------------------------------------
-- VISTA DE HECHOS: Cada fila es un detalle de instalacion (equipo o
-- material). Granularidad maxima: permite a Power BI agregar por tecnico,
-- material, fecha, tecnologia, etc.
-- ----------------------------------------------------------------------------
CREATE VIEW [dbo].[vw_HechosInstalaciones]
AS
SELECT
    DI.[IDDetalle],
    DI.[NumeroSolicitud],
    DI.[FechaInstalacion],
    YEAR(DI.[FechaInstalacion])                     AS [Anio],
    MONTH(DI.[FechaInstalacion])                    AS [Mes],
    DI.[ValidadoBodega],
    -- Tecnico que instalo
    T.[CodigoTecnico],
    T.[CodigoCuadrilla],
    T.[Nombre] + ' ' + T.[Apellido]                 AS [NombreTecnico],
    -- Tipo de tecnologia (heredada de la orden)
    O.[TipoTecnologia],
    -- Si el detalle es un equipo
    DI.[NumeroSerie],
    ES.[Modelo]                                     AS [ModeloEquipo],
    ES.[TipoAparato],
    -- Si el detalle es un material
    DI.[CodigoMaterial],
    MM.[NombreMaterial],
    MM.[UnidadMedida],
    DI.[CantidadUtilizada],
    -- Clasificador para medidas
    CASE
        WHEN DI.[NumeroSerie]    IS NOT NULL THEN 'Equipo'
        WHEN DI.[CodigoMaterial] IS NOT NULL THEN 'Material'
    END AS [TipoDetalle]
FROM [dbo].[DetalleInstalacion] DI
INNER JOIN [dbo].[OrdenesTrabajo] O        ON O.[NumeroSolicitud] = DI.[NumeroSolicitud]
INNER JOIN [dbo].[Tecnicos] T              ON T.[CodigoTecnico]   = DI.[CodigoTecnico]
LEFT JOIN [dbo].[EquiposSeriados] ES       ON ES.[NumeroSerie]    = DI.[NumeroSerie]
LEFT JOIN [dbo].[MaterialesMiscelaneos] MM ON MM.[CodigoMaterial] = DI.[CodigoMaterial];
GO

-- ----------------------------------------------------------------------------
-- VISTA DE HECHOS: Cada fila es una averia. Permite reportes de
-- garantia, tipos de visita, problemas mas frecuentes.
-- ----------------------------------------------------------------------------
CREATE VIEW [dbo].[vw_HechosAverias]
AS
SELECT
    AG.[NumeroTicket],
    AG.[NumeroSolicitud],
    AG.[FechaVisita],
    YEAR(AG.[FechaVisita])                          AS [Anio],
    MONTH(AG.[FechaVisita])                         AS [Mes],
    AG.[TipoVisita],
    AG.[ProblemaReportado],
    AG.[NumeroSerieInstalado],
    AG.[NumeroSerieRetirado],
    AG.[CodigoMaterial],
    AG.[CantidadMaterial],
    -- Tecnico que atendio
    T.[CodigoCuadrilla],
    T.[Nombre] + ' ' + T.[Apellido]                 AS [NombreTecnico],
    -- Datos de la orden original
    O.[FechaOrden]                                  AS [FechaOrdenOriginal],
    O.[TipoTecnologia],
    DATEDIFF(DAY, O.[FechaOrden], AG.[FechaVisita]) AS [DiasDesdeInstalacion],
    -- Clasificador de garantia (3 meses = 90 dias)
    CASE
        WHEN DATEDIFF(DAY, O.[FechaOrden], AG.[FechaVisita]) <= 90 THEN 'En Garantia'
        ELSE 'Fuera de Garantia'
    END AS [EstadoGarantia]
FROM [dbo].[AveriaGarantia] AG
INNER JOIN [dbo].[Tecnicos] T       ON T.[CodigoTecnico]   = AG.[CodigoTecnico]
INNER JOIN [dbo].[OrdenesTrabajo] O ON O.[NumeroSolicitud] = AG.[NumeroSolicitud];
GO

-- ----------------------------------------------------------------------------
-- VISTA DE HECHOS: Movimientos de inventario consolidados.
-- Cada fila es una entrega (factura) o devolucion. Util para grafico
-- de flujo de inventario en el dashboard.
-- ----------------------------------------------------------------------------
CREATE VIEW [dbo].[vw_HechosMovimientosInventario]
AS
-- Entregas (facturas)
SELECT
    'Entrega' AS [TipoMovimiento],
    F.[FechaFactura]                                AS [Fecha],
    YEAR(F.[FechaFactura])                          AS [Anio],
    MONTH(F.[FechaFactura])                         AS [Mes],
    T.[CodigoCuadrilla],
    T.[Nombre] + ' ' + T.[Apellido]                 AS [NombreTecnico],
    AE.[NumeroSerie],
    NULL                                            AS [CodigoMaterial],
    1                                               AS [Cantidad],
    NULL                                            AS [CondicionEntrega]
FROM [dbo].[Facturas] F
INNER JOIN [dbo].[Tecnicos] T          ON T.[CodigoTecnico] = F.[CodigoTecnico]
INNER JOIN [dbo].[AsignacionEquipos] AE ON AE.[NumeroFactura] = F.[NumeroFactura]

UNION ALL

SELECT
    'Entrega' AS [TipoMovimiento],
    F.[FechaFactura]                                AS [Fecha],
    YEAR(F.[FechaFactura])                          AS [Anio],
    MONTH(F.[FechaFactura])                         AS [Mes],
    T.[CodigoCuadrilla],
    T.[Nombre] + ' ' + T.[Apellido]                 AS [NombreTecnico],
    NULL                                            AS [NumeroSerie],
    AM.[CodigoMaterial],
    AM.[Cantidad],
    NULL                                            AS [CondicionEntrega]
FROM [dbo].[Facturas] F
INNER JOIN [dbo].[Tecnicos] T            ON T.[CodigoTecnico] = F.[CodigoTecnico]
INNER JOIN [dbo].[AsignacionMateriales] AM ON AM.[NumeroFactura] = F.[NumeroFactura]

UNION ALL

-- Devoluciones
SELECT
    'Devolucion' AS [TipoMovimiento],
    DEV.[FechaDevolucion]                           AS [Fecha],
    YEAR(DEV.[FechaDevolucion])                     AS [Anio],
    MONTH(DEV.[FechaDevolucion])                    AS [Mes],
    T.[CodigoCuadrilla],
    T.[Nombre] + ' ' + T.[Apellido]                 AS [NombreTecnico],
    DEV.[NumeroSerie],
    DEV.[CodigoMaterial],
    ISNULL(DEV.[CantidadDevuelta], 1)               AS [Cantidad],
    DEV.[CondicionEntrega]
FROM [dbo].[DevolucionInventario] DEV
INNER JOIN [dbo].[Tecnicos] T ON T.[CodigoTecnico] = DEV.[CodigoTecnico];
GO


/* ============================================================================
   SECCION 4: VISTAS GERENCIALES (para tarjetas/KPIs en Power BI)
   ============================================================================
   Vistas con calculos agregados pre-hechos para los KPIs grandes del
   dashboard ejecutivo. Power BI las consume como cards.
   ============================================================================ */

-- ----------------------------------------------------------------------------
-- VISTA: Resumen de inventario por estado para card de "salud de bodega".
-- ----------------------------------------------------------------------------
CREATE VIEW [dbo].[vw_KPIInventarioGlobal]
AS
SELECT
    ES.[TipoAparato],
    ES.[EstadoEquipo],
    COUNT(*) AS [Cantidad]
FROM [dbo].[EquiposSeriados] ES
GROUP BY ES.[TipoAparato], ES.[EstadoEquipo];
GO

-- ----------------------------------------------------------------------------
-- VISTA: Productividad acumulada por tecnico (sin filtro de fecha).
-- Power BI puede filtrar por fecha desde la dimension de fecha.
-- ----------------------------------------------------------------------------
CREATE VIEW [dbo].[vw_KPIProductividadTecnico]
AS
SELECT
    T.[CodigoTecnico],
    T.[CodigoCuadrilla],
    T.[Nombre] + ' ' + T.[Apellido]                 AS [NombreTecnico],
    T.[EstadoLaboral],
    COUNT(O.[NumeroSolicitud])                      AS [TotalOrdenes],
    SUM(CASE WHEN O.[EstadoOrden] = 'Completada' THEN 1 ELSE 0 END) AS [OrdenesCompletadas],
    SUM(CASE WHEN O.[EstadoOrden] = 'Cancelada'  THEN 1 ELSE 0 END) AS [OrdenesCanceladas],
    SUM(CASE WHEN O.[EstadoOrden] IN ('Pendiente','En Proceso') THEN 1 ELSE 0 END) AS [OrdenesAbiertas],
    SUM(CASE WHEN O.[EstadoOrden] = 'Completada' THEN O.[CobroTecnico] ELSE 0 END) AS [TotalCobrado],
    -- Tasa de exito: completadas / (completadas + canceladas)
    CASE
        WHEN SUM(CASE WHEN O.[EstadoOrden] IN ('Completada','Cancelada') THEN 1 ELSE 0 END) = 0 THEN NULL
        ELSE CAST(SUM(CASE WHEN O.[EstadoOrden] = 'Completada' THEN 1 ELSE 0 END) AS DECIMAL(10,2))
             / SUM(CASE WHEN O.[EstadoOrden] IN ('Completada','Cancelada') THEN 1 ELSE 0 END)
    END AS [TasaExito]
FROM [dbo].[Tecnicos] T
LEFT JOIN [dbo].[OrdenesTrabajo] O ON O.[CodigoTecnico] = T.[CodigoTecnico]
GROUP BY T.[CodigoTecnico], T.[CodigoCuadrilla], T.[Nombre], T.[Apellido], T.[EstadoLaboral];
GO

-- ----------------------------------------------------------------------------
-- VISTA: Discrepancias activas. Equipos asignados a tecnicos que no
-- estan instalados ni devueltos. Mismo concepto del SP de discrepancias
-- pero como vista para que Power BI la consuma como tabla.
-- ESTE ES EL REPORTE MAS POLITICO: Claro pregunta esto en cada auditoria.
-- ----------------------------------------------------------------------------
CREATE VIEW [dbo].[vw_KPIDiscrepancias]
AS
SELECT
    T.[CodigoCuadrilla],
    T.[Nombre] + ' ' + T.[Apellido]                 AS [NombreTecnico],
    AE.[NumeroSerie],
    ES.[Modelo],
    ES.[TipoAparato],
    F.[NumeroFactura],
    F.[FechaFactura],
    DATEDIFF(DAY, F.[FechaFactura], GETDATE())      AS [DiasSinResolver],
    CASE
        WHEN DATEDIFF(DAY, F.[FechaFactura], GETDATE()) <= 7  THEN '0-7 dias'
        WHEN DATEDIFF(DAY, F.[FechaFactura], GETDATE()) <= 30 THEN '8-30 dias'
        WHEN DATEDIFF(DAY, F.[FechaFactura], GETDATE()) <= 90 THEN '31-90 dias'
        ELSE '90+ dias'
    END AS [RangoAntiguedad]
FROM [dbo].[AsignacionEquipos] AE
INNER JOIN [dbo].[Facturas] F          ON F.[NumeroFactura] = AE.[NumeroFactura]
INNER JOIN [dbo].[Tecnicos] T          ON T.[CodigoTecnico] = F.[CodigoTecnico]
INNER JOIN [dbo].[EquiposSeriados] ES  ON ES.[NumeroSerie]  = AE.[NumeroSerie]
WHERE AE.[EstadoAsignacion] = 'Activa'
  AND NOT EXISTS (
      SELECT 1 FROM [dbo].[DetalleInstalacion] DI
      WHERE DI.[NumeroSerie] = AE.[NumeroSerie]
  )
  AND NOT EXISTS (
      SELECT 1 FROM [dbo].[DevolucionInventario] DEV
      WHERE DEV.[NumeroSerie] = AE.[NumeroSerie]
        AND DEV.[CodigoTecnico] = F.[CodigoTecnico]
  );
GO

-- ----------------------------------------------------------------------------
-- VISTA: Materiales con su nivel de stock clasificado.
-- Para semaforo de bodega en Power BI: rojo/amarillo/verde.
-- ----------------------------------------------------------------------------
CREATE VIEW [dbo].[vw_KPIStockMateriales]
AS
SELECT
    MM.[CodigoMaterial],
    MM.[NombreMaterial],
    MM.[UnidadMedida],
    MM.[StockBodega],
    -- Consumo promedio diario de los ultimos 30 dias
    ISNULL((
        SELECT SUM(DI.[CantidadUtilizada]) / 30.0
        FROM [dbo].[DetalleInstalacion] DI
        WHERE DI.[CodigoMaterial] = MM.[CodigoMaterial]
          AND DI.[FechaInstalacion] >= DATEADD(DAY, -30, GETDATE())
    ), 0) AS [ConsumoDiarioPromedio],
    -- Dias estimados de cobertura (stock / consumo diario)
    CASE
        WHEN ISNULL((
            SELECT SUM(DI.[CantidadUtilizada]) / 30.0
            FROM [dbo].[DetalleInstalacion] DI
            WHERE DI.[CodigoMaterial] = MM.[CodigoMaterial]
              AND DI.[FechaInstalacion] >= DATEADD(DAY, -30, GETDATE())
        ), 0) = 0 THEN NULL
        ELSE MM.[StockBodega] / (
            SELECT SUM(DI.[CantidadUtilizada]) / 30.0
            FROM [dbo].[DetalleInstalacion] DI
            WHERE DI.[CodigoMaterial] = MM.[CodigoMaterial]
              AND DI.[FechaInstalacion] >= DATEADD(DAY, -30, GETDATE())
        )
    END AS [DiasCobertura],
    -- Clasificacion semaforo
    CASE
        WHEN MM.[StockBodega] = 0 THEN 'Agotado'
        WHEN MM.[StockBodega] < 10 THEN 'Critico'
        WHEN MM.[StockBodega] < 50 THEN 'Bajo'
        ELSE 'Normal'
    END AS [NivelStock]
FROM [dbo].[MaterialesMiscelaneos] MM;
GO

-- ----------------------------------------------------------------------------
-- VISTA: Liquidaciones pendientes de validacion bodega (cuello de
-- botella operativo). Permite ver con que tecnico y cuanto tiempo lleva.
-- ----------------------------------------------------------------------------
CREATE VIEW [dbo].[vw_KPILiquidacionesPendientes]
AS
SELECT
    DI.[IDDetalle],
    DI.[NumeroSolicitud],
    DI.[FechaInstalacion],
    DATEDIFF(DAY, DI.[FechaInstalacion], GETDATE()) AS [DiasSinValidar],
    T.[CodigoCuadrilla],
    T.[Nombre] + ' ' + T.[Apellido]                 AS [NombreTecnico],
    DI.[NumeroSerie],
    DI.[CodigoMaterial],
    DI.[CantidadUtilizada],
    O.[TipoTecnologia]
FROM [dbo].[DetalleInstalacion] DI
INNER JOIN [dbo].[Tecnicos] T       ON T.[CodigoTecnico]   = DI.[CodigoTecnico]
INNER JOIN [dbo].[OrdenesTrabajo] O ON O.[NumeroSolicitud] = DI.[NumeroSolicitud]
WHERE DI.[ValidadoBodega] = 'NO';
GO

/* ############################################################################
   ############################################################################
   PARTE 2 de 3: PROCEDIMIENTOS ALMACENADOS Y TIPOS
   (Origen: PROCONTEL_SP.sql)
   - Tipos TVP, datos iniciales de RBAC y todos los SP base.
   ############################################################################
   ############################################################################ */

USE [Procontel]
GO


/* ============================================================================
   SECCION 0: TIPOS DE DATOS (TABLE-VALUED PARAMETERS)
   ============================================================================
   Los TVP permiten pasar tablas completas como parametro de un SP.
   Se usan en los SP que crean facturas y liquidaciones, que reciben
   listas de equipos y materiales.
   ============================================================================ */

-- TVP para listas de equipos seriados
CREATE TYPE [dbo].[TVP_EquiposSeriados] AS TABLE (
    [NumeroSerie] VARCHAR(50) NOT NULL PRIMARY KEY
)
GO

-- TVP para listas de materiales con cantidad
CREATE TYPE [dbo].[TVP_Materiales] AS TABLE (
    [CodigoMaterial] VARCHAR(15) NOT NULL PRIMARY KEY,
    [Cantidad]       DECIMAL(10,2) NOT NULL
)
GO


/* ============================================================================
   SECCION 1: DATOS INICIALES DE RBAC
   ============================================================================
   Roles, Permisos y asignaciones Rol-Permiso iniciales del sistema.
   Estos datos son parte del sistema, no son datos operativos, por eso
   se cargan junto con los SP.
   ============================================================================ */

-- ----------------------------------------------------------------------------
-- INSERTS DE ROLES (5 roles segun definicion del negocio)
-- ----------------------------------------------------------------------------
INSERT INTO [dbo].[Roles] ([NombreRol], [Descripcion]) VALUES
    ('Gerente',      'Gerente General. Acceso total al sistema, reportes gerenciales y administracion de usuarios.'),
    ('JefeBodega',   'Jefe de Bodega. Supervision de inventario, respuesta a Claro, CRUD de equipos y materiales.'),
    ('Bodeguero',    'Bodeguero. Ejecucion de entregas (facturas) y recepcion de devoluciones.'),
    ('Tecnico',      'Tecnico de campo. Accede solo a sus ordenes asignadas y registra sus liquidaciones.'),
    ('Auditor',      'Auditor. Solo lectura para revision interna o externa (Claro, contraloria).')
GO

-- ----------------------------------------------------------------------------
-- INSERTS DE PERMISOS (permisos atomicos agrupados por modulo)
-- ----------------------------------------------------------------------------
INSERT INTO [dbo].[Permisos] ([CodigoPermiso], [Modulo], [Descripcion]) VALUES
    -- Modulo: Usuarios
    ('Usuario.Crear',              'Usuarios',  'Crear nuevos usuarios del sistema'),
    ('Usuario.Editar',             'Usuarios',  'Editar datos de usuarios existentes'),
    ('Usuario.CambiarEstado',      'Usuarios',  'Activar o desactivar usuarios'),
    ('Usuario.Ver',                'Usuarios',  'Ver listado de usuarios'),
    ('Usuario.AsignarRol',         'Usuarios',  'Asignar o remover roles de usuarios'),

    -- Modulo: Roles y Permisos
    ('Rol.Crear',                  'Roles',     'Crear nuevos roles'),
    ('Rol.Editar',                 'Roles',     'Editar roles existentes'),
    ('Rol.Ver',                    'Roles',     'Ver listado de roles'),
    ('Rol.AsignarPermiso',         'Roles',     'Asignar o remover permisos de roles'),

    -- Modulo: Tecnicos
    ('Tecnico.Crear',              'Tecnicos',  'Crear nuevos tecnicos'),
    ('Tecnico.Editar',             'Tecnicos',  'Editar datos de tecnicos'),
    ('Tecnico.CambiarEstado',      'Tecnicos',  'Activar, inactivar o incapacitar tecnicos'),
    ('Tecnico.Ver',                'Tecnicos',  'Ver listado de tecnicos'),
    ('Tecnico.VerPropio',          'Tecnicos',  'Ver solo su propio perfil de tecnico'),

    -- Modulo: Equipos
    ('Equipo.Ingresar',            'Equipos',   'Ingresar nuevos equipos seriados a bodega'),
    ('Equipo.CambiarEstado',       'Equipos',   'Cambiar estado de equipos'),
    ('Equipo.Ver',                 'Equipos',   'Ver listado completo de equipos'),
    ('Equipo.VerAsignados',        'Equipos',   'Ver solo equipos asignados al usuario actual'),

    -- Modulo: Materiales
    ('Material.Crear',             'Materiales','Crear nuevos materiales'),
    ('Material.Editar',            'Materiales','Editar materiales'),
    ('Material.AjustarStock',      'Materiales','Ajustar el stock de materiales'),
    ('Material.Ver',                'Materiales','Ver listado de materiales'),

    -- Modulo: Ordenes de Trabajo
    ('Orden.Crear',                'Ordenes',   'Crear nuevas ordenes de trabajo'),
    ('Orden.Editar',               'Ordenes',   'Editar ordenes existentes'),
    ('Orden.CambiarEstado',        'Ordenes',   'Cambiar estado de ordenes'),
    ('Orden.AsignarTecnico',       'Ordenes',   'Asignar o reasignar tecnico a una orden'),
    ('Orden.Ver',                  'Ordenes',   'Ver listado completo de ordenes'),
    ('Orden.VerPropia',            'Ordenes',   'Ver solo ordenes asignadas al usuario actual'),

    -- Modulo: Facturas
    ('Factura.Crear',              'Facturas',  'Crear facturas (despacho de equipos a tecnicos)'),
    ('Factura.Anular',             'Facturas',  'Anular facturas'),
    ('Factura.Ver',                'Facturas',  'Ver listado de facturas'),

    -- Modulo: Liquidacion / Instalacion
    ('Liquidacion.Registrar',      'Liquidacion','Registrar liquidacion de una orden (tecnico)'),
    ('Liquidacion.Validar',        'Liquidacion','Validar liquidacion de bodega'),
    ('Liquidacion.Ver',            'Liquidacion','Ver detalles de instalacion'),

    -- Modulo: Averias
    ('Averia.Registrar',           'Averias',   'Registrar averia o garantia'),
    ('Averia.Ver',                 'Averias',   'Ver listado de averias'),

    -- Modulo: Devoluciones
    ('Devolucion.Registrar',       'Devoluciones','Registrar devolucion de equipo o material'),
    ('Devolucion.Ver',             'Devoluciones','Ver listado de devoluciones'),

    -- Modulo: Bitacora
    ('Bitacora.Ver',               'Bitacora',  'Ver bitacora de auditoria'),

    -- Modulo: Reportes
    ('Reporte.Operativo',          'Reportes',  'Ver reportes operativos (inventario, productividad)'),
    ('Reporte.Gerencial',          'Reportes',  'Ver reportes gerenciales y financieros')
GO

-- ----------------------------------------------------------------------------
-- ASIGNACION DE PERMISOS A ROLES
-- ----------------------------------------------------------------------------

-- GERENTE: acceso total. Se asignan TODOS los permisos.
INSERT INTO [dbo].[RolesPermisos] ([IDRol], [IDPermiso])
SELECT R.IDRol, P.IDPermiso
FROM [dbo].[Roles] R CROSS JOIN [dbo].[Permisos] P
WHERE R.NombreRol = 'Gerente'
GO

-- JEFE DE BODEGA: todo lo operativo excepto administracion de usuarios/roles
-- y reportes gerenciales.
INSERT INTO [dbo].[RolesPermisos] ([IDRol], [IDPermiso])
SELECT R.IDRol, P.IDPermiso
FROM [dbo].[Roles] R CROSS JOIN [dbo].[Permisos] P
WHERE R.NombreRol = 'JefeBodega'
  AND P.CodigoPermiso IN (
    'Usuario.Ver',
    'Rol.Ver',
    'Tecnico.Crear', 'Tecnico.Editar', 'Tecnico.CambiarEstado', 'Tecnico.Ver',
    'Equipo.Ingresar', 'Equipo.CambiarEstado', 'Equipo.Ver',
    'Material.Crear', 'Material.Editar', 'Material.AjustarStock', 'Material.Ver',
    'Orden.Crear', 'Orden.Editar', 'Orden.CambiarEstado', 'Orden.AsignarTecnico', 'Orden.Ver',
    'Factura.Crear', 'Factura.Anular', 'Factura.Ver',
    'Liquidacion.Validar', 'Liquidacion.Ver',
    'Averia.Registrar', 'Averia.Ver',
    'Devolucion.Registrar', 'Devolucion.Ver',
    'Bitacora.Ver',
    'Reporte.Operativo'
  )
GO

-- BODEGUERO: operacion de entrega (facturas) y recepcion de devoluciones.
INSERT INTO [dbo].[RolesPermisos] ([IDRol], [IDPermiso])
SELECT R.IDRol, P.IDPermiso
FROM [dbo].[Roles] R CROSS JOIN [dbo].[Permisos] P
WHERE R.NombreRol = 'Bodeguero'
  AND P.CodigoPermiso IN (
    'Tecnico.Ver',
    'Equipo.Ingresar', 'Equipo.Ver',
    'Material.Ver',
    'Orden.Ver',
    'Factura.Crear', 'Factura.Ver',
    'Liquidacion.Validar', 'Liquidacion.Ver',
    'Devolucion.Registrar', 'Devolucion.Ver'
  )
GO

-- TECNICO: solo accesos a sus propias ordenes y sus propias acciones de campo.
INSERT INTO [dbo].[RolesPermisos] ([IDRol], [IDPermiso])
SELECT R.IDRol, P.IDPermiso
FROM [dbo].[Roles] R CROSS JOIN [dbo].[Permisos] P
WHERE R.NombreRol = 'Tecnico'
  AND P.CodigoPermiso IN (
    'Tecnico.VerPropio',
    'Equipo.VerAsignados',
    'Material.Ver',
    'Orden.VerPropia',
    'Liquidacion.Registrar',
    'Averia.Registrar',
    'Devolucion.Registrar'
  )
GO

-- AUDITOR: solo lectura. Lista explicita (no se usa LIKE porque VerPropio/
-- VerAsignados son permisos limitados para tecnicos, no para auditoria).
INSERT INTO [dbo].[RolesPermisos] ([IDRol], [IDPermiso])
SELECT R.IDRol, P.IDPermiso
FROM [dbo].[Roles] R CROSS JOIN [dbo].[Permisos] P
WHERE R.NombreRol = 'Auditor'
  AND P.CodigoPermiso IN (
    'Usuario.Ver',
    'Rol.Ver',
    'Tecnico.Ver',
    'Equipo.Ver',
    'Material.Ver',
    'Orden.Ver',
    'Factura.Ver',
    'Liquidacion.Ver',
    'Averia.Ver',
    'Devolucion.Ver',
    'Bitacora.Ver',
    'Reporte.Operativo',
    'Reporte.Gerencial'
  )
GO


/* ============================================================================
   SECCION 2: SP DE SEGURIDAD Y BITACORA
   ============================================================================ */

-- ----------------------------------------------------------------------------
-- SP interno llamado desde los demas. Registra una accion en la bitacora.
-- ----------------------------------------------------------------------------
CREATE PROCEDURE [dbo].[usp_RegistrarBitacora]
    @TablaAfectada   NVARCHAR(50),
    @TipoOperacion   CHAR(1),
    @RegistroID      NVARCHAR(50),
    @CampoModificado NVARCHAR(50) = NULL,
    @ValorAnterior   NVARCHAR(500) = NULL,
    @ValorNuevo      NVARCHAR(500) = NULL,
    @UsuarioLogin    VARCHAR(20),
    @DireccionIP     VARCHAR(45) = NULL
AS
BEGIN
    SET NOCOUNT ON;

    INSERT INTO [dbo].[BitacoraAuditoria] (
        [TablaAfectada], [TipoOperacion], [RegistroID],
        [CampoModificado], [ValorAnterior], [ValorNuevo],
        [UsuarioLogin], [DireccionIP]
    )
    VALUES (
        @TablaAfectada, @TipoOperacion, @RegistroID,
        @CampoModificado, @ValorAnterior, @ValorNuevo,
        @UsuarioLogin, @DireccionIP
    );
END
GO

-- ----------------------------------------------------------------------------
-- Autentica un usuario. Devuelve ID, login, nombres y roles si es valido.
-- No revela si el error fue por usuario o contrasena.
-- ----------------------------------------------------------------------------
CREATE PROCEDURE [dbo].[usp_AutenticarUsuario]
    @UsuarioLogin  VARCHAR(20),
    @PasswordHash  VARCHAR(128)
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @IDUsuario INT;
    DECLARE @EstadoUsuario NVARCHAR(15);

    SELECT @IDUsuario = [IDUsuario], @EstadoUsuario = [EstadoUsuario]
    FROM [dbo].[Usuarios]
    WHERE [UsuarioLogin] = @UsuarioLogin
      AND [PasswordHash] = @PasswordHash;

    IF @IDUsuario IS NULL
    BEGIN
        THROW 51000, 'Credenciales invalidas.', 1;
        RETURN;
    END

    IF @EstadoUsuario <> 'Activo'
    BEGIN
        THROW 51001, 'Usuario inactivo o bloqueado.', 1;
        RETURN;
    END

    -- Actualizar fecha de ultimo login
    UPDATE [dbo].[Usuarios]
    SET [FechaUltimoLogin] = GETDATE()
    WHERE [IDUsuario] = @IDUsuario;

    -- Devolver datos del usuario autenticado
    SELECT
        U.[IDUsuario],
        U.[UsuarioLogin],
        U.[Nombres],
        U.[Apellidos],
        U.[CodigoTecnico],
        U.[EstadoUsuario]
    FROM [dbo].[Usuarios] U
    WHERE U.[IDUsuario] = @IDUsuario;
END
GO

-- ----------------------------------------------------------------------------
-- Cambia la contrasena de un usuario validando la actual primero.
-- ----------------------------------------------------------------------------
CREATE PROCEDURE [dbo].[usp_CambiarPassword]
    @UsuarioLogin       VARCHAR(20),
    @PasswordActual     VARCHAR(128),
    @PasswordNuevo      VARCHAR(128)
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @IDUsuario INT;

    SELECT @IDUsuario = [IDUsuario]
    FROM [dbo].[Usuarios]
    WHERE [UsuarioLogin] = @UsuarioLogin
      AND [PasswordHash] = @PasswordActual
      AND [EstadoUsuario] = 'Activo';

    IF @IDUsuario IS NULL
    BEGIN
        THROW 51002, 'Contrasena actual incorrecta o usuario inactivo.', 1;
        RETURN;
    END

    UPDATE [dbo].[Usuarios]
    SET [PasswordHash] = @PasswordNuevo
    WHERE [IDUsuario] = @IDUsuario;

    EXEC [dbo].[usp_RegistrarBitacora]
        @TablaAfectada   = N'Usuarios',
        @TipoOperacion   = 'U',
        @RegistroID      = @IDUsuario,
        @CampoModificado = N'PasswordHash',
        @ValorAnterior   = '***',
        @ValorNuevo      = '***',
        @UsuarioLogin    = @UsuarioLogin;
END
GO

-- ----------------------------------------------------------------------------
-- Devuelve todos los permisos efectivos de un usuario (JOIN de sus roles).
-- Este es el SP mas llamado: la app C# lo usa al login para cachear permisos.
-- ----------------------------------------------------------------------------
CREATE PROCEDURE [dbo].[usp_ConsultarPermisosDeUsuario]
    @IDUsuario INT
AS
BEGIN
    SET NOCOUNT ON;

    SELECT DISTINCT
        P.[IDPermiso],
        P.[CodigoPermiso],
        P.[Modulo],
        P.[Descripcion]
    FROM [dbo].[Usuarios] U
    INNER JOIN [dbo].[UsuariosRoles] UR ON UR.[IDUsuario] = U.[IDUsuario]
    INNER JOIN [dbo].[Roles] R          ON R.[IDRol]      = UR.[IDRol]
    INNER JOIN [dbo].[RolesPermisos] RP ON RP.[IDRol]     = R.[IDRol]
    INNER JOIN [dbo].[Permisos] P       ON P.[IDPermiso]  = RP.[IDPermiso]
    WHERE U.[IDUsuario] = @IDUsuario
      AND U.[EstadoUsuario] = 'Activo'
      AND R.[EstadoRol] = 'Activo'
    ORDER BY P.[Modulo], P.[CodigoPermiso];
END
GO

-- ----------------------------------------------------------------------------
-- Consulta historial de cambios de un registro especifico.
-- ----------------------------------------------------------------------------
CREATE PROCEDURE [dbo].[usp_ConsultarBitacoraPorRegistro]
    @TablaAfectada NVARCHAR(50),
    @RegistroID    NVARCHAR(50)
AS
BEGIN
    SET NOCOUNT ON;

    SELECT
        [IDAuditoria], [FechaHora], [TipoOperacion],
        [CampoModificado], [ValorAnterior], [ValorNuevo],
        [UsuarioLogin], [DireccionIP]
    FROM [dbo].[BitacoraAuditoria]
    WHERE [TablaAfectada] = @TablaAfectada
      AND [RegistroID]    = @RegistroID
    ORDER BY [FechaHora] DESC;
END
GO

-- ----------------------------------------------------------------------------
-- Consulta todas las acciones realizadas por un usuario en un rango de fechas.
-- ----------------------------------------------------------------------------
CREATE PROCEDURE [dbo].[usp_ConsultarBitacoraPorUsuario]
    @UsuarioLogin VARCHAR(20),
    @FechaInicio  DATE,
    @FechaFin     DATE
AS
BEGIN
    SET NOCOUNT ON;

    SELECT
        [IDAuditoria], [FechaHora], [TablaAfectada], [TipoOperacion],
        [RegistroID], [CampoModificado], [ValorAnterior], [ValorNuevo],
        [DireccionIP]
    FROM [dbo].[BitacoraAuditoria]
    WHERE [UsuarioLogin] = @UsuarioLogin
      AND [FechaHora] >= @FechaInicio
      AND [FechaHora] <  DATEADD(DAY, 1, @FechaFin)
    ORDER BY [FechaHora] DESC;
END
GO

-- ----------------------------------------------------------------------------
-- Crea un nuevo rol en el catalogo. Solo Gerente puede ejecutarlo.
-- ----------------------------------------------------------------------------
CREATE PROCEDURE [dbo].[usp_InsertarRol]
    @NombreRol    NVARCHAR(50),
    @Descripcion  NVARCHAR(200) = NULL,
    @UsuarioLogin VARCHAR(20)
AS
BEGIN
    SET NOCOUNT ON;

    BEGIN TRY
        INSERT INTO [dbo].[Roles] ([NombreRol], [Descripcion])
        VALUES (@NombreRol, @Descripcion);

        DECLARE @IDRol INT = SCOPE_IDENTITY();

        EXEC [dbo].[usp_RegistrarBitacora]
            @TablaAfectada = N'Roles',
            @TipoOperacion = 'I',
            @RegistroID    = @IDRol,
            @ValorNuevo    = @NombreRol,
            @UsuarioLogin  = @UsuarioLogin;

        SELECT @IDRol AS [IDRol];
    END TRY
    BEGIN CATCH
        THROW;
    END CATCH
END
GO

-- ----------------------------------------------------------------------------
-- Lista todos los roles activos del sistema.
-- ----------------------------------------------------------------------------
CREATE PROCEDURE [dbo].[usp_ListarRoles]
AS
BEGIN
    SET NOCOUNT ON;

    SELECT [IDRol], [NombreRol], [Descripcion], [EstadoRol]
    FROM [dbo].[Roles]
    ORDER BY [NombreRol];
END
GO

-- ----------------------------------------------------------------------------
-- Asigna un rol a un usuario (relacion N:M).
-- ----------------------------------------------------------------------------
CREATE PROCEDURE [dbo].[usp_AsignarRolAUsuario]
    @IDUsuario    INT,
    @IDRol        INT,
    @UsuarioLogin VARCHAR(20)
AS
BEGIN
    SET NOCOUNT ON;

    BEGIN TRY
        -- Verificar que no este ya asignado
        IF EXISTS (SELECT 1 FROM [dbo].[UsuariosRoles]
                   WHERE [IDUsuario] = @IDUsuario AND [IDRol] = @IDRol)
        BEGIN
            THROW 51010, 'El usuario ya tiene este rol asignado.', 1;
            RETURN;
        END

        INSERT INTO [dbo].[UsuariosRoles] ([IDUsuario], [IDRol])
        VALUES (@IDUsuario, @IDRol);

        EXEC [dbo].[usp_RegistrarBitacora]
            @TablaAfectada = N'UsuariosRoles',
            @TipoOperacion = 'I',
            @RegistroID    = @IDUsuario,
            @CampoModificado = N'IDRol',
            @ValorNuevo    = @IDRol,
            @UsuarioLogin  = @UsuarioLogin;
    END TRY
    BEGIN CATCH
        THROW;
    END CATCH
END
GO

-- ----------------------------------------------------------------------------
-- Remueve un rol de un usuario.
-- ----------------------------------------------------------------------------
CREATE PROCEDURE [dbo].[usp_RemoverRolDeUsuario]
    @IDUsuario    INT,
    @IDRol        INT,
    @UsuarioLogin VARCHAR(20)
AS
BEGIN
    SET NOCOUNT ON;

    BEGIN TRY
        DELETE FROM [dbo].[UsuariosRoles]
        WHERE [IDUsuario] = @IDUsuario AND [IDRol] = @IDRol;

        IF @@ROWCOUNT = 0
        BEGIN
            THROW 51011, 'El usuario no tiene este rol asignado.', 1;
            RETURN;
        END

        EXEC [dbo].[usp_RegistrarBitacora]
            @TablaAfectada = N'UsuariosRoles',
            @TipoOperacion = 'D',
            @RegistroID    = @IDUsuario,
            @CampoModificado = N'IDRol',
            @ValorAnterior = @IDRol,
            @UsuarioLogin  = @UsuarioLogin;
    END TRY
    BEGIN CATCH
        THROW;
    END CATCH
END
GO

-- ----------------------------------------------------------------------------
-- Consulta los roles asignados a un usuario.
-- ----------------------------------------------------------------------------
CREATE PROCEDURE [dbo].[usp_ConsultarRolesDeUsuario]
    @IDUsuario INT
AS
BEGIN
    SET NOCOUNT ON;

    SELECT R.[IDRol], R.[NombreRol], R.[Descripcion], UR.[FechaAsignacion]
    FROM [dbo].[UsuariosRoles] UR
    INNER JOIN [dbo].[Roles] R ON R.[IDRol] = UR.[IDRol]
    WHERE UR.[IDUsuario] = @IDUsuario
    ORDER BY R.[NombreRol];
END
GO

-- ----------------------------------------------------------------------------
-- Asigna un permiso a un rol.
-- ----------------------------------------------------------------------------
CREATE PROCEDURE [dbo].[usp_AsignarPermisoARol]
    @IDRol        INT,
    @IDPermiso    INT,
    @UsuarioLogin VARCHAR(20)
AS
BEGIN
    SET NOCOUNT ON;

    BEGIN TRY
        IF EXISTS (SELECT 1 FROM [dbo].[RolesPermisos]
                   WHERE [IDRol] = @IDRol AND [IDPermiso] = @IDPermiso)
        BEGIN
            THROW 51012, 'El rol ya tiene este permiso asignado.', 1;
            RETURN;
        END

        INSERT INTO [dbo].[RolesPermisos] ([IDRol], [IDPermiso])
        VALUES (@IDRol, @IDPermiso);

        EXEC [dbo].[usp_RegistrarBitacora]
            @TablaAfectada = N'RolesPermisos',
            @TipoOperacion = 'I',
            @RegistroID    = @IDRol,
            @CampoModificado = N'IDPermiso',
            @ValorNuevo    = @IDPermiso,
            @UsuarioLogin  = @UsuarioLogin;
    END TRY
    BEGIN CATCH
        THROW;
    END CATCH
END
GO

-- ----------------------------------------------------------------------------
-- Lista todos los permisos disponibles en el sistema.
-- ----------------------------------------------------------------------------
CREATE PROCEDURE [dbo].[usp_ListarPermisos]
AS
BEGIN
    SET NOCOUNT ON;

    SELECT [IDPermiso], [CodigoPermiso], [Modulo], [Descripcion]
    FROM [dbo].[Permisos]
    ORDER BY [Modulo], [CodigoPermiso];
END
GO


/* ============================================================================
   SECCION 3: SP DE TECNICOS
   ============================================================================ */

-- ----------------------------------------------------------------------------
-- Inserta un nuevo tecnico. Los CHECK de BD validan formato.
-- ----------------------------------------------------------------------------
CREATE PROCEDURE [dbo].[usp_InsertarTecnico]
    @CodigoCuadrilla VARCHAR(10),
    @DUI             VARCHAR(10),
    @Nombre          NVARCHAR(50),
    @Apellido        NVARCHAR(50),
    @Direccion       NVARCHAR(150) = NULL,
    @Telefono        VARCHAR(9),
    @TipoSangre      VARCHAR(3),
    @EstadoCivil     NVARCHAR(15),
    @FechaNacimiento DATE,
    @Genero          NVARCHAR(10),
    @TipoLicencia    NVARCHAR(15) = NULL,
    @EstadoLaboral   NVARCHAR(15) = 'Activo',
    @UsuarioLogin    VARCHAR(20)
AS
BEGIN
    SET NOCOUNT ON;

    BEGIN TRY
        INSERT INTO [dbo].[Tecnicos] (
            [CodigoCuadrilla], [DUI], [Nombre], [Apellido], [Direccion],
            [Telefono], [TipoSangre], [EstadoCivil], [FechaNacimiento],
            [Genero], [TipoLicencia], [EstadoLaboral]
        )
        VALUES (
            @CodigoCuadrilla, @DUI, @Nombre, @Apellido, @Direccion,
            @Telefono, @TipoSangre, @EstadoCivil, @FechaNacimiento,
            @Genero, @TipoLicencia, @EstadoLaboral
        );

        DECLARE @CodigoTecnico INT = SCOPE_IDENTITY();

        EXEC [dbo].[usp_RegistrarBitacora]
            @TablaAfectada = N'Tecnicos',
            @TipoOperacion = 'I',
            @RegistroID    = @CodigoTecnico,
            @ValorNuevo    = @CodigoCuadrilla,
            @UsuarioLogin  = @UsuarioLogin;

        SELECT @CodigoTecnico AS [CodigoTecnico];
    END TRY
    BEGIN CATCH
        THROW;
    END CATCH
END
GO

-- ----------------------------------------------------------------------------
-- Actualiza datos de un tecnico (excepto DUI y CodigoCuadrilla que son fijos).
-- ----------------------------------------------------------------------------
CREATE PROCEDURE [dbo].[usp_ActualizarTecnico]
    @CodigoTecnico   INT,
    @Nombre          NVARCHAR(50),
    @Apellido        NVARCHAR(50),
    @Direccion       NVARCHAR(150) = NULL,
    @Telefono        VARCHAR(9),
    @TipoSangre      VARCHAR(3),
    @EstadoCivil     NVARCHAR(15),
    @Genero          NVARCHAR(10),
    @TipoLicencia    NVARCHAR(15) = NULL,
    @UsuarioLogin    VARCHAR(20)
AS
BEGIN
    SET NOCOUNT ON;

    BEGIN TRY
        IF NOT EXISTS (SELECT 1 FROM [dbo].[Tecnicos] WHERE [CodigoTecnico] = @CodigoTecnico)
        BEGIN
            THROW 52000, 'Tecnico no encontrado.', 1;
            RETURN;
        END

        UPDATE [dbo].[Tecnicos]
        SET [Nombre]       = @Nombre,
            [Apellido]     = @Apellido,
            [Direccion]    = @Direccion,
            [Telefono]     = @Telefono,
            [TipoSangre]   = @TipoSangre,
            [EstadoCivil]  = @EstadoCivil,
            [Genero]       = @Genero,
            [TipoLicencia] = @TipoLicencia
        WHERE [CodigoTecnico] = @CodigoTecnico;

        EXEC [dbo].[usp_RegistrarBitacora]
            @TablaAfectada = N'Tecnicos',
            @TipoOperacion = 'U',
            @RegistroID    = @CodigoTecnico,
            @UsuarioLogin  = @UsuarioLogin;
    END TRY
    BEGIN CATCH
        THROW;
    END CATCH
END
GO

-- ----------------------------------------------------------------------------
-- Cambia estado laboral del tecnico (Activo/Inactivo/Incapacitado).
-- ----------------------------------------------------------------------------
CREATE PROCEDURE [dbo].[usp_CambiarEstadoLaboralTecnico]
    @CodigoTecnico  INT,
    @NuevoEstado    NVARCHAR(15),
    @UsuarioLogin   VARCHAR(20)
AS
BEGIN
    SET NOCOUNT ON;

    BEGIN TRY
        DECLARE @EstadoAnterior NVARCHAR(15);

        SELECT @EstadoAnterior = [EstadoLaboral]
        FROM [dbo].[Tecnicos]
        WHERE [CodigoTecnico] = @CodigoTecnico;

        IF @EstadoAnterior IS NULL
        BEGIN
            THROW 52000, 'Tecnico no encontrado.', 1;
            RETURN;
        END

        UPDATE [dbo].[Tecnicos]
        SET [EstadoLaboral] = @NuevoEstado
        WHERE [CodigoTecnico] = @CodigoTecnico;

        EXEC [dbo].[usp_RegistrarBitacora]
            @TablaAfectada   = N'Tecnicos',
            @TipoOperacion   = 'U',
            @RegistroID      = @CodigoTecnico,
            @CampoModificado = N'EstadoLaboral',
            @ValorAnterior   = @EstadoAnterior,
            @ValorNuevo      = @NuevoEstado,
            @UsuarioLogin    = @UsuarioLogin;
    END TRY
    BEGIN CATCH
        THROW;
    END CATCH
END
GO

-- ----------------------------------------------------------------------------
-- Consulta todos los datos de un tecnico por su codigo interno.
-- ----------------------------------------------------------------------------
CREATE PROCEDURE [dbo].[usp_ConsultarTecnicoPorCodigo]
    @CodigoTecnico INT
AS
BEGIN
    SET NOCOUNT ON;

    SELECT *
    FROM [dbo].[Tecnicos]
    WHERE [CodigoTecnico] = @CodigoTecnico;
END
GO

-- ----------------------------------------------------------------------------
-- Busqueda de tecnico por numero de DUI.
-- ----------------------------------------------------------------------------
CREATE PROCEDURE [dbo].[usp_ConsultarTecnicoPorDUI]
    @DUI VARCHAR(10)
AS
BEGIN
    SET NOCOUNT ON;

    SELECT *
    FROM [dbo].[Tecnicos]
    WHERE [DUI] = @DUI;
END
GO

-- ----------------------------------------------------------------------------
-- Tecnicos con estado Activo. Para poblar dropdowns de la UI.
-- ----------------------------------------------------------------------------
CREATE PROCEDURE [dbo].[usp_ListarTecnicosActivos]
AS
BEGIN
    SET NOCOUNT ON;

    SELECT [CodigoTecnico], [CodigoCuadrilla], [Nombre], [Apellido], [Telefono]
    FROM [dbo].[Tecnicos]
    WHERE [EstadoLaboral] = 'Activo'
    ORDER BY [CodigoCuadrilla];
END
GO

-- ----------------------------------------------------------------------------
-- Listado general con filtro opcional por estado laboral.
-- ----------------------------------------------------------------------------
CREATE PROCEDURE [dbo].[usp_ListarTecnicos]
    @EstadoLaboral NVARCHAR(15) = NULL
AS
BEGIN
    SET NOCOUNT ON;

    SELECT [CodigoTecnico], [CodigoCuadrilla], [DUI], [Nombre], [Apellido],
           [Telefono], [TipoLicencia], [EstadoLaboral]
    FROM [dbo].[Tecnicos]
    WHERE (@EstadoLaboral IS NULL OR [EstadoLaboral] = @EstadoLaboral)
    ORDER BY [CodigoCuadrilla];
END
GO


/* ============================================================================
   SECCION 4: SP DE USUARIOS
   ============================================================================ */

-- ----------------------------------------------------------------------------
-- Inserta un nuevo usuario. El password llega ya hasheado desde la app.
-- ----------------------------------------------------------------------------
CREATE PROCEDURE [dbo].[usp_InsertarUsuario]
    @UsuarioLoginNuevo  VARCHAR(20),
    @PasswordHash       VARCHAR(128),
    @Nombres            NVARCHAR(50),
    @Apellidos          NVARCHAR(50),
    @CorreoElectronico  NVARCHAR(100) = NULL,
    @CodigoTecnico      INT = NULL,
    @UsuarioLogin       VARCHAR(20)
AS
BEGIN
    SET NOCOUNT ON;

    BEGIN TRY
        INSERT INTO [dbo].[Usuarios] (
            [UsuarioLogin], [PasswordHash], [Nombres], [Apellidos],
            [CorreoElectronico], [CodigoTecnico]
        )
        VALUES (
            @UsuarioLoginNuevo, @PasswordHash, @Nombres, @Apellidos,
            @CorreoElectronico, @CodigoTecnico
        );

        DECLARE @IDUsuario INT = SCOPE_IDENTITY();

        EXEC [dbo].[usp_RegistrarBitacora]
            @TablaAfectada = N'Usuarios',
            @TipoOperacion = 'I',
            @RegistroID    = @IDUsuario,
            @ValorNuevo    = @UsuarioLoginNuevo,
            @UsuarioLogin  = @UsuarioLogin;

        SELECT @IDUsuario AS [IDUsuario];
    END TRY
    BEGIN CATCH
        THROW;
    END CATCH
END
GO

-- ----------------------------------------------------------------------------
-- Actualiza datos de un usuario (no toca password ni login).
-- ----------------------------------------------------------------------------
CREATE PROCEDURE [dbo].[usp_ActualizarUsuario]
    @IDUsuario          INT,
    @Nombres            NVARCHAR(50),
    @Apellidos          NVARCHAR(50),
    @CorreoElectronico  NVARCHAR(100) = NULL,
    @UsuarioLogin       VARCHAR(20)
AS
BEGIN
    SET NOCOUNT ON;

    BEGIN TRY
        IF NOT EXISTS (SELECT 1 FROM [dbo].[Usuarios] WHERE [IDUsuario] = @IDUsuario)
        BEGIN
            THROW 53000, 'Usuario no encontrado.', 1;
            RETURN;
        END

        UPDATE [dbo].[Usuarios]
        SET [Nombres]           = @Nombres,
            [Apellidos]         = @Apellidos,
            [CorreoElectronico] = @CorreoElectronico
        WHERE [IDUsuario] = @IDUsuario;

        EXEC [dbo].[usp_RegistrarBitacora]
            @TablaAfectada = N'Usuarios',
            @TipoOperacion = 'U',
            @RegistroID    = @IDUsuario,
            @UsuarioLogin  = @UsuarioLogin;
    END TRY
    BEGIN CATCH
        THROW;
    END CATCH
END
GO

-- ----------------------------------------------------------------------------
-- Activa o desactiva un usuario (sin borrar). Soft delete.
-- ----------------------------------------------------------------------------
CREATE PROCEDURE [dbo].[usp_CambiarEstadoUsuario]
    @IDUsuario      INT,
    @NuevoEstado    NVARCHAR(15),
    @UsuarioLogin   VARCHAR(20)
AS
BEGIN
    SET NOCOUNT ON;

    BEGIN TRY
        DECLARE @EstadoAnterior NVARCHAR(15);

        SELECT @EstadoAnterior = [EstadoUsuario]
        FROM [dbo].[Usuarios]
        WHERE [IDUsuario] = @IDUsuario;

        IF @EstadoAnterior IS NULL
        BEGIN
            THROW 53000, 'Usuario no encontrado.', 1;
            RETURN;
        END

        UPDATE [dbo].[Usuarios]
        SET [EstadoUsuario] = @NuevoEstado
        WHERE [IDUsuario] = @IDUsuario;

        EXEC [dbo].[usp_RegistrarBitacora]
            @TablaAfectada   = N'Usuarios',
            @TipoOperacion   = 'U',
            @RegistroID      = @IDUsuario,
            @CampoModificado = N'EstadoUsuario',
            @ValorAnterior   = @EstadoAnterior,
            @ValorNuevo      = @NuevoEstado,
            @UsuarioLogin    = @UsuarioLogin;
    END TRY
    BEGIN CATCH
        THROW;
    END CATCH
END
GO

-- ----------------------------------------------------------------------------
-- Devuelve datos de un usuario por su ID.
-- ----------------------------------------------------------------------------
CREATE PROCEDURE [dbo].[usp_ConsultarUsuarioPorCodigo]
    @IDUsuario INT
AS
BEGIN
    SET NOCOUNT ON;

    SELECT
        U.[IDUsuario], U.[UsuarioLogin], U.[Nombres], U.[Apellidos],
        U.[CorreoElectronico], U.[CodigoTecnico], U.[EstadoUsuario],
        U.[FechaCreacion], U.[FechaUltimoLogin],
        T.[CodigoCuadrilla]
    FROM [dbo].[Usuarios] U
    LEFT JOIN [dbo].[Tecnicos] T ON T.[CodigoTecnico] = U.[CodigoTecnico]
    WHERE U.[IDUsuario] = @IDUsuario;
END
GO

-- ----------------------------------------------------------------------------
-- Usuarios activos. Para poblar dropdowns de administracion.
-- ----------------------------------------------------------------------------
CREATE PROCEDURE [dbo].[usp_ListarUsuariosActivos]
AS
BEGIN
    SET NOCOUNT ON;

    SELECT [IDUsuario], [UsuarioLogin], [Nombres], [Apellidos], [CodigoTecnico]
    FROM [dbo].[Usuarios]
    WHERE [EstadoUsuario] = 'Activo'
    ORDER BY [UsuarioLogin];
END
GO


/* ============================================================================
   SECCION 5: SP DE EQUIPOS SERIADOS
   ============================================================================ */

-- ----------------------------------------------------------------------------
-- Registra un equipo nuevo en bodega. Valida que la serie no exista.
-- ----------------------------------------------------------------------------
CREATE PROCEDURE [dbo].[usp_IngresarEquipoBodega]
    @NumeroSerie   VARCHAR(50),
    @Modelo        NVARCHAR(100),
    @TipoAparato   NVARCHAR(20),
    @UsuarioLogin  VARCHAR(20)
AS
BEGIN
    SET NOCOUNT ON;

    BEGIN TRY
        IF EXISTS (SELECT 1 FROM [dbo].[EquiposSeriados] WHERE [NumeroSerie] = @NumeroSerie)
        BEGIN
            THROW 54000, 'Numero de serie ya existe en el sistema.', 1;
            RETURN;
        END

        INSERT INTO [dbo].[EquiposSeriados] ([NumeroSerie], [Modelo], [TipoAparato], [EstadoEquipo])
        VALUES (@NumeroSerie, @Modelo, @TipoAparato, 'Bodega');

        EXEC [dbo].[usp_RegistrarBitacora]
            @TablaAfectada = N'EquiposSeriados',
            @TipoOperacion = 'I',
            @RegistroID    = @NumeroSerie,
            @ValorNuevo    = @Modelo,
            @UsuarioLogin  = @UsuarioLogin;
    END TRY
    BEGIN CATCH
        THROW;
    END CATCH
END
GO

-- ----------------------------------------------------------------------------
-- Ingreso masivo de equipos via TVP. Transaccional: todo o nada. [COMPUESTO]
-- ----------------------------------------------------------------------------
CREATE PROCEDURE [dbo].[usp_IngresarLoteEquipos]
    @Modelo        NVARCHAR(100),
    @TipoAparato   NVARCHAR(20),
    @Equipos       [dbo].[TVP_EquiposSeriados] READONLY,
    @UsuarioLogin  VARCHAR(20)
AS
BEGIN
    SET NOCOUNT ON;

    BEGIN TRY
        BEGIN TRANSACTION;

        -- Validar que ningun numero de serie ya exista
        IF EXISTS (
            SELECT 1 FROM @Equipos E
            INNER JOIN [dbo].[EquiposSeriados] ES ON ES.[NumeroSerie] = E.[NumeroSerie]
        )
        BEGIN
            THROW 54001, 'Al menos un numero de serie del lote ya existe.', 1;
            RETURN;
        END

        INSERT INTO [dbo].[EquiposSeriados] ([NumeroSerie], [Modelo], [TipoAparato], [EstadoEquipo])
        SELECT [NumeroSerie], @Modelo, @TipoAparato, 'Bodega'
        FROM @Equipos;

        -- Bitacora: un registro por equipo
        INSERT INTO [dbo].[BitacoraAuditoria] (
            [TablaAfectada], [TipoOperacion], [RegistroID], [ValorNuevo], [UsuarioLogin]
        )
        SELECT N'EquiposSeriados', 'I', [NumeroSerie], @Modelo, @UsuarioLogin
        FROM @Equipos;

        COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        THROW;
    END CATCH
END
GO

-- ----------------------------------------------------------------------------
-- Cambia estado de un equipo (Bodega/Asignado/Instalado/Danado/Garantia).
-- ----------------------------------------------------------------------------
CREATE PROCEDURE [dbo].[usp_CambiarEstadoEquipo]
    @NumeroSerie    VARCHAR(50),
    @NuevoEstado    NVARCHAR(15),
    @UsuarioLogin   VARCHAR(20)
AS
BEGIN
    SET NOCOUNT ON;

    BEGIN TRY
        DECLARE @EstadoAnterior NVARCHAR(15);

        SELECT @EstadoAnterior = [EstadoEquipo]
        FROM [dbo].[EquiposSeriados]
        WHERE [NumeroSerie] = @NumeroSerie;

        IF @EstadoAnterior IS NULL
        BEGIN
            THROW 54002, 'Equipo no encontrado.', 1;
            RETURN;
        END

        UPDATE [dbo].[EquiposSeriados]
        SET [EstadoEquipo] = @NuevoEstado
        WHERE [NumeroSerie] = @NumeroSerie;

        EXEC [dbo].[usp_RegistrarBitacora]
            @TablaAfectada   = N'EquiposSeriados',
            @TipoOperacion   = 'U',
            @RegistroID      = @NumeroSerie,
            @CampoModificado = N'EstadoEquipo',
            @ValorAnterior   = @EstadoAnterior,
            @ValorNuevo      = @NuevoEstado,
            @UsuarioLogin    = @UsuarioLogin;
    END TRY
    BEGIN CATCH
        THROW;
    END CATCH
END
GO

-- ----------------------------------------------------------------------------
-- Devuelve datos del equipo + estado + tecnico asignado si aplica.
-- ----------------------------------------------------------------------------
CREATE PROCEDURE [dbo].[usp_ConsultarEquipoPorSerie]
    @NumeroSerie VARCHAR(50)
AS
BEGIN
    SET NOCOUNT ON;

    SELECT
        ES.[NumeroSerie], ES.[Modelo], ES.[TipoAparato], ES.[EstadoEquipo],
        ES.[FechaIngreso],
        T.[CodigoCuadrilla], T.[Nombre] + ' ' + T.[Apellido] AS [NombreTecnico]
    FROM [dbo].[EquiposSeriados] ES
    LEFT JOIN [dbo].[AsignacionEquipos] AE
        ON AE.[NumeroSerie] = ES.[NumeroSerie] AND AE.[EstadoAsignacion] = 'Activa'
    LEFT JOIN [dbo].[Facturas] F ON F.[NumeroFactura] = AE.[NumeroFactura]
    LEFT JOIN [dbo].[Tecnicos] T  ON T.[CodigoTecnico] = F.[CodigoTecnico]
    WHERE ES.[NumeroSerie] = @NumeroSerie;
END
GO

-- ----------------------------------------------------------------------------
-- Equipos en estado Bodega filtrados por tipo de aparato.
-- ----------------------------------------------------------------------------
CREATE PROCEDURE [dbo].[usp_ListarEquiposDisponibles]
    @TipoAparato NVARCHAR(20) = NULL
AS
BEGIN
    SET NOCOUNT ON;

    SELECT [NumeroSerie], [Modelo], [TipoAparato], [FechaIngreso]
    FROM [dbo].[EquiposSeriados]
    WHERE [EstadoEquipo] = 'Bodega'
      AND (@TipoAparato IS NULL OR [TipoAparato] = @TipoAparato)
    ORDER BY [TipoAparato], [FechaIngreso];
END
GO

-- ----------------------------------------------------------------------------
-- Equipos actualmente asignados a un tecnico (asignacion Activa).
-- ----------------------------------------------------------------------------
CREATE PROCEDURE [dbo].[usp_ListarEquiposPorTecnico]
    @CodigoTecnico INT
AS
BEGIN
    SET NOCOUNT ON;

    SELECT
        ES.[NumeroSerie], ES.[Modelo], ES.[TipoAparato], ES.[EstadoEquipo],
        F.[NumeroFactura], F.[FechaFactura]
    FROM [dbo].[AsignacionEquipos] AE
    INNER JOIN [dbo].[Facturas] F         ON F.[NumeroFactura] = AE.[NumeroFactura]
    INNER JOIN [dbo].[EquiposSeriados] ES ON ES.[NumeroSerie]  = AE.[NumeroSerie]
    WHERE F.[CodigoTecnico] = @CodigoTecnico
      AND AE.[EstadoAsignacion] = 'Activa'
    ORDER BY F.[FechaFactura] DESC;
END
GO


/* ============================================================================
   SECCION 6: SP DE MATERIALES MISCELANEOS
   ============================================================================ */

-- ----------------------------------------------------------------------------
-- Inserta un nuevo material en el catalogo.
-- ----------------------------------------------------------------------------
CREATE PROCEDURE [dbo].[usp_InsertarMaterial]
    @CodigoMaterial VARCHAR(15),
    @NombreMaterial NVARCHAR(100),
    @UnidadMedida   NVARCHAR(20),
    @StockInicial   DECIMAL(10,2) = 0,
    @UsuarioLogin   VARCHAR(20)
AS
BEGIN
    SET NOCOUNT ON;

    BEGIN TRY
        INSERT INTO [dbo].[MaterialesMiscelaneos] ([CodigoMaterial], [NombreMaterial], [UnidadMedida], [StockBodega])
        VALUES (@CodigoMaterial, @NombreMaterial, @UnidadMedida, @StockInicial);

        EXEC [dbo].[usp_RegistrarBitacora]
            @TablaAfectada = N'MaterialesMiscelaneos',
            @TipoOperacion = 'I',
            @RegistroID    = @CodigoMaterial,
            @ValorNuevo    = @NombreMaterial,
            @UsuarioLogin  = @UsuarioLogin;
    END TRY
    BEGIN CATCH
        THROW;
    END CATCH
END
GO

-- ----------------------------------------------------------------------------
-- Actualiza nombre y unidad de medida de un material.
-- ----------------------------------------------------------------------------
CREATE PROCEDURE [dbo].[usp_ActualizarMaterial]
    @CodigoMaterial VARCHAR(15),
    @NombreMaterial NVARCHAR(100),
    @UnidadMedida   NVARCHAR(20),
    @UsuarioLogin   VARCHAR(20)
AS
BEGIN
    SET NOCOUNT ON;

    BEGIN TRY
        IF NOT EXISTS (SELECT 1 FROM [dbo].[MaterialesMiscelaneos] WHERE [CodigoMaterial] = @CodigoMaterial)
        BEGIN
            THROW 55000, 'Material no encontrado.', 1;
            RETURN;
        END

        UPDATE [dbo].[MaterialesMiscelaneos]
        SET [NombreMaterial] = @NombreMaterial,
            [UnidadMedida]   = @UnidadMedida
        WHERE [CodigoMaterial] = @CodigoMaterial;

        EXEC [dbo].[usp_RegistrarBitacora]
            @TablaAfectada = N'MaterialesMiscelaneos',
            @TipoOperacion = 'U',
            @RegistroID    = @CodigoMaterial,
            @UsuarioLogin  = @UsuarioLogin;
    END TRY
    BEGIN CATCH
        THROW;
    END CATCH
END
GO

-- ----------------------------------------------------------------------------
-- Suma o resta stock de un material. Valida que no quede negativo.
-- ----------------------------------------------------------------------------
CREATE PROCEDURE [dbo].[usp_AjustarStockMaterial]
    @CodigoMaterial VARCHAR(15),
    @Ajuste         DECIMAL(10,2),
    @Motivo         NVARCHAR(100),
    @UsuarioLogin   VARCHAR(20)
AS
BEGIN
    SET NOCOUNT ON;

    BEGIN TRY
        DECLARE @StockActual DECIMAL(10,2);

        SELECT @StockActual = [StockBodega]
        FROM [dbo].[MaterialesMiscelaneos]
        WHERE [CodigoMaterial] = @CodigoMaterial;

        IF @StockActual IS NULL
        BEGIN
            THROW 55000, 'Material no encontrado.', 1;
            RETURN;
        END

        IF (@StockActual + @Ajuste) < 0
        BEGIN
            THROW 55001, 'El ajuste dejaria el stock en negativo.', 1;
            RETURN;
        END

        UPDATE [dbo].[MaterialesMiscelaneos]
        SET [StockBodega] = [StockBodega] + @Ajuste
        WHERE [CodigoMaterial] = @CodigoMaterial;

        -- 1. Declarar variables temporales para los valores en formato string
        DECLARE @ValorAnteriorStr NVARCHAR(20) = CAST(@StockActual AS NVARCHAR(20));
        DECLARE @ValorNuevoStr NVARCHAR(20) = CAST((@StockActual + @Ajuste) AS NVARCHAR(20));

        -- 2. Ejecutar la bitácora pasando las variables limpias
        EXEC [dbo].[usp_RegistrarBitacora]
            @TablaAfectada   = N'MaterialesMiscelaneos',
            @TipoOperacion   = 'U',
            @RegistroID      = @CodigoMaterial,
            @CampoModificado = N'StockBodega',
            @ValorAnterior   = @ValorAnteriorStr,
            @ValorNuevo      = @ValorNuevoStr,
            @UsuarioLogin    = @UsuarioLogin;
            
    END TRY
    BEGIN CATCH
        THROW;
    END CATCH
END
GO

-- ----------------------------------------------------------------------------
-- Consulta datos de un material + stock actual.
-- ----------------------------------------------------------------------------
CREATE PROCEDURE [dbo].[usp_ConsultarMaterialPorCodigo]
    @CodigoMaterial VARCHAR(15)
AS
BEGIN
    SET NOCOUNT ON;

    SELECT *
    FROM [dbo].[MaterialesMiscelaneos]
    WHERE [CodigoMaterial] = @CodigoMaterial;
END
GO

-- ----------------------------------------------------------------------------
-- Lista materiales con stock disponible mayor a cero.
-- ----------------------------------------------------------------------------
CREATE PROCEDURE [dbo].[usp_ListarMaterialesConStock]
AS
BEGIN
    SET NOCOUNT ON;

    SELECT [CodigoMaterial], [NombreMaterial], [UnidadMedida], [StockBodega]
    FROM [dbo].[MaterialesMiscelaneos]
    WHERE [StockBodega] > 0
    ORDER BY [NombreMaterial];
END
GO

-- ----------------------------------------------------------------------------
-- Materiales con stock por debajo de un umbral. Para alertas de reabasto.
-- ----------------------------------------------------------------------------
CREATE PROCEDURE [dbo].[usp_ListarMaterialesBajoStock]
    @Umbral DECIMAL(10,2)
AS
BEGIN
    SET NOCOUNT ON;

    SELECT [CodigoMaterial], [NombreMaterial], [UnidadMedida], [StockBodega]
    FROM [dbo].[MaterialesMiscelaneos]
    WHERE [StockBodega] <= @Umbral
    ORDER BY [StockBodega] ASC;
END
GO


/* ============================================================================
   SECCION 7: SP DE ORDENES DE TRABAJO
   ============================================================================ */

-- ----------------------------------------------------------------------------
-- Crea una nueva orden en estado Pendiente. Valida que el tecnico este Activo.
-- ----------------------------------------------------------------------------
CREATE PROCEDURE [dbo].[usp_CrearOrdenTrabajo]
    @NumeroSolicitud       VARCHAR(20),
    @CodigoTecnico         INT,
    @NombreTitular         NVARCHAR(100),
    @ND                    VARCHAR(15) = NULL,
    @OrdenServicio         NVARCHAR(100),
    @TipoTecnologia        NVARCHAR(20),
    @ContactoPrincipal     VARCHAR(9),
    @ContactoSecundario    VARCHAR(9) = NULL,
    @DireccionInstalacion  NVARCHAR(200),
    @CobroTecnico          DECIMAL(10,2) = 0,
    @UsuarioLogin          VARCHAR(20)
AS
BEGIN
    SET NOCOUNT ON;

    BEGIN TRY
        IF NOT EXISTS (
            SELECT 1 FROM [dbo].[Tecnicos]
            WHERE [CodigoTecnico] = @CodigoTecnico AND [EstadoLaboral] = 'Activo'
        )
        BEGIN
            THROW 56000, 'Tecnico no encontrado o no esta activo.', 1;
            RETURN;
        END

        INSERT INTO [dbo].[OrdenesTrabajo] (
            [NumeroSolicitud], [CodigoTecnico], [NombreTitular], [ND],
            [OrdenServicio], [TipoTecnologia], [ContactoPrincipal],
            [ContactoSecundario], [DireccionInstalacion], [CobroTecnico],
            [EstadoOrden]
        )
        VALUES (
            @NumeroSolicitud, @CodigoTecnico, @NombreTitular, @ND,
            @OrdenServicio, @TipoTecnologia, @ContactoPrincipal,
            @ContactoSecundario, @DireccionInstalacion, @CobroTecnico,
            'Pendiente'
        );

        EXEC [dbo].[usp_RegistrarBitacora]
            @TablaAfectada = N'OrdenesTrabajo',
            @TipoOperacion = 'I',
            @RegistroID    = @NumeroSolicitud,
            @ValorNuevo    = @OrdenServicio,
            @UsuarioLogin  = @UsuarioLogin;
    END TRY
    BEGIN CATCH
        THROW;
    END CATCH
END
GO

-- ----------------------------------------------------------------------------
-- Reasigna una orden a otro tecnico. Valida que el nuevo tecnico este Activo.
-- ----------------------------------------------------------------------------
CREATE PROCEDURE [dbo].[usp_AsignarTecnicoAOrden]
    @NumeroSolicitud   VARCHAR(20),
    @NuevoTecnico      INT,
    @UsuarioLogin      VARCHAR(20)
AS
BEGIN
    SET NOCOUNT ON;

    BEGIN TRY
        DECLARE @TecnicoAnterior INT;

        SELECT @TecnicoAnterior = [CodigoTecnico]
        FROM [dbo].[OrdenesTrabajo]
        WHERE [NumeroSolicitud] = @NumeroSolicitud;

        IF @TecnicoAnterior IS NULL
        BEGIN
            THROW 56001, 'Orden no encontrada.', 1;
            RETURN;
        END

        IF NOT EXISTS (
            SELECT 1 FROM [dbo].[Tecnicos]
            WHERE [CodigoTecnico] = @NuevoTecnico AND [EstadoLaboral] = 'Activo'
        )
        BEGIN
            THROW 56000, 'Nuevo tecnico no encontrado o no esta activo.', 1;
            RETURN;
        END

        UPDATE [dbo].[OrdenesTrabajo]
        SET [CodigoTecnico] = @NuevoTecnico
        WHERE [NumeroSolicitud] = @NumeroSolicitud;

        -- 1. Declarar variables temporales para los valores en formato string
        DECLARE @TecnicoAnteriorStr NVARCHAR(20) = CAST(@TecnicoAnterior AS NVARCHAR(20));
        DECLARE @NuevoTecnicoStr NVARCHAR(20) = CAST(@NuevoTecnico AS NVARCHAR(20));

        -- 2. Ejecutar la bitácora pasando las variables limpias
        EXEC [dbo].[usp_RegistrarBitacora]
            @TablaAfectada   = N'OrdenesTrabajo',
            @TipoOperacion   = 'U',
            @RegistroID      = @NumeroSolicitud,
            @CampoModificado = N'CodigoTecnico',
            @ValorAnterior   = @TecnicoAnteriorStr,
            @ValorNuevo      = @NuevoTecnicoStr,
            @UsuarioLogin    = @UsuarioLogin;
            
    END TRY
    BEGIN CATCH
        THROW;
    END CATCH
END
GO

-- ----------------------------------------------------------------------------
-- Cambia estado de una orden. Valida transiciones logicas.
-- ----------------------------------------------------------------------------
CREATE PROCEDURE [dbo].[usp_CambiarEstadoOrden]
    @NumeroSolicitud   VARCHAR(20),
    @NuevoEstado       NVARCHAR(20),
    @UsuarioLogin      VARCHAR(20)
AS
BEGIN
    SET NOCOUNT ON;

    BEGIN TRY
        DECLARE @EstadoAnterior NVARCHAR(20);

        SELECT @EstadoAnterior = [EstadoOrden]
        FROM [dbo].[OrdenesTrabajo]
        WHERE [NumeroSolicitud] = @NumeroSolicitud;

        IF @EstadoAnterior IS NULL
        BEGIN
            THROW 56001, 'Orden no encontrada.', 1;
            RETURN;
        END

        -- Transiciones validas:
        -- Pendiente   -> En Proceso, Cancelada
        -- En Proceso  -> Completada, Cancelada
        -- Completada  -> (terminal)
        -- Cancelada   -> (terminal)
        IF @EstadoAnterior IN ('Completada','Cancelada')
        BEGIN
            THROW 56002, 'La orden esta en estado terminal y no puede cambiar.', 1;
            RETURN;
        END

        IF @EstadoAnterior = 'Pendiente' AND @NuevoEstado NOT IN ('En Proceso','Cancelada')
        BEGIN
            THROW 56003, 'Transicion de estado no valida desde Pendiente.', 1;
            RETURN;
        END

        IF @EstadoAnterior = 'En Proceso' AND @NuevoEstado NOT IN ('Completada','Cancelada')
        BEGIN
            THROW 56004, 'Transicion de estado no valida desde En Proceso.', 1;
            RETURN;
        END

        UPDATE [dbo].[OrdenesTrabajo]
        SET [EstadoOrden] = @NuevoEstado
        WHERE [NumeroSolicitud] = @NumeroSolicitud;

        EXEC [dbo].[usp_RegistrarBitacora]
            @TablaAfectada   = N'OrdenesTrabajo',
            @TipoOperacion   = 'U',
            @RegistroID      = @NumeroSolicitud,
            @CampoModificado = N'EstadoOrden',
            @ValorAnterior   = @EstadoAnterior,
            @ValorNuevo      = @NuevoEstado,
            @UsuarioLogin    = @UsuarioLogin;
    END TRY
    BEGIN CATCH
        THROW;
    END CATCH
END
GO

-- ----------------------------------------------------------------------------
-- Consulta una orden completa + datos del tecnico asignado.
-- ----------------------------------------------------------------------------
CREATE PROCEDURE [dbo].[usp_ConsultarOrdenPorNumero]
    @NumeroSolicitud VARCHAR(20)
AS
BEGIN
    SET NOCOUNT ON;

    SELECT
        O.*,
        T.[CodigoCuadrilla],
        T.[Nombre] + ' ' + T.[Apellido] AS [NombreTecnico],
        T.[Telefono] AS [TelefonoTecnico]
    FROM [dbo].[OrdenesTrabajo] O
    INNER JOIN [dbo].[Tecnicos] T ON T.[CodigoTecnico] = O.[CodigoTecnico]
    WHERE O.[NumeroSolicitud] = @NumeroSolicitud;
END
GO

-- ----------------------------------------------------------------------------
-- Ordenes de un tecnico con filtro opcional por estado.
-- ----------------------------------------------------------------------------
CREATE PROCEDURE [dbo].[usp_ListarOrdenesPorTecnico]
    @CodigoTecnico INT,
    @EstadoOrden   NVARCHAR(20) = NULL
AS
BEGIN
    SET NOCOUNT ON;

    SELECT [NumeroSolicitud], [NombreTitular], [TipoTecnologia],
           [DireccionInstalacion], [FechaOrden], [EstadoOrden]
    FROM [dbo].[OrdenesTrabajo]
    WHERE [CodigoTecnico] = @CodigoTecnico
      AND (@EstadoOrden IS NULL OR [EstadoOrden] = @EstadoOrden)
    ORDER BY [FechaOrden] DESC;
END
GO

-- ----------------------------------------------------------------------------
-- Todas las ordenes en un estado especifico.
-- ----------------------------------------------------------------------------
CREATE PROCEDURE [dbo].[usp_ListarOrdenesPorEstado]
    @EstadoOrden NVARCHAR(20)
AS
BEGIN
    SET NOCOUNT ON;

    SELECT O.[NumeroSolicitud], O.[NombreTitular], O.[TipoTecnologia],
           O.[FechaOrden], T.[CodigoCuadrilla],
           T.[Nombre] + ' ' + T.[Apellido] AS [NombreTecnico]
    FROM [dbo].[OrdenesTrabajo] O
    INNER JOIN [dbo].[Tecnicos] T ON T.[CodigoTecnico] = O.[CodigoTecnico]
    WHERE O.[EstadoOrden] = @EstadoOrden
    ORDER BY O.[FechaOrden] DESC;
END
GO

-- ----------------------------------------------------------------------------
-- Pendientes y En Proceso del dia agrupadas por tecnico. Dashboard diario.
-- ----------------------------------------------------------------------------
CREATE PROCEDURE [dbo].[usp_ListarOrdenesPendientesDelDia]
AS
BEGIN
    SET NOCOUNT ON;

    SELECT T.[CodigoCuadrilla],
           T.[Nombre] + ' ' + T.[Apellido] AS [NombreTecnico],
           O.[NumeroSolicitud], O.[NombreTitular], O.[DireccionInstalacion],
           O.[TipoTecnologia], O.[EstadoOrden]
    FROM [dbo].[OrdenesTrabajo] O
    INNER JOIN [dbo].[Tecnicos] T ON T.[CodigoTecnico] = O.[CodigoTecnico]
    WHERE O.[EstadoOrden] IN ('Pendiente','En Proceso')
      AND O.[FechaOrden] = CAST(GETDATE() AS DATE)
    ORDER BY T.[CodigoCuadrilla], O.[NumeroSolicitud];
END
GO


/* ============================================================================
   SECCION 8: SP DE FACTURAS Y ASIGNACIONES
   ============================================================================
   Modulo mas critico transaccionalmente. Todos los SP con operaciones
   multi-tabla estan marcados con [COMPUESTO] y usan BEGIN TRAN.
   ============================================================================ */

-- ----------------------------------------------------------------------------
-- EL SP MAS IMPORTANTE. Crea factura + asigna equipos y materiales. [COMPUESTO]
-- Recibe TVPs, actualiza estados, descuenta stock. Todo atomico.
-- ----------------------------------------------------------------------------
CREATE PROCEDURE [dbo].[usp_CrearFacturaCompleta]
    @CodigoTecnico    INT,
    @IDUsuarioBodega  INT,
    @Observaciones    NVARCHAR(200) = NULL,
    @Equipos          [dbo].[TVP_EquiposSeriados] READONLY,
    @Materiales       [dbo].[TVP_Materiales] READONLY,
    @UsuarioLogin     VARCHAR(20)
AS
BEGIN
    SET NOCOUNT ON;

    BEGIN TRY
        BEGIN TRANSACTION;

        -- Validar tecnico activo
        IF NOT EXISTS (
            SELECT 1 FROM [dbo].[Tecnicos]
            WHERE [CodigoTecnico] = @CodigoTecnico AND [EstadoLaboral] = 'Activo'
        )
        BEGIN
            THROW 57000, 'Tecnico no encontrado o no esta activo.', 1;
            RETURN;
        END

        -- Validar usuario de bodega activo
        IF NOT EXISTS (
            SELECT 1 FROM [dbo].[Usuarios]
            WHERE [IDUsuario] = @IDUsuarioBodega AND [EstadoUsuario] = 'Activo'
        )
        BEGIN
            THROW 57001, 'Usuario de bodega no encontrado o no esta activo.', 1;
            RETURN;
        END

        -- Validar que todos los equipos existan y esten en Bodega
        IF EXISTS (
            SELECT 1 FROM @Equipos E
            LEFT JOIN [dbo].[EquiposSeriados] ES ON ES.[NumeroSerie] = E.[NumeroSerie]
            WHERE ES.[NumeroSerie] IS NULL OR ES.[EstadoEquipo] <> 'Bodega'
        )
        BEGIN
            THROW 57002, 'Al menos un equipo no existe o no esta disponible en bodega.', 1;
            RETURN;
        END

        -- Validar que todos los materiales existan y tengan stock suficiente
        IF EXISTS (
            SELECT 1 FROM @Materiales M
            LEFT JOIN [dbo].[MaterialesMiscelaneos] MM ON MM.[CodigoMaterial] = M.[CodigoMaterial]
            WHERE MM.[CodigoMaterial] IS NULL OR MM.[StockBodega] < M.[Cantidad]
        )
        BEGIN
            THROW 57003, 'Al menos un material no existe o no tiene stock suficiente.', 1;
            RETURN;
        END

        -- 1) Crear cabecera de factura
        INSERT INTO [dbo].[Facturas] ([CodigoTecnico], [IDUsuarioBodega], [Observaciones])
        VALUES (@CodigoTecnico, @IDUsuarioBodega, @Observaciones);

        DECLARE @NumeroFactura INT = SCOPE_IDENTITY();

        -- 2) Insertar lineas de equipos
        INSERT INTO [dbo].[AsignacionEquipos] ([NumeroFactura], [NumeroSerie])
        SELECT @NumeroFactura, [NumeroSerie] FROM @Equipos;

        -- 3) Insertar lineas de materiales
        INSERT INTO [dbo].[AsignacionMateriales] ([NumeroFactura], [CodigoMaterial], [Cantidad])
        SELECT @NumeroFactura, [CodigoMaterial], [Cantidad] FROM @Materiales;

        -- 4) Actualizar estado de equipos a 'Asignado'
        UPDATE ES
        SET [EstadoEquipo] = 'Asignado'
        FROM [dbo].[EquiposSeriados] ES
        INNER JOIN @Equipos E ON E.[NumeroSerie] = ES.[NumeroSerie];

        -- 5) Descontar stock de materiales
        UPDATE MM
        SET [StockBodega] = MM.[StockBodega] - M.[Cantidad]
        FROM [dbo].[MaterialesMiscelaneos] MM
        INNER JOIN @Materiales M ON M.[CodigoMaterial] = MM.[CodigoMaterial];

        -- Bitacora
        EXEC [dbo].[usp_RegistrarBitacora]
            @TablaAfectada = N'Facturas',
            @TipoOperacion = 'I',
            @RegistroID    = @NumeroFactura,
            @UsuarioLogin  = @UsuarioLogin;

        COMMIT TRANSACTION;

        SELECT @NumeroFactura AS [NumeroFactura];
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        THROW;
    END CATCH
END
GO

-- ----------------------------------------------------------------------------
-- Consulta factura completa: encabezado + equipos + materiales (3 result sets).
-- ----------------------------------------------------------------------------
CREATE PROCEDURE [dbo].[usp_ConsultarFacturaCompleta]
    @NumeroFactura INT
AS
BEGIN
    SET NOCOUNT ON;

    -- Result set 1: encabezado
    SELECT
        F.[NumeroFactura], F.[FechaFactura], F.[Observaciones],
        T.[CodigoCuadrilla],
        T.[Nombre] + ' ' + T.[Apellido] AS [NombreTecnico],
        U.[UsuarioLogin] AS [LoginBodeguero],
        U.[Nombres] + ' ' + U.[Apellidos] AS [NombreBodeguero]
    FROM [dbo].[Facturas] F
    INNER JOIN [dbo].[Tecnicos] T ON T.[CodigoTecnico] = F.[CodigoTecnico]
    INNER JOIN [dbo].[Usuarios] U ON U.[IDUsuario]     = F.[IDUsuarioBodega]
    WHERE F.[NumeroFactura] = @NumeroFactura;

    -- Result set 2: equipos asignados
    SELECT AE.[NumeroSerie], ES.[Modelo], ES.[TipoAparato], AE.[EstadoAsignacion]
    FROM [dbo].[AsignacionEquipos] AE
    INNER JOIN [dbo].[EquiposSeriados] ES ON ES.[NumeroSerie] = AE.[NumeroSerie]
    WHERE AE.[NumeroFactura] = @NumeroFactura;

    -- Result set 3: materiales asignados
    SELECT AM.[CodigoMaterial], MM.[NombreMaterial], MM.[UnidadMedida], AM.[Cantidad]
    FROM [dbo].[AsignacionMateriales] AM
    INNER JOIN [dbo].[MaterialesMiscelaneos] MM ON MM.[CodigoMaterial] = AM.[CodigoMaterial]
    WHERE AM.[NumeroFactura] = @NumeroFactura;
END
GO

-- ----------------------------------------------------------------------------
-- Facturas de un tecnico con filtro opcional por fechas.
-- ----------------------------------------------------------------------------
CREATE PROCEDURE [dbo].[usp_ListarFacturasPorTecnico]
    @CodigoTecnico INT,
    @FechaInicio   DATE = NULL,
    @FechaFin      DATE = NULL
AS
BEGIN
    SET NOCOUNT ON;

    SELECT F.[NumeroFactura], F.[FechaFactura], F.[Observaciones],
           U.[UsuarioLogin] AS [LoginBodeguero]
    FROM [dbo].[Facturas] F
    INNER JOIN [dbo].[Usuarios] U ON U.[IDUsuario] = F.[IDUsuarioBodega]
    WHERE F.[CodigoTecnico] = @CodigoTecnico
      AND (@FechaInicio IS NULL OR F.[FechaFactura] >= @FechaInicio)
      AND (@FechaFin    IS NULL OR F.[FechaFactura] <= @FechaFin)
    ORDER BY F.[FechaFactura] DESC;
END
GO

-- ----------------------------------------------------------------------------
-- Facturas emitidas por un bodeguero. Auditoria de quien despacho que.
-- ----------------------------------------------------------------------------
CREATE PROCEDURE [dbo].[usp_ListarFacturasPorBodeguero]
    @IDUsuarioBodega INT,
    @FechaInicio     DATE = NULL,
    @FechaFin        DATE = NULL
AS
BEGIN
    SET NOCOUNT ON;

    SELECT F.[NumeroFactura], F.[FechaFactura], F.[Observaciones],
           T.[CodigoCuadrilla],
           T.[Nombre] + ' ' + T.[Apellido] AS [NombreTecnico]
    FROM [dbo].[Facturas] F
    INNER JOIN [dbo].[Tecnicos] T ON T.[CodigoTecnico] = F.[CodigoTecnico]
    WHERE F.[IDUsuarioBodega] = @IDUsuarioBodega
      AND (@FechaInicio IS NULL OR F.[FechaFactura] >= @FechaInicio)
      AND (@FechaFin    IS NULL OR F.[FechaFactura] <= @FechaFin)
    ORDER BY F.[FechaFactura] DESC;
END
GO

-- ----------------------------------------------------------------------------
-- Anula factura: marca asignaciones devueltas, regresa equipos y stock. [COMPUESTO]
-- Motivo obligatorio. Solo ejecutar con permiso Factura.Anular.
-- ----------------------------------------------------------------------------
CREATE PROCEDURE [dbo].[usp_AnularFactura]
    @NumeroFactura INT,
    @Motivo        NVARCHAR(200),
    @UsuarioLogin  VARCHAR(20)
AS
BEGIN
    SET NOCOUNT ON;

    BEGIN TRY
        BEGIN TRANSACTION;

        IF NOT EXISTS (SELECT 1 FROM [dbo].[Facturas] WHERE [NumeroFactura] = @NumeroFactura)
        BEGIN
            THROW 57010, 'Factura no encontrada.', 1;
            RETURN;
        END

        -- 1) Marcar asignaciones de equipos como Devuelta
        UPDATE [dbo].[AsignacionEquipos]
        SET [EstadoAsignacion] = 'Devuelta'
        WHERE [NumeroFactura] = @NumeroFactura;

        -- 2) Regresar equipos a estado Bodega
        UPDATE ES
        SET [EstadoEquipo] = 'Bodega'
        FROM [dbo].[EquiposSeriados] ES
        INNER JOIN [dbo].[AsignacionEquipos] AE ON AE.[NumeroSerie] = ES.[NumeroSerie]
        WHERE AE.[NumeroFactura] = @NumeroFactura;

        -- 3) Regresar stock de materiales
        UPDATE MM
        SET [StockBodega] = MM.[StockBodega] + AM.[Cantidad]
        FROM [dbo].[MaterialesMiscelaneos] MM
        INNER JOIN [dbo].[AsignacionMateriales] AM ON AM.[CodigoMaterial] = MM.[CodigoMaterial]
        WHERE AM.[NumeroFactura] = @NumeroFactura;

        -- 4) Anotar motivo en observaciones
        UPDATE [dbo].[Facturas]
        SET [Observaciones] = ISNULL([Observaciones] + ' | ', '') + 'ANULADA: ' + @Motivo
        WHERE [NumeroFactura] = @NumeroFactura;

        EXEC [dbo].[usp_RegistrarBitacora]
            @TablaAfectada   = N'Facturas',
            @TipoOperacion   = 'U',
            @RegistroID      = @NumeroFactura,
            @CampoModificado = N'Anulacion',
            @ValorNuevo      = @Motivo,
            @UsuarioLogin    = @UsuarioLogin;

        COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        THROW;
    END CATCH
END
GO

-- ----------------------------------------------------------------------------
-- Marca una asignacion de equipo individual como devuelta.
-- ----------------------------------------------------------------------------
CREATE PROCEDURE [dbo].[usp_MarcarAsignacionDevuelta]
    @IDRegistro    INT,
    @UsuarioLogin  VARCHAR(20)
AS
BEGIN
    SET NOCOUNT ON;

    BEGIN TRY
        UPDATE [dbo].[AsignacionEquipos]
        SET [EstadoAsignacion] = 'Devuelta'
        WHERE [IDRegistro] = @IDRegistro;

        IF @@ROWCOUNT = 0
        BEGIN
            THROW 57020, 'Asignacion no encontrada.', 1;
            RETURN;
        END

        EXEC [dbo].[usp_RegistrarBitacora]
            @TablaAfectada   = N'AsignacionEquipos',
            @TipoOperacion   = 'U',
            @RegistroID      = @IDRegistro,
            @CampoModificado = N'EstadoAsignacion',
            @ValorNuevo      = N'Devuelta',
            @UsuarioLogin    = @UsuarioLogin;
    END TRY
    BEGIN CATCH
        THROW;
    END CATCH
END
GO


/* ============================================================================
   SECCION 9: SP DE LIQUIDACION / DETALLE DE INSTALACION
   ============================================================================ */

-- ----------------------------------------------------------------------------
-- Tecnico cierra una orden. Transaccional: inserta detalles + cambia estados. [COMPUESTO]
-- Valida que cada equipo instalado este asignado al tecnico actualmente.
-- ----------------------------------------------------------------------------
CREATE PROCEDURE [dbo].[usp_RegistrarLiquidacionOrden]
    @NumeroSolicitud    VARCHAR(20),
    @CodigoTecnico      INT,
    @FechaInstalacion   DATE,
    @EquiposInstalados  [dbo].[TVP_EquiposSeriados] READONLY,
    @MaterialesUsados   [dbo].[TVP_Materiales] READONLY,
    @UsuarioLogin       VARCHAR(20)
AS
BEGIN
    SET NOCOUNT ON;

    BEGIN TRY
        BEGIN TRANSACTION;

        -- Validar que la orden exista y este En Proceso o Pendiente
        DECLARE @EstadoOrden NVARCHAR(20);
        SELECT @EstadoOrden = [EstadoOrden]
        FROM [dbo].[OrdenesTrabajo]
        WHERE [NumeroSolicitud] = @NumeroSolicitud;

        IF @EstadoOrden IS NULL
        BEGIN
            THROW 58000, 'Orden no encontrada.', 1;
            RETURN;
        END

        IF @EstadoOrden NOT IN ('Pendiente','En Proceso')
        BEGIN
            THROW 58001, 'La orden no esta en estado valido para liquidacion.', 1;
            RETURN;
        END

        -- Validar que cada equipo instalado este actualmente asignado al tecnico
        IF EXISTS (
            SELECT 1 FROM @EquiposInstalados EI
            WHERE NOT EXISTS (
                SELECT 1 FROM [dbo].[AsignacionEquipos] AE
                INNER JOIN [dbo].[Facturas] F ON F.[NumeroFactura] = AE.[NumeroFactura]
                WHERE AE.[NumeroSerie]      = EI.[NumeroSerie]
                  AND AE.[EstadoAsignacion] = 'Activa'
                  AND F.[CodigoTecnico]     = @CodigoTecnico
            )
        )
        BEGIN
            THROW 58002, 'Al menos un equipo no esta asignado actualmente a este tecnico.', 1;
            RETURN;
        END

        -- 1) Insertar detalles de equipos instalados
        INSERT INTO [dbo].[DetalleInstalacion] (
            [NumeroSolicitud], [CodigoTecnico], [FechaInstalacion], [NumeroSerie]
        )
        SELECT @NumeroSolicitud, @CodigoTecnico, @FechaInstalacion, [NumeroSerie]
        FROM @EquiposInstalados;

        -- 2) Insertar detalles de materiales usados
        INSERT INTO [dbo].[DetalleInstalacion] (
            [NumeroSolicitud], [CodigoTecnico], [FechaInstalacion], [CodigoMaterial], [CantidadUtilizada]
        )
        SELECT @NumeroSolicitud, @CodigoTecnico, @FechaInstalacion, [CodigoMaterial], [Cantidad]
        FROM @MaterialesUsados;

        -- 3) Cambiar estado de equipos instalados a 'Instalado'
        UPDATE ES
        SET [EstadoEquipo] = 'Instalado'
        FROM [dbo].[EquiposSeriados] ES
        INNER JOIN @EquiposInstalados EI ON EI.[NumeroSerie] = ES.[NumeroSerie];

        -- 4) Cambiar estado de la orden a Completada
        UPDATE [dbo].[OrdenesTrabajo]
        SET [EstadoOrden] = 'Completada'
        WHERE [NumeroSolicitud] = @NumeroSolicitud;

        EXEC [dbo].[usp_RegistrarBitacora]
            @TablaAfectada = N'OrdenesTrabajo',
            @TipoOperacion = 'U',
            @RegistroID    = @NumeroSolicitud,
            @CampoModificado = N'EstadoOrden',
            @ValorAnterior = @EstadoOrden,
            @ValorNuevo    = N'Completada',
            @UsuarioLogin  = @UsuarioLogin;

        COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        THROW;
    END CATCH
END
GO

-- ----------------------------------------------------------------------------
-- Bodega revisa y marca la liquidacion como validada. Cierra el ciclo.
-- ----------------------------------------------------------------------------
CREATE PROCEDURE [dbo].[usp_ValidarLiquidacionPorBodega]
    @IDDetalle     INT,
    @UsuarioLogin  VARCHAR(20)
AS
BEGIN
    SET NOCOUNT ON;

    BEGIN TRY
        UPDATE [dbo].[DetalleInstalacion]
        SET [ValidadoBodega] = 'SI'
        WHERE [IDDetalle] = @IDDetalle;

        IF @@ROWCOUNT = 0
        BEGIN
            THROW 58010, 'Detalle de instalacion no encontrado.', 1;
            RETURN;
        END

        EXEC [dbo].[usp_RegistrarBitacora]
            @TablaAfectada   = N'DetalleInstalacion',
            @TipoOperacion   = 'U',
            @RegistroID      = @IDDetalle,
            @CampoModificado = N'ValidadoBodega',
            @ValorAnterior   = N'NO',
            @ValorNuevo      = N'SI',
            @UsuarioLogin    = @UsuarioLogin;
    END TRY
    BEGIN CATCH
        THROW;
    END CATCH
END
GO

-- ----------------------------------------------------------------------------
-- Devuelve que se instalo y que se consumio en una orden.
-- ----------------------------------------------------------------------------
CREATE PROCEDURE [dbo].[usp_ConsultarDetalleOrden]
    @NumeroSolicitud VARCHAR(20)
AS
BEGIN
    SET NOCOUNT ON;

    SELECT
        DI.[IDDetalle], DI.[FechaInstalacion], DI.[ValidadoBodega],
        DI.[NumeroSerie], ES.[Modelo] AS [ModeloEquipo],
        DI.[CodigoMaterial], MM.[NombreMaterial], DI.[CantidadUtilizada],
        MM.[UnidadMedida]
    FROM [dbo].[DetalleInstalacion] DI
    LEFT JOIN [dbo].[EquiposSeriados] ES       ON ES.[NumeroSerie]    = DI.[NumeroSerie]
    LEFT JOIN [dbo].[MaterialesMiscelaneos] MM ON MM.[CodigoMaterial] = DI.[CodigoMaterial]
    WHERE DI.[NumeroSolicitud] = @NumeroSolicitud
    ORDER BY DI.[IDDetalle];
END
GO

-- ----------------------------------------------------------------------------
-- Detalles de instalacion que no han sido validados por bodega aun.
-- ----------------------------------------------------------------------------
CREATE PROCEDURE [dbo].[usp_ListarLiquidacionesPendientesValidacion]
AS
BEGIN
    SET NOCOUNT ON;

    SELECT
        DI.[IDDetalle], DI.[NumeroSolicitud], DI.[FechaInstalacion],
        T.[CodigoCuadrilla],
        T.[Nombre] + ' ' + T.[Apellido] AS [NombreTecnico],
        DI.[NumeroSerie], DI.[CodigoMaterial], DI.[CantidadUtilizada]
    FROM [dbo].[DetalleInstalacion] DI
    INNER JOIN [dbo].[Tecnicos] T ON T.[CodigoTecnico] = DI.[CodigoTecnico]
    WHERE DI.[ValidadoBodega] = 'NO'
    ORDER BY DI.[FechaInstalacion] ASC;
END
GO

-- ----------------------------------------------------------------------------
-- Liquidaciones registradas por un tecnico en un rango de fechas.
-- ----------------------------------------------------------------------------
CREATE PROCEDURE [dbo].[usp_ListarLiquidacionesPorTecnico]
    @CodigoTecnico INT,
    @FechaInicio   DATE,
    @FechaFin      DATE
AS
BEGIN
    SET NOCOUNT ON;

    SELECT
        DI.[IDDetalle], DI.[NumeroSolicitud], DI.[FechaInstalacion],
        DI.[NumeroSerie], DI.[CodigoMaterial], DI.[CantidadUtilizada],
        DI.[ValidadoBodega]
    FROM [dbo].[DetalleInstalacion] DI
    WHERE DI.[CodigoTecnico] = @CodigoTecnico
      AND DI.[FechaInstalacion] BETWEEN @FechaInicio AND @FechaFin
    ORDER BY DI.[FechaInstalacion] DESC;
END
GO


/* ============================================================================
   SECCION 10: SP DE AVERIAS Y GARANTIAS
   ============================================================================ */

-- ----------------------------------------------------------------------------
-- Registra visita de soporte. El CHECK de BD valida coherencia tipo-inventario.
-- Si hay cambio de equipo: nuevo -> Instalado, retirado -> Danado/Garantia. [COMPUESTO]
-- ----------------------------------------------------------------------------
CREATE PROCEDURE [dbo].[usp_RegistrarAveria]
    @NumeroTicket           VARCHAR(20),
    @NumeroSolicitud        VARCHAR(20),
    @CodigoTecnico          INT,
    @FechaVisita            DATE,
    @ProblemaReportado      NVARCHAR(200),
    @ComentarioTecnico      NVARCHAR(200) = NULL,
    @TipoVisita             NVARCHAR(20),
    @NumeroSerieInstalado   VARCHAR(50) = NULL,
    @NumeroSerieRetirado    VARCHAR(50) = NULL,
    @EstadoEquipoRetirado   NVARCHAR(15) = NULL,   -- 'Dañado' o 'Garantía'
    @CodigoMaterial         VARCHAR(15) = NULL,
    @CantidadMaterial       DECIMAL(10,2) = NULL,
    @UsuarioLogin           VARCHAR(20)
AS
BEGIN
    SET NOCOUNT ON;

    BEGIN TRY
        BEGIN TRANSACTION;

        -- Insertar averia (el CHECK compuesto valida coherencia)
        INSERT INTO [dbo].[AveriaGarantia] (
            [NumeroTicket], [NumeroSolicitud], [CodigoTecnico], [FechaVisita],
            [ProblemaReportado], [ComentarioTecnico], [TipoVisita],
            [NumeroSerieInstalado], [NumeroSerieRetirado],
            [CodigoMaterial], [CantidadMaterial]
        )
        VALUES (
            @NumeroTicket, @NumeroSolicitud, @CodigoTecnico, @FechaVisita,
            @ProblemaReportado, @ComentarioTecnico, @TipoVisita,
            @NumeroSerieInstalado, @NumeroSerieRetirado,
            @CodigoMaterial, @CantidadMaterial
        );

        -- Cambio de equipo: nuevo a Instalado
        IF @NumeroSerieInstalado IS NOT NULL
        BEGIN
            UPDATE [dbo].[EquiposSeriados]
            SET [EstadoEquipo] = 'Instalado'
            WHERE [NumeroSerie] = @NumeroSerieInstalado;
        END

        -- Cambio de equipo: retirado a Dañado o Garantía
        IF @NumeroSerieRetirado IS NOT NULL
        BEGIN
            IF @EstadoEquipoRetirado NOT IN ('Dañado','Garantía') OR @EstadoEquipoRetirado IS NULL
            BEGIN
                THROW 59000, 'EstadoEquipoRetirado debe ser Danado o Garantia cuando hay retirado.', 1;
                RETURN;
            END

            UPDATE [dbo].[EquiposSeriados]
            SET [EstadoEquipo] = @EstadoEquipoRetirado
            WHERE [NumeroSerie] = @NumeroSerieRetirado;
        END

        -- Uso de material: descontar stock
        IF @CodigoMaterial IS NOT NULL AND @CantidadMaterial IS NOT NULL
        BEGIN
            UPDATE [dbo].[MaterialesMiscelaneos]
            SET [StockBodega] = [StockBodega] - @CantidadMaterial
            WHERE [CodigoMaterial] = @CodigoMaterial;
        END

        EXEC [dbo].[usp_RegistrarBitacora]
            @TablaAfectada = N'AveriaGarantia',
            @TipoOperacion = 'I',
            @RegistroID    = @NumeroTicket,
            @ValorNuevo    = @TipoVisita,
            @UsuarioLogin  = @UsuarioLogin;

        COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        THROW;
    END CATCH
END
GO

-- ----------------------------------------------------------------------------
-- Averias asociadas a una orden original (historial de problemas).
-- ----------------------------------------------------------------------------
CREATE PROCEDURE [dbo].[usp_ConsultarAveriasPorOrden]
    @NumeroSolicitud VARCHAR(20)
AS
BEGIN
    SET NOCOUNT ON;

    SELECT
        AG.[NumeroTicket], AG.[FechaVisita], AG.[TipoVisita],
        AG.[ProblemaReportado], AG.[ComentarioTecnico],
        AG.[NumeroSerieInstalado], AG.[NumeroSerieRetirado],
        AG.[CodigoMaterial], AG.[CantidadMaterial],
        T.[CodigoCuadrilla]
    FROM [dbo].[AveriaGarantia] AG
    INNER JOIN [dbo].[Tecnicos] T ON T.[CodigoTecnico] = AG.[CodigoTecnico]
    WHERE AG.[NumeroSolicitud] = @NumeroSolicitud
    ORDER BY AG.[FechaVisita] DESC;
END
GO

-- ----------------------------------------------------------------------------
-- Averias atendidas por un tecnico en un rango de fechas.
-- ----------------------------------------------------------------------------
CREATE PROCEDURE [dbo].[usp_ListarAveriasPorTecnico]
    @CodigoTecnico INT,
    @FechaInicio   DATE,
    @FechaFin      DATE
AS
BEGIN
    SET NOCOUNT ON;

    SELECT
        AG.[NumeroTicket], AG.[NumeroSolicitud], AG.[FechaVisita],
        AG.[TipoVisita], AG.[ProblemaReportado]
    FROM [dbo].[AveriaGarantia] AG
    WHERE AG.[CodigoTecnico] = @CodigoTecnico
      AND AG.[FechaVisita] BETWEEN @FechaInicio AND @FechaFin
    ORDER BY AG.[FechaVisita] DESC;
END
GO

-- ----------------------------------------------------------------------------
-- Ordenes completadas hace menos de 3 meses con averias reportadas.
-- ----------------------------------------------------------------------------
CREATE PROCEDURE [dbo].[usp_ListarAveriasDentroDeGarantia]
AS
BEGIN
    SET NOCOUNT ON;

    SELECT
        O.[NumeroSolicitud], O.[NombreTitular], O.[FechaOrden],
        AG.[NumeroTicket], AG.[FechaVisita], AG.[TipoVisita]
    FROM [dbo].[OrdenesTrabajo] O
    INNER JOIN [dbo].[AveriaGarantia] AG ON AG.[NumeroSolicitud] = O.[NumeroSolicitud]
    WHERE O.[EstadoOrden] = 'Completada'
      AND O.[FechaOrden] >= DATEADD(MONTH, -3, CAST(GETDATE() AS DATE))
    ORDER BY O.[FechaOrden] DESC, AG.[FechaVisita] DESC;
END
GO


/* ============================================================================
   SECCION 11: SP DE DEVOLUCIONES DE INVENTARIO
   ============================================================================ */

-- ----------------------------------------------------------------------------
-- Tecnico devuelve equipo/material. Actualiza stock y estados. [COMPUESTO]
-- Bueno -> Bodega, Danado/Fabrica -> Garantia, Danado/Uso -> Danado.
-- ----------------------------------------------------------------------------
CREATE PROCEDURE [dbo].[usp_RegistrarDevolucion]
    @CodigoTecnico      INT,
    @IDUsuarioBodega    INT,
    @NumeroSerie        VARCHAR(50) = NULL,
    @CodigoMaterial     VARCHAR(15) = NULL,
    @CantidadDevuelta   DECIMAL(10,2) = NULL,
    @CondicionEntrega   NVARCHAR(20),
    @UsuarioLogin       VARCHAR(20)
AS
BEGIN
    SET NOCOUNT ON;

    BEGIN TRY
        BEGIN TRANSACTION;

        -- Insertar devolucion
        INSERT INTO [dbo].[DevolucionInventario] (
            [CodigoTecnico], [IDUsuarioBodega], [NumeroSerie],
            [CodigoMaterial], [CantidadDevuelta], [CondicionEntrega]
        )
        VALUES (
            @CodigoTecnico, @IDUsuarioBodega, @NumeroSerie,
            @CodigoMaterial, @CantidadDevuelta, @CondicionEntrega
        );

        DECLARE @IDDevolucion INT = SCOPE_IDENTITY();

        -- Si es equipo seriado
        IF @NumeroSerie IS NOT NULL
        BEGIN
            -- Marcar asignacion activa como devuelta
            UPDATE AE
            SET [EstadoAsignacion] = 'Devuelta'
            FROM [dbo].[AsignacionEquipos] AE
            INNER JOIN [dbo].[Facturas] F ON F.[NumeroFactura] = AE.[NumeroFactura]
            WHERE AE.[NumeroSerie] = @NumeroSerie
              AND AE.[EstadoAsignacion] = 'Activa'
              AND F.[CodigoTecnico] = @CodigoTecnico;

            -- Cambiar estado del equipo segun condicion
            DECLARE @NuevoEstadoEquipo NVARCHAR(15);
            SET @NuevoEstadoEquipo =
                CASE @CondicionEntrega
                    WHEN 'Bueno/Sobrante'     THEN 'Bodega'
                    WHEN 'Dañado de fábrica'  THEN 'Garantía'
                    WHEN 'Dañado por uso'     THEN 'Dañado'
                END;

            UPDATE [dbo].[EquiposSeriados]
            SET [EstadoEquipo] = @NuevoEstadoEquipo
            WHERE [NumeroSerie] = @NumeroSerie;
        END

        -- Si es material y esta en condicion Bueno/Sobrante, devolver al stock
        IF @CodigoMaterial IS NOT NULL
           AND @CondicionEntrega = 'Bueno/Sobrante'
           AND @CantidadDevuelta IS NOT NULL
        BEGIN
            UPDATE [dbo].[MaterialesMiscelaneos]
            SET [StockBodega] = [StockBodega] + @CantidadDevuelta
            WHERE [CodigoMaterial] = @CodigoMaterial;
        END

        EXEC [dbo].[usp_RegistrarBitacora]
            @TablaAfectada = N'DevolucionInventario',
            @TipoOperacion = 'I',
            @RegistroID    = @IDDevolucion,
            @ValorNuevo    = @CondicionEntrega,
            @UsuarioLogin  = @UsuarioLogin;

        COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        THROW;
    END CATCH
END
GO

-- ----------------------------------------------------------------------------
-- Historial de devoluciones de un tecnico en un rango de fechas.
-- ----------------------------------------------------------------------------
CREATE PROCEDURE [dbo].[usp_ConsultarDevolucionesPorTecnico]
    @CodigoTecnico INT,
    @FechaInicio   DATE = NULL,
    @FechaFin      DATE = NULL
AS
BEGIN
    SET NOCOUNT ON;

    SELECT
        DI.[IDDevolucion], DI.[FechaDevolucion],
        DI.[NumeroSerie], ES.[Modelo],
        DI.[CodigoMaterial], MM.[NombreMaterial], DI.[CantidadDevuelta],
        DI.[CondicionEntrega],
        U.[UsuarioLogin] AS [LoginBodeguero]
    FROM [dbo].[DevolucionInventario] DI
    LEFT JOIN [dbo].[EquiposSeriados] ES       ON ES.[NumeroSerie]    = DI.[NumeroSerie]
    LEFT JOIN [dbo].[MaterialesMiscelaneos] MM ON MM.[CodigoMaterial] = DI.[CodigoMaterial]
    INNER JOIN [dbo].[Usuarios] U              ON U.[IDUsuario]       = DI.[IDUsuarioBodega]
    WHERE DI.[CodigoTecnico] = @CodigoTecnico
      AND (@FechaInicio IS NULL OR DI.[FechaDevolucion] >= @FechaInicio)
      AND (@FechaFin    IS NULL OR DI.[FechaDevolucion] <= @FechaFin)
    ORDER BY DI.[FechaDevolucion] DESC;
END
GO

-- ----------------------------------------------------------------------------
-- Devoluciones recibidas por un bodeguero. Auditoria de recepcion.
-- ----------------------------------------------------------------------------
CREATE PROCEDURE [dbo].[usp_ListarDevolucionesPorBodeguero]
    @IDUsuarioBodega INT,
    @FechaInicio     DATE = NULL,
    @FechaFin        DATE = NULL
AS
BEGIN
    SET NOCOUNT ON;

    SELECT
        DI.[IDDevolucion], DI.[FechaDevolucion],
        T.[CodigoCuadrilla],
        T.[Nombre] + ' ' + T.[Apellido] AS [NombreTecnico],
        DI.[NumeroSerie], DI.[CodigoMaterial], DI.[CantidadDevuelta],
        DI.[CondicionEntrega]
    FROM [dbo].[DevolucionInventario] DI
    INNER JOIN [dbo].[Tecnicos] T ON T.[CodigoTecnico] = DI.[CodigoTecnico]
    WHERE DI.[IDUsuarioBodega] = @IDUsuarioBodega
      AND (@FechaInicio IS NULL OR DI.[FechaDevolucion] >= @FechaInicio)
      AND (@FechaFin    IS NULL OR DI.[FechaDevolucion] <= @FechaFin)
    ORDER BY DI.[FechaDevolucion] DESC;
END
GO


/* ============================================================================
   SECCION 12: SP DE REPORTES Y CONSULTAS GERENCIALES
   ============================================================================ */

-- ----------------------------------------------------------------------------
-- Inventario disponible en bodega agrupado por tipo de aparato.
-- ----------------------------------------------------------------------------
CREATE PROCEDURE [dbo].[usp_ReporteInventarioBodega]
AS
BEGIN
    SET NOCOUNT ON;

    SELECT [TipoAparato], COUNT(*) AS [Cantidad]
    FROM [dbo].[EquiposSeriados]
    WHERE [EstadoEquipo] = 'Bodega'
    GROUP BY [TipoAparato]
    ORDER BY [TipoAparato];

    -- Segundo result set: materiales con stock
    SELECT [CodigoMaterial], [NombreMaterial], [UnidadMedida], [StockBodega]
    FROM [dbo].[MaterialesMiscelaneos]
    WHERE [StockBodega] > 0
    ORDER BY [NombreMaterial];
END
GO

-- ----------------------------------------------------------------------------
-- Equipos asignados actualmente y a que tecnico estan.
-- ----------------------------------------------------------------------------
CREATE PROCEDURE [dbo].[usp_ReporteInventarioEnPoderTecnicos]
AS
BEGIN
    SET NOCOUNT ON;

    SELECT
        T.[CodigoCuadrilla],
        T.[Nombre] + ' ' + T.[Apellido] AS [NombreTecnico],
        ES.[TipoAparato], ES.[NumeroSerie], ES.[Modelo],
        F.[NumeroFactura], F.[FechaFactura]
    FROM [dbo].[AsignacionEquipos] AE
    INNER JOIN [dbo].[Facturas] F         ON F.[NumeroFactura] = AE.[NumeroFactura]
    INNER JOIN [dbo].[Tecnicos] T         ON T.[CodigoTecnico] = F.[CodigoTecnico]
    INNER JOIN [dbo].[EquiposSeriados] ES ON ES.[NumeroSerie]  = AE.[NumeroSerie]
    WHERE AE.[EstadoAsignacion] = 'Activa'
    ORDER BY T.[CodigoCuadrilla], ES.[TipoAparato];
END
GO

-- ----------------------------------------------------------------------------
-- CLAVE PARA DEFENSA DEL TECNICO. Equipos asignados NO instalados NI devueltos.
-- ----------------------------------------------------------------------------
CREATE PROCEDURE [dbo].[usp_ReporteDiscrepanciasTecnico]
    @CodigoTecnico INT,
    @FechaInicio   DATE,
    @FechaFin      DATE
AS
BEGIN
    SET NOCOUNT ON;

    -- Equipos asignados al tecnico en el rango
    SELECT
        AE.[NumeroSerie], ES.[Modelo], ES.[TipoAparato],
        F.[NumeroFactura], F.[FechaFactura],
        ES.[EstadoEquipo],
        AE.[EstadoAsignacion]
    FROM [dbo].[AsignacionEquipos] AE
    INNER JOIN [dbo].[Facturas] F         ON F.[NumeroFactura] = AE.[NumeroFactura]
    INNER JOIN [dbo].[EquiposSeriados] ES ON ES.[NumeroSerie]  = AE.[NumeroSerie]
    WHERE F.[CodigoTecnico] = @CodigoTecnico
      AND F.[FechaFactura] BETWEEN @FechaInicio AND @FechaFin
      AND AE.[EstadoAsignacion] = 'Activa'
      -- No esta instalado aun
      AND NOT EXISTS (
          SELECT 1 FROM [dbo].[DetalleInstalacion] DI
          WHERE DI.[NumeroSerie] = AE.[NumeroSerie]
      )
      -- No fue devuelto
      AND NOT EXISTS (
          SELECT 1 FROM [dbo].[DevolucionInventario] DEV
          WHERE DEV.[NumeroSerie] = AE.[NumeroSerie]
            AND DEV.[CodigoTecnico] = F.[CodigoTecnico]
      )
    ORDER BY F.[FechaFactura];
END
GO

-- ----------------------------------------------------------------------------
-- Productividad: ordenes completadas por tecnico con suma de cobros.
-- ----------------------------------------------------------------------------
CREATE PROCEDURE [dbo].[usp_ReporteProductividadTecnico]
    @FechaInicio DATE,
    @FechaFin    DATE
AS
BEGIN
    SET NOCOUNT ON;

    SELECT
        T.[CodigoCuadrilla],
        T.[Nombre] + ' ' + T.[Apellido] AS [NombreTecnico],
        COUNT(O.[NumeroSolicitud]) AS [OrdenesCompletadas],
        SUM(O.[CobroTecnico])      AS [TotalCobrado]
    FROM [dbo].[Tecnicos] T
    LEFT JOIN [dbo].[OrdenesTrabajo] O
        ON O.[CodigoTecnico] = T.[CodigoTecnico]
       AND O.[EstadoOrden] = 'Completada'
       AND O.[FechaOrden] BETWEEN @FechaInicio AND @FechaFin
    WHERE T.[EstadoLaboral] = 'Activo'
    GROUP BY T.[CodigoCuadrilla], T.[Nombre], T.[Apellido]
    ORDER BY [OrdenesCompletadas] DESC;
END
GO

-- ----------------------------------------------------------------------------
-- Material mas consumido agrupado por tipo de tecnologia instalada.
-- ----------------------------------------------------------------------------
CREATE PROCEDURE [dbo].[usp_ReporteConsumoMateriales]
    @FechaInicio DATE,
    @FechaFin    DATE
AS
BEGIN
    SET NOCOUNT ON;

    SELECT
        O.[TipoTecnologia],
        MM.[NombreMaterial], MM.[UnidadMedida],
        SUM(DI.[CantidadUtilizada]) AS [TotalConsumido]
    FROM [dbo].[DetalleInstalacion] DI
    INNER JOIN [dbo].[OrdenesTrabajo] O        ON O.[NumeroSolicitud] = DI.[NumeroSolicitud]
    INNER JOIN [dbo].[MaterialesMiscelaneos] MM ON MM.[CodigoMaterial] = DI.[CodigoMaterial]
    WHERE DI.[CodigoMaterial] IS NOT NULL
      AND DI.[FechaInstalacion] BETWEEN @FechaInicio AND @FechaFin
    GROUP BY O.[TipoTecnologia], MM.[NombreMaterial], MM.[UnidadMedida]
    ORDER BY O.[TipoTecnologia], [TotalConsumido] DESC;
END
GO

-- ----------------------------------------------------------------------------
-- Ordenes completadas sin validacion de bodega. Alertas de seguimiento.
-- ----------------------------------------------------------------------------
CREATE PROCEDURE [dbo].[usp_ReporteLiquidacionesPendientes]
AS
BEGIN
    SET NOCOUNT ON;

    SELECT
        O.[NumeroSolicitud], O.[NombreTitular], O.[FechaOrden],
        T.[CodigoCuadrilla],
        COUNT(DI.[IDDetalle]) AS [TotalDetalles],
        SUM(CASE WHEN DI.[ValidadoBodega] = 'NO' THEN 1 ELSE 0 END) AS [PendientesValidacion]
    FROM [dbo].[OrdenesTrabajo] O
    INNER JOIN [dbo].[Tecnicos] T           ON T.[CodigoTecnico] = O.[CodigoTecnico]
    INNER JOIN [dbo].[DetalleInstalacion] DI ON DI.[NumeroSolicitud] = O.[NumeroSolicitud]
    WHERE O.[EstadoOrden] = 'Completada'
    GROUP BY O.[NumeroSolicitud], O.[NombreTitular], O.[FechaOrden], T.[CodigoCuadrilla]
    HAVING SUM(CASE WHEN DI.[ValidadoBodega] = 'NO' THEN 1 ELSE 0 END) > 0
    ORDER BY O.[FechaOrden];
END
GO

-- ----------------------------------------------------------------------------
-- Equipos en estado Danado con la fecha de cambio mas reciente.
-- ----------------------------------------------------------------------------
CREATE PROCEDURE [dbo].[usp_ReporteEquiposDanados]
AS
BEGIN
    SET NOCOUNT ON;

    SELECT
        ES.[NumeroSerie], ES.[Modelo], ES.[TipoAparato], ES.[EstadoEquipo],
        (
            SELECT MAX(BA.[FechaHora])
            FROM [dbo].[BitacoraAuditoria] BA
            WHERE BA.[TablaAfectada] = 'EquiposSeriados'
              AND BA.[RegistroID]    = ES.[NumeroSerie]
              AND BA.[CampoModificado] = 'EstadoEquipo'
        ) AS [FechaCambioEstado]
    FROM [dbo].[EquiposSeriados] ES
    WHERE ES.[EstadoEquipo] IN ('Dañado','Garantía')
    ORDER BY [FechaCambioEstado] DESC;
END
GO

-- ----------------------------------------------------------------------------
-- Trazabilidad de una factura: despacho + instalaciones + devoluciones.
-- ----------------------------------------------------------------------------
CREATE PROCEDURE [dbo].[usp_ReporteFlujoFactura]
    @NumeroFactura INT
AS
BEGIN
    SET NOCOUNT ON;

    -- Result set 1: cabecera de factura
    SELECT
        F.[NumeroFactura], F.[FechaFactura],
        T.[CodigoCuadrilla],
        T.[Nombre] + ' ' + T.[Apellido] AS [NombreTecnico]
    FROM [dbo].[Facturas] F
    INNER JOIN [dbo].[Tecnicos] T ON T.[CodigoTecnico] = F.[CodigoTecnico]
    WHERE F.[NumeroFactura] = @NumeroFactura;

    -- Result set 2: que se entrego (equipos)
    SELECT
        'Despachado' AS [Flujo],
        AE.[NumeroSerie], ES.[Modelo], AE.[EstadoAsignacion]
    FROM [dbo].[AsignacionEquipos] AE
    INNER JOIN [dbo].[EquiposSeriados] ES ON ES.[NumeroSerie] = AE.[NumeroSerie]
    WHERE AE.[NumeroFactura] = @NumeroFactura;

    -- Result set 3: que se instalo de los equipos de esta factura
    SELECT
        'Instalado' AS [Flujo],
        DI.[NumeroSerie], DI.[NumeroSolicitud], DI.[FechaInstalacion]
    FROM [dbo].[DetalleInstalacion] DI
    WHERE DI.[NumeroSerie] IN (
        SELECT [NumeroSerie] FROM [dbo].[AsignacionEquipos]
        WHERE [NumeroFactura] = @NumeroFactura
    );

    -- Result set 4: que se devolvio de esta factura
    SELECT
        'Devuelto' AS [Flujo],
        DEV.[NumeroSerie], DEV.[FechaDevolucion], DEV.[CondicionEntrega]
    FROM [dbo].[DevolucionInventario] DEV
    WHERE DEV.[NumeroSerie] IN (
        SELECT [NumeroSerie] FROM [dbo].[AsignacionEquipos]
        WHERE [NumeroFactura] = @NumeroFactura
    );
END
GO

-- ----------------------------------------------------------------------------
-- Historial completo de un equipo por numero de serie desde la bitacora.
-- ----------------------------------------------------------------------------
CREATE PROCEDURE [dbo].[usp_ReporteAuditoriaMovimientos]
    @NumeroSerie VARCHAR(50)
AS
BEGIN
    SET NOCOUNT ON;

    SELECT
        BA.[FechaHora], BA.[TipoOperacion], BA.[TablaAfectada],
        BA.[CampoModificado], BA.[ValorAnterior], BA.[ValorNuevo],
        BA.[UsuarioLogin]
    FROM [dbo].[BitacoraAuditoria] BA
    WHERE BA.[TablaAfectada] = 'EquiposSeriados'
      AND BA.[RegistroID]    = @NumeroSerie
    ORDER BY BA.[FechaHora] ASC;
END
GO


/* ============================================================================
   FIN DEL SCRIPT DE PROCEDIMIENTOS ALMACENADOS
   ============================================================================
   
   TOTAL DE OBJETOS CREADOS:
   
   Tipos TVP:                         2
     - TVP_EquiposSeriados
     - TVP_Materiales
   
   Registros iniciales de RBAC:
     - 5 Roles (Gerente, JefeBodega, Bodeguero, Tecnico, Auditor)
     - 41 Permisos
     - Asignaciones Rol-Permiso (variable por rol)
   
   Stored Procedures:                 71
     Seguridad y Bitacora:            13
     Tecnicos:                         7
     Usuarios:                         5
     Equipos Seriados:                 6
     Materiales Miscelaneos:           6
     Ordenes de Trabajo:               7
     Facturas y Asignaciones:          6
     Liquidacion / Instalacion:        5
     Averias y Garantias:              4
     Devoluciones:                     3
     Reportes Gerenciales:             9
   
   ============================================================================ */

/* ############################################################################
   ############################################################################
   PARTE 3 de 3: CAMBIOS V2.0
   (Origen: CAMBIOS_PROCONTEL_V2_0.sql  - typo @UsujarioLogin corregido)
   - Estado 'Escalada', FechaVencimiento, tabla TraspasoEquipos,
     SP nuevos y los 3 SP ajustados (drop + recreate).
   ############################################################################
   ############################################################################ */

USE [Procontel]
GO

-- Quitar el CHECK actual de estados
ALTER TABLE [dbo].[OrdenesTrabajo]
    DROP CONSTRAINT [CK_OrdenesTrabajo_EstadoOrden]
GO

-- Agregar el nuevo CHECK con los 5 estados reales
ALTER TABLE [dbo].[OrdenesTrabajo]
    ADD CONSTRAINT [CK_OrdenesTrabajo_EstadoOrden] CHECK (
        [EstadoOrden] IN (
            'Pendiente',      -- Asignada, no trabajada aun
            'En Proceso',     -- Tecnico esta trabajando en ella
            'Escalada',       -- Trabajada pero NO puesta en servicio (equipos fantasma)
            'Completada',     -- Puesta en servicio + liquidada
            'Cancelada'       -- No factible o cancelada
        )
    )
GO

PRINT 'Paso 1.1 OK: Estado Escalada agregado a OrdenesTrabajo'
GO






-- Agregar columna FechaVencimiento (NO calculada, se llena al insertar)
-- Razon: las columnas calculadas con GETDATE() no son permitidas como
-- persistidas. Mejor llenarla desde el SP de creacion de factura.
ALTER TABLE [dbo].[AsignacionEquipos]
    ADD [FechaVencimiento] DATE NULL
GO

-- Backfill para registros existentes (si hay alguno): poner 90 dias 
-- despues de la fecha de la factura asociada
UPDATE AE
SET AE.[FechaVencimiento] = DATEADD(DAY, 90, F.[FechaFactura])
FROM [dbo].[AsignacionEquipos] AE
INNER JOIN [dbo].[Facturas] F ON F.[NumeroFactura] = AE.[NumeroFactura]
WHERE AE.[FechaVencimiento] IS NULL
GO

-- Ahora si, hacerla NOT NULL
ALTER TABLE [dbo].[AsignacionEquipos]
    ALTER COLUMN [FechaVencimiento] DATE NOT NULL
GO

-- Quitar el CHECK actual de estados
ALTER TABLE [dbo].[AsignacionEquipos]
    DROP CONSTRAINT [CK_AsignacionEquipos_Estado]
GO

-- Agregar nuevo CHECK con los 4 estados
ALTER TABLE [dbo].[AsignacionEquipos]
    ADD CONSTRAINT [CK_AsignacionEquipos_Estado] CHECK (
        [EstadoAsignacion] IN (
            'Activa',       -- En custodia del tecnico, dentro de plazo
            'Vencida',      -- Pasaron 90 dias sin instalar (alerta de descuento)
            'Devuelta',     -- Tecnico la devolvio a bodega
            'Traspasada'    -- Pasada a otro tecnico (cierra esta, abre nueva)
        )
    )
GO

-- Indice para consultas de "que se me vence pronto"
CREATE NONCLUSTERED INDEX [IX_AsignacionEquipos_FechaVencimiento]
    ON [dbo].[AsignacionEquipos] ([FechaVencimiento] ASC)
    WHERE [EstadoAsignacion] = 'Activa'
GO

PRINT 'Paso 1.2 OK: FechaVencimiento + nuevos estados de asignacion'
GO






CREATE TABLE [dbo].[TraspasoEquipos] (
    [IDTraspaso]            INT             IDENTITY(1,1)   NOT NULL,
    [NumeroSerie]           VARCHAR(50)                     NOT NULL,
    [CuadrillaOrigen]       INT                             NOT NULL,
    -- FK al CodigoTecnico que CEDE el equipo
    [CuadrillaDestino]      INT                             NOT NULL,
    -- FK al CodigoTecnico que RECIBE el equipo
    [FechaTraspaso]         DATETIME                        NOT NULL    DEFAULT GETDATE(),
    [MotivoTraspaso]        NVARCHAR(50)                    NOT NULL,
    -- Razon del traspaso (ver CHECK abajo)
    [IDAsignacionOrigen]    INT                             NOT NULL,
    -- FK a la asignacion ORIGINAL que se cierra (estado Traspasada)
    [IDAsignacionDestino]   INT                             NOT NULL,
    -- FK a la NUEVA asignacion que se crea (estado Activa)
    [IDUsuarioAutoriza]     INT                             NOT NULL,
    -- Quien autoriza el traspaso (Bodeguero, Jefe de Bodega o Gerente)
    [Observaciones]         NVARCHAR(200)                   NULL,

    CONSTRAINT [PK_TraspasoEquipos] PRIMARY KEY CLUSTERED ([IDTraspaso] ASC),

    CONSTRAINT [FK_TraspasoEquipos_EquiposSeriados] FOREIGN KEY ([NumeroSerie])
        REFERENCES [dbo].[EquiposSeriados] ([NumeroSerie]),

    CONSTRAINT [FK_TraspasoEquipos_TecnicoOrigen] FOREIGN KEY ([CuadrillaOrigen])
        REFERENCES [dbo].[Tecnicos] ([CodigoTecnico]),

    CONSTRAINT [FK_TraspasoEquipos_TecnicoDestino] FOREIGN KEY ([CuadrillaDestino])
        REFERENCES [dbo].[Tecnicos] ([CodigoTecnico]),

    CONSTRAINT [FK_TraspasoEquipos_AsignacionOrigen] FOREIGN KEY ([IDAsignacionOrigen])
        REFERENCES [dbo].[AsignacionEquipos] ([IDRegistro]),

    CONSTRAINT [FK_TraspasoEquipos_AsignacionDestino] FOREIGN KEY ([IDAsignacionDestino])
        REFERENCES [dbo].[AsignacionEquipos] ([IDRegistro]),

    CONSTRAINT [FK_TraspasoEquipos_UsuarioAutoriza] FOREIGN KEY ([IDUsuarioAutoriza])
        REFERENCES [dbo].[Usuarios] ([IDUsuario]),

    CONSTRAINT [CK_TraspasoEquipos_Motivo] CHECK (
        [MotivoTraspaso] IN (
            'Proximo a vencer',         -- El que mas se va a usar
            'Tecnico no necesita',      -- Ya no requiere el equipo
            'Cambio de cuadrilla',      -- Reorganizacion administrativa
            'Solicitud del destino',    -- Otro tecnico lo necesita
            'Otro'                      -- Comodin con observaciones
        )
    ),

    CONSTRAINT [CK_TraspasoEquipos_NoMismoTecnico] CHECK (
        [CuadrillaOrigen] <> [CuadrillaDestino]
    )
    -- No tiene sentido traspasarse un equipo a si mismo
) ON [PRIMARY]
GO

-- Indices para consultas frecuentes
CREATE NONCLUSTERED INDEX [IX_TraspasoEquipos_NumeroSerie]
    ON [dbo].[TraspasoEquipos] ([NumeroSerie] ASC)
GO

CREATE NONCLUSTERED INDEX [IX_TraspasoEquipos_CuadrillaOrigen]
    ON [dbo].[TraspasoEquipos] ([CuadrillaOrigen] ASC, [FechaTraspaso] DESC)
GO

CREATE NONCLUSTERED INDEX [IX_TraspasoEquipos_CuadrillaDestino]
    ON [dbo].[TraspasoEquipos] ([CuadrillaDestino] ASC, [FechaTraspaso] DESC)
GO

PRINT 'Paso 1.3 OK: Tabla TraspasoEquipos creada con indices'
GO

-- Eliminamos la version anterior
IF OBJECT_ID('[dbo].[usp_CrearFacturaCompleta]', 'P') IS NOT NULL
    DROP PROCEDURE [dbo].[usp_CrearFacturaCompleta]
GO

-- ----------------------------------------------------------------------------
-- AJUSTADO: Ahora llena FechaVencimiento (FechaFactura + 90 dias).
-- Lo demas se mantiene identico.
-- ----------------------------------------------------------------------------
CREATE PROCEDURE [dbo].[usp_CrearFacturaCompleta]
    @CodigoTecnico    INT,
    @IDUsuarioBodega  INT,
    @Observaciones    NVARCHAR(200) = NULL,
    @Equipos          [dbo].[TVP_EquiposSeriados] READONLY,
    @Materiales       [dbo].[TVP_Materiales] READONLY,
    @UsuarioLogin     VARCHAR(20)
AS
BEGIN
    SET NOCOUNT ON;

    BEGIN TRY
        BEGIN TRANSACTION;

        -- Validar tecnico activo
        IF NOT EXISTS (
            SELECT 1 FROM [dbo].[Tecnicos]
            WHERE [CodigoTecnico] = @CodigoTecnico AND [EstadoLaboral] = 'Activo'
        )
        BEGIN
            THROW 57000, 'Tecnico no encontrado o no esta activo.', 1;
            RETURN;
        END

        -- Validar usuario de bodega activo
        IF NOT EXISTS (
            SELECT 1 FROM [dbo].[Usuarios]
            WHERE [IDUsuario] = @IDUsuarioBodega AND [EstadoUsuario] = 'Activo'
        )
        BEGIN
            THROW 57001, 'Usuario de bodega no encontrado o no esta activo.', 1;
            RETURN;
        END

        -- Validar equipos disponibles
        IF EXISTS (
            SELECT 1 FROM @Equipos E
            LEFT JOIN [dbo].[EquiposSeriados] ES ON ES.[NumeroSerie] = E.[NumeroSerie]
            WHERE ES.[NumeroSerie] IS NULL OR ES.[EstadoEquipo] <> 'Bodega'
        )
        BEGIN
            THROW 57002, 'Al menos un equipo no existe o no esta disponible en bodega.', 1;
            RETURN;
        END

        -- Validar stock de materiales
        IF EXISTS (
            SELECT 1 FROM @Materiales M
            LEFT JOIN [dbo].[MaterialesMiscelaneos] MM ON MM.[CodigoMaterial] = M.[CodigoMaterial]
            WHERE MM.[CodigoMaterial] IS NULL OR MM.[StockBodega] < M.[Cantidad]
        )
        BEGIN
            THROW 57003, 'Al menos un material no existe o no tiene stock suficiente.', 1;
            RETURN;
        END

        -- 1) Cabecera de factura
        INSERT INTO [dbo].[Facturas] ([CodigoTecnico], [IDUsuarioBodega], [Observaciones])
        VALUES (@CodigoTecnico, @IDUsuarioBodega, @Observaciones);

        DECLARE @NumeroFactura INT = SCOPE_IDENTITY();

        -- Calcular fecha de vencimiento: 90 dias despues de hoy
        DECLARE @FechaVencimiento DATE = DATEADD(DAY, 90, CAST(GETDATE() AS DATE));

        -- 2) Lineas de equipos (CON FechaVencimiento)
        INSERT INTO [dbo].[AsignacionEquipos] (
            [NumeroFactura], [NumeroSerie], [FechaVencimiento]
        )
        SELECT @NumeroFactura, [NumeroSerie], @FechaVencimiento FROM @Equipos;

        -- 3) Lineas de materiales
        INSERT INTO [dbo].[AsignacionMateriales] ([NumeroFactura], [CodigoMaterial], [Cantidad])
        SELECT @NumeroFactura, [CodigoMaterial], [Cantidad] FROM @Materiales;

        -- 4) Equipos a estado Asignado
        UPDATE ES
        SET [EstadoEquipo] = 'Asignado'
        FROM [dbo].[EquiposSeriados] ES
        INNER JOIN @Equipos E ON E.[NumeroSerie] = ES.[NumeroSerie];

        -- 5) Descontar stock
        UPDATE MM
        SET [StockBodega] = MM.[StockBodega] - M.[Cantidad]
        FROM [dbo].[MaterialesMiscelaneos] MM
        INNER JOIN @Materiales M ON M.[CodigoMaterial] = MM.[CodigoMaterial];

        EXEC [dbo].[usp_RegistrarBitacora]
            @TablaAfectada = N'Facturas',
            @TipoOperacion = 'I',
            @RegistroID    = @NumeroFactura,
            @UsuarioLogin  = @UsuarioLogin;

        COMMIT TRANSACTION;

        SELECT @NumeroFactura AS [NumeroFactura], @FechaVencimiento AS [FechaVencimiento];
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        THROW;
    END CATCH
END
GO

PRINT 'Paso 2.1 OK: usp_CrearFacturaCompleta ajustado con FechaVencimiento'
GO




IF OBJECT_ID('[dbo].[usp_CambiarEstadoOrden]', 'P') IS NOT NULL
    DROP PROCEDURE [dbo].[usp_CambiarEstadoOrden]
GO

-- ----------------------------------------------------------------------------
-- AJUSTADO: Ahora soporta el estado Escalada con sus transiciones validas.
-- 
-- Reglas de transicion:
--   Pendiente   -> En Proceso, Escalada, Cancelada
--   En Proceso  -> Escalada, Completada, Cancelada
--   Escalada    -> En Proceso (cuando vuelve para retomar), Completada
--   Completada  -> (terminal)
--   Cancelada   -> (terminal)
-- ----------------------------------------------------------------------------
CREATE PROCEDURE [dbo].[usp_CambiarEstadoOrden]
    @NumeroSolicitud   VARCHAR(20),
    @NuevoEstado       NVARCHAR(20),
    @UsuarioLogin      VARCHAR(20)
AS
BEGIN
    SET NOCOUNT ON;

    BEGIN TRY
        DECLARE @EstadoAnterior NVARCHAR(20);

        SELECT @EstadoAnterior = [EstadoOrden]
        FROM [dbo].[OrdenesTrabajo]
        WHERE [NumeroSolicitud] = @NumeroSolicitud;

        IF @EstadoAnterior IS NULL
        BEGIN
            THROW 56001, 'Orden no encontrada.', 1;
            RETURN;
        END

        -- Estados terminales: no se pueden modificar
        IF @EstadoAnterior IN ('Completada','Cancelada')
        BEGIN
            THROW 56002, 'La orden esta en estado terminal y no puede cambiar.', 1;
            RETURN;
        END

        -- Validar transiciones desde cada estado de origen
        IF @EstadoAnterior = 'Pendiente' 
           AND @NuevoEstado NOT IN ('En Proceso','Escalada','Cancelada')
        BEGIN
            THROW 56003, 'Transicion no valida desde Pendiente. Permitidas: En Proceso, Escalada, Cancelada.', 1;
            RETURN;
        END

        IF @EstadoAnterior = 'En Proceso' 
           AND @NuevoEstado NOT IN ('Escalada','Completada','Cancelada')
        BEGIN
            THROW 56004, 'Transicion no valida desde En Proceso. Permitidas: Escalada, Completada, Cancelada.', 1;
            RETURN;
        END

        IF @EstadoAnterior = 'Escalada' 
           AND @NuevoEstado NOT IN ('En Proceso','Completada')
        BEGIN
            THROW 56005, 'Transicion no valida desde Escalada. Permitidas: En Proceso, Completada.', 1;
            RETURN;
        END

        UPDATE [dbo].[OrdenesTrabajo]
        SET [EstadoOrden] = @NuevoEstado
        WHERE [NumeroSolicitud] = @NumeroSolicitud;

        EXEC [dbo].[usp_RegistrarBitacora]
            @TablaAfectada   = N'OrdenesTrabajo',
            @TipoOperacion   = 'U',
            @RegistroID      = @NumeroSolicitud,
            @CampoModificado = N'EstadoOrden',
            @ValorAnterior   = @EstadoAnterior,
            @ValorNuevo      = @NuevoEstado,
            @UsuarioLogin    = @UsuarioLogin;
    END TRY
    BEGIN CATCH
        THROW;
    END CATCH
END
GO

PRINT 'Paso 2.2 OK: usp_CambiarEstadoOrden ajustado con estado Escalada'
GO





-- ----------------------------------------------------------------------------
-- NUEVO: Escala una orden con motivo registrado en bitacora.
-- Es un atajo conveniente sobre usp_CambiarEstadoOrden que ademas exige
-- el motivo de la escalacion (problema de sistema, error humano, etc.).
-- ----------------------------------------------------------------------------
CREATE PROCEDURE [dbo].[usp_EscalarOrden]
    @NumeroSolicitud   VARCHAR(20),
    @MotivoEscalacion  NVARCHAR(200),
    @UsuarioLogin      VARCHAR(20)
AS
BEGIN
    SET NOCOUNT ON;

    BEGIN TRY
        DECLARE @EstadoAnterior NVARCHAR(20);

        SELECT @EstadoAnterior = [EstadoOrden]
        FROM [dbo].[OrdenesTrabajo]
        WHERE [NumeroSolicitud] = @NumeroSolicitud;

        IF @EstadoAnterior IS NULL
        BEGIN
            THROW 56001, 'Orden no encontrada.', 1;
            RETURN;
        END

        IF @EstadoAnterior NOT IN ('Pendiente','En Proceso')
        BEGIN
            THROW 56010, 'Solo se puede escalar desde Pendiente o En Proceso.', 1;
            RETURN;
        END

        -- Cambiar estado
        UPDATE [dbo].[OrdenesTrabajo]
        SET [EstadoOrden] = 'Escalada'
        WHERE [NumeroSolicitud] = @NumeroSolicitud;

        -- Registrar el motivo en bitacora con detalle especifico
        EXEC [dbo].[usp_RegistrarBitacora]
            @TablaAfectada   = N'OrdenesTrabajo',
            @TipoOperacion   = 'U',
            @RegistroID      = @NumeroSolicitud,
            @CampoModificado = N'EscalacionMotivo',
            @ValorAnterior   = @EstadoAnterior,
            @ValorNuevo      = @MotivoEscalacion,
            @UsuarioLogin    = @UsuarioLogin;
    END TRY
    BEGIN CATCH
        THROW;
    END CATCH
END
GO

PRINT 'Paso 2.3 OK: usp_EscalarOrden creado'
GO



-- ----------------------------------------------------------------------------
-- NUEVO: Marca como Vencidas las asignaciones cuya FechaVencimiento ya paso.
-- Este SP debe correrse diariamente (job de SQL Agent o llamado desde la
-- aplicacion C# al iniciar el dia).
-- 
-- No borra nada. Solo cambia el estado de Activa a Vencida para que el
-- tecnico vea las alertas en la UI.
-- ----------------------------------------------------------------------------
CREATE PROCEDURE [dbo].[usp_MarcarEquiposVencidos]
    @UsuarioLogin VARCHAR(20) = 'SISTEMA'
AS
BEGIN
    SET NOCOUNT ON;

    BEGIN TRY
        DECLARE @Hoy DATE = CAST(GETDATE() AS DATE);
        DECLARE @TotalVencidos INT;

        -- Contar cuantos vamos a marcar
        SELECT @TotalVencidos = COUNT(*)
        FROM [dbo].[AsignacionEquipos]
        WHERE [EstadoAsignacion] = 'Activa'
          AND [FechaVencimiento] < @Hoy;

        IF @TotalVencidos = 0
        BEGIN
            SELECT 0 AS [TotalMarcados], 'No hay equipos vencidos hoy' AS [Mensaje];
            RETURN;
        END

        -- Registrar en bitacora ANTES de actualizar (para tener el detalle)
        INSERT INTO [dbo].[BitacoraAuditoria] (
            [TablaAfectada], [TipoOperacion], [RegistroID],
            [CampoModificado], [ValorAnterior], [ValorNuevo],
            [UsuarioLogin]
        )
        SELECT
            N'AsignacionEquipos',
            'U',
            CAST(AE.[IDRegistro] AS NVARCHAR(50)),
            N'EstadoAsignacion',
            N'Activa',
            N'Vencida',
            @UsuarioLogin
        FROM [dbo].[AsignacionEquipos] AE
        WHERE AE.[EstadoAsignacion] = 'Activa'
          AND AE.[FechaVencimiento] < @Hoy;

        -- Actualizar estado
        UPDATE [dbo].[AsignacionEquipos]
        SET [EstadoAsignacion] = 'Vencida'
        WHERE [EstadoAsignacion] = 'Activa'
          AND [FechaVencimiento] < @Hoy;

        SELECT @TotalVencidos AS [TotalMarcados], 'Equipos marcados como Vencidos' AS [Mensaje];
    END TRY
    BEGIN CATCH
        THROW;
    END CATCH
END
GO

PRINT 'Paso 2.4 OK: usp_MarcarEquiposVencidos creado'
GO




-- ----------------------------------------------------------------------------
-- NUEVO: Lista equipos asignados a un tecnico que estan por vencer.
-- 
-- Devuelve clasificados por urgencia:
--   - Vencidos (rojo)
--   - 0-7 dias por vencer (rojo)
--   - 8-15 dias (amarillo)
--   - 16-30 dias (amarillo claro)
--   - 31+ dias (verde)
-- 
-- Si @CodigoTecnico es NULL, devuelve para TODOS los tecnicos
-- (uso del Jefe de Bodega).
-- ----------------------------------------------------------------------------
CREATE PROCEDURE [dbo].[usp_ListarEquiposPorVencer]
    @CodigoTecnico INT = NULL,
    @DiasMaximos   INT = 30   -- Solo mostrar los que vencen dentro de N dias
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @Hoy DATE = CAST(GETDATE() AS DATE);

    SELECT
        T.[CodigoCuadrilla],
        T.[Nombre] + ' ' + T.[Apellido] AS [NombreTecnico],
        AE.[IDRegistro],
        AE.[NumeroSerie],
        ES.[Modelo],
        ES.[TipoAparato],
        F.[NumeroFactura],
        F.[FechaFactura],
        AE.[FechaVencimiento],
        DATEDIFF(DAY, @Hoy, AE.[FechaVencimiento]) AS [DiasRestantes],
        AE.[EstadoAsignacion],
        CASE
            WHEN AE.[EstadoAsignacion] = 'Vencida' THEN 'VENCIDO'
            WHEN DATEDIFF(DAY, @Hoy, AE.[FechaVencimiento]) <= 7  THEN 'CRITICO'
            WHEN DATEDIFF(DAY, @Hoy, AE.[FechaVencimiento]) <= 15 THEN 'URGENTE'
            WHEN DATEDIFF(DAY, @Hoy, AE.[FechaVencimiento]) <= 30 THEN 'PROXIMO'
            ELSE 'NORMAL'
        END AS [NivelAlerta]
    FROM [dbo].[AsignacionEquipos] AE
    INNER JOIN [dbo].[Facturas] F         ON F.[NumeroFactura] = AE.[NumeroFactura]
    INNER JOIN [dbo].[Tecnicos] T         ON T.[CodigoTecnico] = F.[CodigoTecnico]
    INNER JOIN [dbo].[EquiposSeriados] ES ON ES.[NumeroSerie]  = AE.[NumeroSerie]
    WHERE AE.[EstadoAsignacion] IN ('Activa','Vencida')
      AND (@CodigoTecnico IS NULL OR F.[CodigoTecnico] = @CodigoTecnico)
      AND DATEDIFF(DAY, @Hoy, AE.[FechaVencimiento]) <= @DiasMaximos
    ORDER BY AE.[FechaVencimiento] ASC, T.[CodigoCuadrilla];
END
GO

PRINT 'Paso 2.5 OK: usp_ListarEquiposPorVencer creado'
GO



-- ----------------------------------------------------------------------------
-- EL SP MAS IMPORTANTE DE LA ENTREGA 2. [COMPUESTO TRANSACCIONAL]
-- 
-- Traspasa un equipo de un tecnico a otro SIN pasar por bodega.
-- 
-- Flujo atomico:
--   1. Validaciones (equipo asignado al origen, ambos tecnicos activos, etc.)
--   2. Cierra la asignacion del tecnico ORIGEN (estado = Traspasada)
--   3. Crea una NUEVA asignacion para el tecnico DESTINO (estado = Activa)
--      - La nueva asignacion HEREDA la fecha de vencimiento original
--        (el plazo de 90 dias NO se reinicia, se mantiene desde la
--         factura original, porque el equipo es el mismo).
--      - Se asocia a la MISMA factura del origen (mismo NumeroFactura).
--   4. Inserta el registro en TraspasoEquipos
--   5. El equipo (EquiposSeriados) NO cambia de estado: sigue 'Asignado'.
--   6. Bitacora.
-- ----------------------------------------------------------------------------
CREATE PROCEDURE [dbo].[usp_TraspasarEquipoEntreTecnicos]
    @NumeroSerie         VARCHAR(50),
    @CuadrillaOrigen     INT,
    @CuadrillaDestino    INT,
    @MotivoTraspaso      NVARCHAR(50),
    @IDUsuarioAutoriza   INT,
    @Observaciones       NVARCHAR(200) = NULL,
    @UsuarioLogin        VARCHAR(20)
AS
BEGIN
    SET NOCOUNT ON;

    BEGIN TRY
        BEGIN TRANSACTION;

        -- ---- VALIDACIONES PREVIAS ----

        -- 1) Validar que origen y destino sean diferentes
        IF @CuadrillaOrigen = @CuadrillaDestino
        BEGIN
            THROW 60000, 'No se puede traspasar al mismo tecnico.', 1;
            RETURN;
        END

        -- 2) Validar tecnico ORIGEN existe y esta Activo
        IF NOT EXISTS (
            SELECT 1 FROM [dbo].[Tecnicos]
            WHERE [CodigoTecnico] = @CuadrillaOrigen AND [EstadoLaboral] = 'Activo'
        )
        BEGIN
            THROW 60001, 'Tecnico de origen no encontrado o no esta activo.', 1;
            RETURN;
        END

        -- 3) Validar tecnico DESTINO existe y esta Activo
        IF NOT EXISTS (
            SELECT 1 FROM [dbo].[Tecnicos]
            WHERE [CodigoTecnico] = @CuadrillaDestino AND [EstadoLaboral] = 'Activo'
        )
        BEGIN
            THROW 60002, 'Tecnico de destino no encontrado o no esta activo.', 1;
            RETURN;
        END

        -- 4) Validar usuario que autoriza esta Activo
        IF NOT EXISTS (
            SELECT 1 FROM [dbo].[Usuarios]
            WHERE [IDUsuario] = @IDUsuarioAutoriza AND [EstadoUsuario] = 'Activo'
        )
        BEGIN
            THROW 60003, 'Usuario que autoriza no es valido.', 1;
            RETURN;
        END

        -- 5) Buscar la asignacion ACTIVA o VENCIDA del equipo en el origen
        DECLARE @IDAsignacionOrigen   INT;
        DECLARE @NumeroFacturaOrigen  INT;
        DECLARE @FechaVencimientoOrig DATE;
        DECLARE @EstadoAsignacionOrig NVARCHAR(10);

        SELECT TOP 1
            @IDAsignacionOrigen   = AE.[IDRegistro],
            @NumeroFacturaOrigen  = AE.[NumeroFactura],
            @FechaVencimientoOrig = AE.[FechaVencimiento],
            @EstadoAsignacionOrig = AE.[EstadoAsignacion]
        FROM [dbo].[AsignacionEquipos] AE
        INNER JOIN [dbo].[Facturas] F ON F.[NumeroFactura] = AE.[NumeroFactura]
        WHERE AE.[NumeroSerie]      = @NumeroSerie
          AND F.[CodigoTecnico]     = @CuadrillaOrigen
          AND AE.[EstadoAsignacion] IN ('Activa','Vencida');

        IF @IDAsignacionOrigen IS NULL
        BEGIN
            THROW 60004, 'El equipo no esta asignado actualmente al tecnico de origen.', 1;
            RETURN;
        END

        -- ---- EJECUCION DEL TRASPASO ----

        -- 6) Cerrar asignacion del origen
        UPDATE [dbo].[AsignacionEquipos]
        SET [EstadoAsignacion] = 'Traspasada'
        WHERE [IDRegistro] = @IDAsignacionOrigen;

        -- 7) Crear nueva FACTURA "virtual" para el destino
        --    NOTA: Decision de diseno - creamos una factura nueva con
        --    observacion explicita de que es un traspaso. Esto mantiene
        --    la trazabilidad limpia: cada tecnico tiene sus propias facturas.
        INSERT INTO [dbo].[Facturas] (
            [CodigoTecnico], [IDUsuarioBodega], [Observaciones]
        )
        VALUES (
            @CuadrillaDestino,
            @IDUsuarioAutoriza,
            'TRASPASO desde factura #' + CAST(@NumeroFacturaOrigen AS VARCHAR(10))
            + ISNULL(' - ' + @Observaciones, '')
        );

        DECLARE @NumeroFacturaDestino INT = SCOPE_IDENTITY();

        -- 8) Crear nueva asignacion en el destino HEREDANDO la fecha de
        --    vencimiento original (el plazo NO se reinicia)
        INSERT INTO [dbo].[AsignacionEquipos] (
            [NumeroFactura], [NumeroSerie], [FechaVencimiento]
        )
        VALUES (
            @NumeroFacturaDestino, @NumeroSerie, @FechaVencimientoOrig
        );

        DECLARE @IDAsignacionDestino INT = SCOPE_IDENTITY();

        -- 9) Registrar el traspaso oficial
        INSERT INTO [dbo].[TraspasoEquipos] (
            [NumeroSerie], [CuadrillaOrigen], [CuadrillaDestino],
            [MotivoTraspaso], [IDAsignacionOrigen], [IDAsignacionDestino],
            [IDUsuarioAutoriza], [Observaciones]
        )
        VALUES (
            @NumeroSerie, @CuadrillaOrigen, @CuadrillaDestino,
            @MotivoTraspaso, @IDAsignacionOrigen, @IDAsignacionDestino,
            @IDUsuarioAutoriza, @Observaciones
        );

        DECLARE @IDTraspaso INT = SCOPE_IDENTITY();

        -- 10) Bitacora
        EXEC [dbo].[usp_RegistrarBitacora]
            @TablaAfectada = N'TraspasoEquipos',
            @TipoOperacion = 'I',
            @RegistroID    = @IDTraspaso,
            @CampoModificado = N'NumeroSerie',
            @ValorAnterior = @NumeroSerie,
            @ValorNuevo    = @MotivoTraspaso,
            @UsuarioLogin  = @UsuarioLogin;

        COMMIT TRANSACTION;

        -- Devolver IDs generados para que la app C# pueda usarlos
        SELECT 
            @IDTraspaso           AS [IDTraspaso],
            @IDAsignacionDestino  AS [IDAsignacionNueva],
            @NumeroFacturaDestino AS [NumeroFacturaTraspaso],
            @FechaVencimientoOrig AS [FechaVencimientoHeredada];
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        THROW;
    END CATCH
END
GO

PRINT 'Paso 2.6 OK: usp_TraspasarEquipoEntreTecnicos creado'
GO




-- ----------------------------------------------------------------------------
-- NUEVO: Historial de traspasos de un equipo (cadena de custodia).
-- Util cuando hay disputa o auditoria de Claro sobre un equipo especifico.
-- ----------------------------------------------------------------------------
CREATE PROCEDURE [dbo].[usp_ConsultarHistorialTraspasos]
    @NumeroSerie VARCHAR(50)
AS
BEGIN
    SET NOCOUNT ON;

    SELECT
        TE.[IDTraspaso],
        TE.[FechaTraspaso],
        TO1.[CodigoCuadrilla] AS [CuadrillaOrigen],
        TO1.[Nombre] + ' ' + TO1.[Apellido] AS [TecnicoOrigen],
        TD.[CodigoCuadrilla] AS [CuadrillaDestino],
        TD.[Nombre] + ' ' + TD.[Apellido] AS [TecnicoDestino],
        TE.[MotivoTraspaso],
        U.[UsuarioLogin] AS [Autorizado],
        U.[Nombres] + ' ' + U.[Apellidos] AS [NombreAutorizador],
        TE.[Observaciones]
    FROM [dbo].[TraspasoEquipos] TE
    INNER JOIN [dbo].[Tecnicos] TO1 ON TO1.[CodigoTecnico] = TE.[CuadrillaOrigen]
    INNER JOIN [dbo].[Tecnicos] TD  ON TD.[CodigoTecnico]  = TE.[CuadrillaDestino]
    INNER JOIN [dbo].[Usuarios] U   ON U.[IDUsuario]       = TE.[IDUsuarioAutoriza]
    WHERE TE.[NumeroSerie] = @NumeroSerie
    ORDER BY TE.[FechaTraspaso] ASC;
END
GO

PRINT 'Paso 2.7 OK: usp_ConsultarHistorialTraspasos creado'
GO




IF OBJECT_ID('[dbo].[usp_RegistrarLiquidacionOrden]', 'P') IS NOT NULL
    DROP PROCEDURE [dbo].[usp_RegistrarLiquidacionOrden]
GO

-- ----------------------------------------------------------------------------
-- AJUSTADO: Ahora permite liquidar desde estado Pendiente, En Proceso O Escalada.
-- Esto es CRITICO: cuando una orden Escalada finalmente se pone en
-- servicio, el tecnico debe poder declarar los equipos.
-- 
-- Tambien actualiza la asignacion del equipo a estado "Devuelta" (no
-- 'Activa') porque ya fue instalado en casa del cliente.
-- ----------------------------------------------------------------------------
CREATE PROCEDURE [dbo].[usp_RegistrarLiquidacionOrden]
    @NumeroSolicitud    VARCHAR(20),
    @CodigoTecnico      INT,
    @FechaInstalacion   DATE,
    @EquiposInstalados  [dbo].[TVP_EquiposSeriados] READONLY,
    @MaterialesUsados   [dbo].[TVP_Materiales] READONLY,
    @UsuarioLogin       VARCHAR(20)
AS
BEGIN
    SET NOCOUNT ON;

    BEGIN TRY
        BEGIN TRANSACTION;

        DECLARE @EstadoOrden NVARCHAR(20);
        SELECT @EstadoOrden = [EstadoOrden]
        FROM [dbo].[OrdenesTrabajo]
        WHERE [NumeroSolicitud] = @NumeroSolicitud;

        IF @EstadoOrden IS NULL
        BEGIN
            THROW 58000, 'Orden no encontrada.', 1;
            RETURN;
        END

        -- AJUSTE: Ahora se acepta tambien el estado Escalada
        IF @EstadoOrden NOT IN ('Pendiente','En Proceso','Escalada')
        BEGIN
            THROW 58001, 'La orden no esta en estado valido para liquidacion.', 1;
            RETURN;
        END

        -- Validar que cada equipo este asignado al tecnico (Activa o Vencida)
        -- Vencida tambien se acepta porque puede que se haya instalado
        -- justo antes de vencer y ahora se este declarando
        IF EXISTS (
            SELECT 1 FROM @EquiposInstalados EI
            WHERE NOT EXISTS (
                SELECT 1 FROM [dbo].[AsignacionEquipos] AE
                INNER JOIN [dbo].[Facturas] F ON F.[NumeroFactura] = AE.[NumeroFactura]
                WHERE AE.[NumeroSerie]      = EI.[NumeroSerie]
                  AND AE.[EstadoAsignacion] IN ('Activa','Vencida')
                  AND F.[CodigoTecnico]     = @CodigoTecnico
            )
        )
        BEGIN
            THROW 58002, 'Al menos un equipo no esta asignado actualmente a este tecnico.', 1;
            RETURN;
        END

        -- 1) Detalles de equipos instalados
        INSERT INTO [dbo].[DetalleInstalacion] (
            [NumeroSolicitud], [CodigoTecnico], [FechaInstalacion], [NumeroSerie]
        )
        SELECT @NumeroSolicitud, @CodigoTecnico, @FechaInstalacion, [NumeroSerie]
        FROM @EquiposInstalados;

        -- 2) Detalles de materiales usados
        INSERT INTO [dbo].[DetalleInstalacion] (
            [NumeroSolicitud], [CodigoTecnico], [FechaInstalacion], [CodigoMaterial], [CantidadUtilizada]
        )
        SELECT @NumeroSolicitud, @CodigoTecnico, @FechaInstalacion, [CodigoMaterial], [Cantidad]
        FROM @MaterialesUsados;

        -- 3) Cambiar estado de equipos a Instalado
        UPDATE ES
        SET [EstadoEquipo] = 'Instalado'
        FROM [dbo].[EquiposSeriados] ES
        INNER JOIN @EquiposInstalados EI ON EI.[NumeroSerie] = ES.[NumeroSerie];

        -- 4) Cambiar estado de las ASIGNACIONES de esos equipos a Devuelta
        --    (porque ya no estan en custodia del tecnico, estan instaladas)
        UPDATE AE
        SET [EstadoAsignacion] = 'Devuelta'
        FROM [dbo].[AsignacionEquipos] AE
        INNER JOIN [dbo].[Facturas] F ON F.[NumeroFactura] = AE.[NumeroFactura]
        INNER JOIN @EquiposInstalados EI ON EI.[NumeroSerie] = AE.[NumeroSerie]
        WHERE F.[CodigoTecnico] = @CodigoTecnico
          AND AE.[EstadoAsignacion] IN ('Activa','Vencida');

        -- 5) Cambiar estado de la orden a Completada
        UPDATE [dbo].[OrdenesTrabajo]
        SET [EstadoOrden] = 'Completada'
        WHERE [NumeroSolicitud] = @NumeroSolicitud;

        EXEC [dbo].[usp_RegistrarBitacora]
            @TablaAfectada = N'OrdenesTrabajo',
            @TipoOperacion = 'U',
            @RegistroID    = @NumeroSolicitud,
            @CampoModificado = N'EstadoOrden',
            @ValorAnterior = @EstadoOrden,
            @ValorNuevo    = N'Completada',
            @UsuarioLogin  = @UsuarioLogin;

        COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        THROW;
    END CATCH
END
GO

PRINT 'Paso 2.8 OK: usp_RegistrarLiquidacionOrden ajustado'
GO