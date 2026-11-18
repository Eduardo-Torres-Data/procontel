# Procontel

Procontel es una base de datos para llevar el control de equipos y materiales en instalaciones de telecomunicaciones. Registra qué equipo salió de bodega, a qué técnico se le asignó y en qué orden se instaló. También guarda los traspasos, las devoluciones y las visitas de garantía.

El proyecto nació en SQL Server y tiene una versión en PostgreSQL. La versión de PostgreSQL incluye vistas para consultar el inventario, la productividad de los técnicos y las liquidaciones pendientes desde Power BI.

## PostgreSQL

Con PostgreSQL 14 o superior, desde la carpeta del proyecto, crea una base de pruebas nueva y ejecuta el esquema. El segundo script es opcional y carga órdenes, inventario y técnicos de demostración.

```sh
createdb procontel_demo
psql -X -v ON_ERROR_STOP=1 -d procontel_demo -f "PROCONTEL POSTGRES/procontel_postgresql.sql"
psql -X -v ON_ERROR_STOP=1 -d procontel_demo -f "PROCONTEL POSTGRES/procontel_demo_postgresql.sql"
```

La carga de demo vacía las tablas operativas y reinicia sus secuencias. Ejecútala solo en la base de pruebas.

Para empezar a explorar los datos, puedes consultar el resumen de equipos por estado.

```sql
SELECT * FROM vw_kpi_inventory_global;
```

## SQL Server

El script original es [PROCONTEL_COMPLETO.sql](PROCONTEL_COMPLETO.sql) y se ejecuta desde SSMS en SQL Server 2019 o superior. Úsalo en una instancia de pruebas, ya que elimina y vuelve a crear la base `Procontel` si ya existe.
