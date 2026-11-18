--  PROCONTEL  -  Inventory Traceability System  (PostgreSQL port)
--  A field-operations inventory and equipment-traceability database for a
--  telecom subcontractor. Originally designed and implemented in SQL Server
--  (T-SQL); this file is a clean PostgreSQL 14+ port intended as a portfolio
--  artifact.
--
--  What this schema demonstrates:
--    - Relational modeling: 17 tables incl. RBAC, a transactional inventory
--      flow (dispatch -> install -> liquidate -> return) and an audit log.
--    - Constraint design: CHECKs, partial UNIQUE indexes, regex validation.
--    - Stored routines: FUNCTIONS that return result sets + PROCEDURES for
--      pure mutations; multi-table writes are atomic and roll back on error.
--    - Triggers: append-only auditing of the state changes that matter.
--    - BI layer: dimension / fact / KPI views ready for a dashboard tool.
--
--  Conventions:
--    - snake_case identifiers, lower_case keywords are also fine in PG.
--    - Routine prefixes: fn_ (returns data) / sp_ (mutates, no return).
--    - Permission codes follow "Module.Action".
--
--  File index (sections appear in dependency order):
--    SECTION A  Schema: tables, constraints, indexes
--    SECTION B  Composite types + routines (security, catalogs, business, reports)
--    SECTION C  Audit triggers
--    SECTION D  Analytical views (BI layer)
--    SECTION E  RBAC seed data
--
--  Run order is top-to-bottom. The script creates objects in an empty schema;
--  it does not create the database itself (run: CREATE DATABASE procontel;).



-- SECTION A  -  SCHEMA

-- PROCONTEL - Inventory Traceability System
-- Target engine : PostgreSQL 14+
-- Domain        : Field-operations inventory & equipment traceability for a
--                 telecom subcontractor serving a national ISP.
-- Author        : Eduardo  (portfolio project, originally authored in T-SQL)
-- This script is a PostgreSQL port of a SQL Server design. It is meant as a
-- portfolio artifact: it demonstrates relational modeling (RBAC, transactional
-- inventory flow, auditing), constraint design, stored routines, triggers and
-- analytical views.
--
-- File layout:
--   01_schema.sql   -> Database objects: tables, constraints, indexes
--   02_routines.sql -> Composite types, helper routines, CRUD/business logic
--   03_triggers.sql -> Audit triggers
--   04_views.sql    -> Dimension / fact / KPI views for BI consumption
--   05_seed_rbac.sql-> Initial roles & permissions (system data, not test data)

-- SECTION 1: SECURITY & ACCESS CONTROL (RBAC)

CREATE TABLE roles (
    role_id      INT          GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    role_name    VARCHAR(50)  NOT NULL UNIQUE,
    description  VARCHAR(200),
    role_status  VARCHAR(15)  NOT NULL DEFAULT 'Active'
                 CHECK (role_status IN ('Active', 'Inactive'))
);
-- Permissions use a technical code in "Module.Action" form, e.g. "Invoice.Void"
CREATE TABLE permissions (
    permission_id    INT          GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    permission_code  VARCHAR(50)  NOT NULL UNIQUE,
    module           VARCHAR(50)  NOT NULL,
    description      VARCHAR(200) NOT NULL
);

-- N:M between roles and permissions
CREATE TABLE role_permissions (
    role_id         INT       NOT NULL REFERENCES roles (role_id),
    permission_id   INT       NOT NULL REFERENCES permissions (permission_id),
    assigned_at     TIMESTAMP NOT NULL DEFAULT now(),
    PRIMARY KEY (role_id, permission_id)
);

-- Authentication accounts. The FK to technicians is added after that table
-- exists (forward reference resolved further down).
CREATE TABLE users (
    user_id          INT           GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    login            VARCHAR(20)   NOT NULL UNIQUE,
    password_hash    VARCHAR(128)  NOT NULL,
    first_name       VARCHAR(50)   NOT NULL,
    last_name        VARCHAR(50)   NOT NULL,
    email            VARCHAR(100),
    technician_id    INT,
    user_status      VARCHAR(15)   NOT NULL DEFAULT 'Active'
                     CHECK (user_status IN ('Active', 'Inactive', 'Locked')),
    created_at       TIMESTAMP     NOT NULL DEFAULT now(),
    last_login_at    TIMESTAMP
);

-- N:M between users and roles (a user may hold several roles)
CREATE TABLE user_roles (
    user_id      INT       NOT NULL REFERENCES users (user_id),
    role_id      INT       NOT NULL REFERENCES roles (role_id),
    assigned_at  TIMESTAMP NOT NULL DEFAULT now(),
    PRIMARY KEY (user_id, role_id)
);


-- SECTION 2: MASTER CATALOGS

-- Technicians. crew_code follows the company pattern PRO06..PRO999.
CREATE TABLE technicians (
    technician_id   INT          GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    crew_code       VARCHAR(10)  NOT NULL UNIQUE,
    national_id     VARCHAR(10)  NOT NULL UNIQUE,   -- gov ID (formatted ########-#)
    first_name      VARCHAR(50)  NOT NULL,
    last_name       VARCHAR(50)  NOT NULL,
    address         VARCHAR(150),
    phone           VARCHAR(9)   NOT NULL UNIQUE,
    blood_type      VARCHAR(3)   NOT NULL,
    marital_status  VARCHAR(15)  NOT NULL,
    birth_date      DATE         NOT NULL,
    gender          VARCHAR(10)  NOT NULL,
    license_type    VARCHAR(15),
    employment_status VARCHAR(15) NOT NULL DEFAULT 'Active',

    CONSTRAINT ck_technicians_crew_format CHECK (
        crew_code ~ '^PRO[0-9]{2,3}$'
    ),
    CONSTRAINT ck_technicians_national_id_format CHECK (
        national_id ~ '^[0-9]{8}-[0-9]$'
    ),
    CONSTRAINT ck_technicians_phone_format CHECK (
        phone ~ '^[0-9]{4}-[0-9]{4}$'
    ),
    CONSTRAINT ck_technicians_blood_type CHECK (
        blood_type IN ('A+','A-','B+','B-','AB+','AB-','O+','O-')
    ),
    CONSTRAINT ck_technicians_marital_status CHECK (
        marital_status IN ('Single','Married','Divorced','Widowed','Partnered')
    ),
    CONSTRAINT ck_technicians_gender CHECK (
        gender IN ('Male','Female')
    ),
    CONSTRAINT ck_technicians_license_type CHECK (
        license_type IN ('Motorcycle','Light','Heavy') OR license_type IS NULL
    ),
    CONSTRAINT ck_technicians_employment_status CHECK (
        employment_status IN ('Active','Inactive','OnLeave')
    )
);

-- Close the forward reference users -> technicians
ALTER TABLE users
    ADD CONSTRAINT fk_users_technicians
    FOREIGN KEY (technician_id) REFERENCES technicians (technician_id);

-- Serialized equipment: each unit has an individual identity (serial number)
CREATE TABLE serialized_equipment (
    serial_number   VARCHAR(50)  PRIMARY KEY,
    model           VARCHAR(100) NOT NULL,
    device_type     VARCHAR(20)  NOT NULL,
    equipment_status VARCHAR(15) NOT NULL DEFAULT 'Warehouse',
    received_date   DATE         NOT NULL DEFAULT CURRENT_DATE,

    CONSTRAINT ck_serialized_equipment_device_type CHECK (
        device_type IN ('Modem','ONT','IPTV','STB','Phone','Router','SIM','Switch')
    ),
    CONSTRAINT ck_serialized_equipment_status CHECK (
        equipment_status IN ('Warehouse','Assigned','Installed','Damaged','Warranty')
    )
);

-- Consumable (non-serialized) materials
CREATE TABLE materials (
    material_code   VARCHAR(15)   PRIMARY KEY,
    material_name   VARCHAR(100)  NOT NULL,
    unit_of_measure VARCHAR(20)   NOT NULL
                    CHECK (unit_of_measure IN ('Meters','Units','Boxes','Rolls')),
    warehouse_stock NUMERIC(10,2) NOT NULL DEFAULT 0.00
                    CHECK (warehouse_stock >= 0)
);


-- SECTION 3: TRANSACTIONAL TABLES

-- Work orders (service requests coming from the ISP)
CREATE TABLE work_orders (
    request_number       VARCHAR(20)   PRIMARY KEY,
    technician_id        INT           NOT NULL REFERENCES technicians (technician_id),
    account_holder       VARCHAR(100)  NOT NULL,
    line_number          VARCHAR(15),
    service_order        VARCHAR(100)  NOT NULL,
    technology_type      VARCHAR(20)   NOT NULL,
    primary_contact      VARCHAR(9)    NOT NULL,
    secondary_contact    VARCHAR(9),
    install_address      VARCHAR(200)  NOT NULL,
    technician_fee       NUMERIC(10,2) NOT NULL DEFAULT 0.00 CHECK (technician_fee >= 0),
    order_date           DATE          NOT NULL DEFAULT CURRENT_DATE,
    -- 'Escalated' = worked but not put in service yet (ghost-equipment state)
    order_status         VARCHAR(20)   NOT NULL DEFAULT 'Pending',

    CONSTRAINT ck_work_orders_primary_contact CHECK (
        primary_contact ~ '^[0-9]{4}-[0-9]{4}$'
    ),
    CONSTRAINT ck_work_orders_secondary_contact CHECK (
        secondary_contact IS NULL OR secondary_contact ~ '^[0-9]{4}-[0-9]{4}$'
    ),
    CONSTRAINT ck_work_orders_technology_type CHECK (
        technology_type IN ('Copper','HFC','Fiber','DTH','Satellite')
    ),
    CONSTRAINT ck_work_orders_status CHECK (
        order_status IN ('Pending','In Progress','Escalated','Completed','Cancelled')
    )
);

-- Prevents two open orders sharing the same line number (filtered unique index)
CREATE UNIQUE INDEX ux_work_orders_open_line
    ON work_orders (line_number)
    WHERE line_number IS NOT NULL AND order_status IN ('Pending','In Progress');

-- Invoices (warehouse dispatch notes)
CREATE TABLE invoices (
    invoice_number    INT           GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    invoice_date      DATE          NOT NULL DEFAULT CURRENT_DATE,
    technician_id     INT           NOT NULL REFERENCES technicians (technician_id),
    warehouse_user_id INT           NOT NULL REFERENCES users (user_id),
    notes             VARCHAR(200)
);

-- Equipment assignment lines (1 row = 1 serialized unit handed to a technician)
CREATE TABLE equipment_assignments (
    assignment_id    INT          GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    invoice_number   INT          NOT NULL REFERENCES invoices (invoice_number),
    serial_number    VARCHAR(50)  NOT NULL REFERENCES serialized_equipment (serial_number),
    quantity         INT          NOT NULL DEFAULT 1 CHECK (quantity = 1),
    -- 90-day custody deadline; not auto-computed, set by the dispatch routine
    expires_on       DATE         NOT NULL,
    assignment_status VARCHAR(12) NOT NULL DEFAULT 'Active'
                     CHECK (assignment_status IN ('Active','Expired','Returned','Transferred'))
);

-- A unit can only have ONE active assignment at a time
CREATE UNIQUE INDEX ux_equipment_assignments_active_serial
    ON equipment_assignments (serial_number)
    WHERE assignment_status = 'Active';

CREATE INDEX ix_equipment_assignments_expires_on
    ON equipment_assignments (expires_on)
    WHERE assignment_status = 'Active';

-- Material assignment lines (variable quantities)
CREATE TABLE material_assignments (
    assignment_id   INT           GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    invoice_number  INT           NOT NULL REFERENCES invoices (invoice_number),
    material_code   VARCHAR(15)   NOT NULL REFERENCES materials (material_code),
    quantity        NUMERIC(10,2) NOT NULL CHECK (quantity > 0)
);

-- Installation detail: closes the cycle Assignment -> Installation -> Discharge
CREATE TABLE installation_details (
    detail_id        INT           GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    request_number   VARCHAR(20)   NOT NULL REFERENCES work_orders (request_number),
    technician_id    INT           NOT NULL REFERENCES technicians (technician_id),
    installed_on     DATE          NOT NULL,
    serial_number    VARCHAR(50)   REFERENCES serialized_equipment (serial_number),
    material_code    VARCHAR(15)   REFERENCES materials (material_code),
    quantity_used    NUMERIC(10,2),
    warehouse_validated BOOLEAN    NOT NULL DEFAULT FALSE,

    -- A detail row must reference either a unit or a material
    CONSTRAINT ck_installation_details_has_content CHECK (
        serial_number IS NOT NULL OR material_code IS NOT NULL
    ),
    -- If it is a material, quantity is mandatory and positive
    CONSTRAINT ck_installation_details_material_qty CHECK (
        material_code IS NULL OR quantity_used > 0
    )
);

-- Fault / warranty visits (post-installation support)
CREATE TABLE warranty_visits (
    ticket_number        VARCHAR(20)   PRIMARY KEY,
    request_number       VARCHAR(20)   NOT NULL REFERENCES work_orders (request_number),
    technician_id        INT           NOT NULL REFERENCES technicians (technician_id),
    visit_date           DATE          NOT NULL,
    reported_problem     VARCHAR(200)  NOT NULL,
    technician_comment   VARCHAR(200),
    visit_type           VARCHAR(20)   NOT NULL,
    installed_serial     VARCHAR(50)   REFERENCES serialized_equipment (serial_number),
    removed_serial       VARCHAR(50)   REFERENCES serialized_equipment (serial_number),
    material_code        VARCHAR(15)   REFERENCES materials (material_code),
    material_quantity    NUMERIC(10,2),

    CONSTRAINT ck_warranty_visits_visit_type CHECK (
        visit_type IN ('Software Support','Equipment Swap','Material Use','Swap And Material')
    ),
    -- Composite CHECK keeps visit_type coherent with the inventory columns
    CONSTRAINT ck_warranty_visits_inventory_coherence CHECK (
        (visit_type = 'Software Support'
            AND installed_serial IS NULL AND removed_serial IS NULL
            AND material_code IS NULL AND material_quantity IS NULL)
        OR (visit_type = 'Equipment Swap'
            AND installed_serial IS NOT NULL
            AND material_code IS NULL AND material_quantity IS NULL)
        OR (visit_type = 'Material Use'
            AND installed_serial IS NULL AND removed_serial IS NULL
            AND material_code IS NOT NULL AND material_quantity > 0)
        OR (visit_type = 'Swap And Material'
            AND installed_serial IS NOT NULL
            AND material_code IS NOT NULL AND material_quantity > 0)
    )
);

-- Inventory returns (technician hands stock back to the warehouse)
CREATE TABLE inventory_returns (
    return_id         INT           GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    return_date       DATE          NOT NULL DEFAULT CURRENT_DATE,
    technician_id     INT           NOT NULL REFERENCES technicians (technician_id),
    warehouse_user_id INT           NOT NULL REFERENCES users (user_id),
    serial_number     VARCHAR(50)   REFERENCES serialized_equipment (serial_number),
    material_code     VARCHAR(15)   REFERENCES materials (material_code),
    returned_quantity NUMERIC(10,2),
    item_condition    VARCHAR(20)   NOT NULL,

    CONSTRAINT ck_inventory_returns_has_content CHECK (
        serial_number IS NOT NULL OR material_code IS NOT NULL
    ),
    CONSTRAINT ck_inventory_returns_condition CHECK (
        item_condition IN ('Good/Surplus','Factory Defect','Damaged In Use')
    ),
    CONSTRAINT ck_inventory_returns_material_qty CHECK (
        material_code IS NULL OR returned_quantity > 0
    )
);

-- Equipment transfers between technicians (added in design v2.0)
CREATE TABLE equipment_transfers (
    transfer_id            INT          GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    serial_number          VARCHAR(50)  NOT NULL REFERENCES serialized_equipment (serial_number),
    source_technician_id   INT          NOT NULL REFERENCES technicians (technician_id),
    target_technician_id   INT          NOT NULL REFERENCES technicians (technician_id),
    transferred_at         TIMESTAMP    NOT NULL DEFAULT now(),
    transfer_reason        VARCHAR(50)  NOT NULL,
    source_assignment_id   INT          NOT NULL REFERENCES equipment_assignments (assignment_id),
    target_assignment_id   INT          NOT NULL REFERENCES equipment_assignments (assignment_id),
    authorized_by_user_id  INT          NOT NULL REFERENCES users (user_id),
    notes                  VARCHAR(200),

    CONSTRAINT ck_equipment_transfers_reason CHECK (
        transfer_reason IN (
            'Near Expiry','Technician No Longer Needs','Crew Reassignment',
            'Requested By Target','Other'
        )
    ),
    -- Transferring a unit to oneself makes no sense
    CONSTRAINT ck_equipment_transfers_distinct_techs CHECK (
        source_technician_id <> target_technician_id
    )
);

CREATE INDEX ix_equipment_transfers_serial  ON equipment_transfers (serial_number);
CREATE INDEX ix_equipment_transfers_source  ON equipment_transfers (source_technician_id, transferred_at DESC);
CREATE INDEX ix_equipment_transfers_target  ON equipment_transfers (target_technician_id, transferred_at DESC);


-- SECTION 4: AUDITING

-- Append-only audit log. Intentionally has NO foreign keys: it must survive
-- even if the referenced rows are later removed, and it spans many tables.
CREATE TABLE audit_log (
    audit_id        BIGINT       GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    logged_at       TIMESTAMP    NOT NULL DEFAULT now(),
    affected_table  VARCHAR(50)  NOT NULL,
    operation       CHAR(1)      NOT NULL CHECK (operation IN ('I','U','D')), -- Insert/Update/Delete
    record_id       VARCHAR(50)  NOT NULL,
    changed_field   VARCHAR(50),
    old_value       VARCHAR(500),
    new_value       VARCHAR(500),
    user_login      VARCHAR(20)  NOT NULL,
    ip_address      VARCHAR(45)
);


-- SECTION 5: SUPPORTING INDEXES

CREATE INDEX ix_audit_log_table_date ON audit_log (affected_table, logged_at DESC);
CREATE INDEX ix_audit_log_user       ON audit_log (user_login, logged_at DESC);

CREATE INDEX ix_equipment_assignments_invoice ON equipment_assignments (invoice_number);
CREATE INDEX ix_equipment_assignments_serial  ON equipment_assignments (serial_number);
CREATE INDEX ix_material_assignments_invoice  ON material_assignments (invoice_number);

CREATE INDEX ix_warranty_visits_request       ON warranty_visits (request_number);

CREATE INDEX ix_installation_details_request  ON installation_details (request_number);
CREATE INDEX ix_installation_details_tech     ON installation_details (technician_id);

CREATE INDEX ix_inventory_returns_tech        ON inventory_returns (technician_id);
CREATE INDEX ix_invoices_technician           ON invoices (technician_id);

CREATE INDEX ix_user_roles_role               ON user_roles (role_id);
CREATE INDEX ix_role_permissions_permission   ON role_permissions (permission_id);

-- Filtered index: only users that are also technicians
CREATE INDEX ix_users_technician ON users (technician_id) WHERE technician_id IS NOT NULL;

-- SECTION B  -  ROUTINES

-- PROCONTEL - Stored routines (functions & procedures)
-- PostgreSQL 14+. Port of the original T-SQL stored procedures.
--
-- Design notes for reviewers:
--   * Routines that RETURN result sets are FUNCTIONS (... RETURNS TABLE / SETOF).
--   * Routines that only mutate state are PROCEDURES (CALLable, no return).
--   * Table-valued parameters from SQL Server are replaced by arrays of
--     composite types (see SECTION 0).
--   * Error handling uses RAISE EXCEPTION with SQLSTATE; multi-table writes run
--     inside the implicit routine transaction and roll back on any exception.
--   * The audit helper writes to audit_log; SECURITY/business routines call it.


-- SECTION 0: COMPOSITE TYPES (replacement for SQL Server TVPs)

-- A list of serialized units (e.g. equipment handed out on an invoice)
CREATE TYPE serial_item AS (
    serial_number VARCHAR(50)
);

-- A list of materials with a quantity
CREATE TYPE material_item AS (
    material_code VARCHAR(15),
    quantity      NUMERIC(10,2)
);


-- SECTION 1: AUDIT HELPER

-- Central helper every write routine calls to leave a trace in audit_log.
CREATE PROCEDURE sp_write_audit(
    p_affected_table VARCHAR(50),
    p_operation      CHAR(1),
    p_record_id      VARCHAR(50),
    p_user_login     VARCHAR(20),
    p_changed_field  VARCHAR(50)  DEFAULT NULL,
    p_old_value      VARCHAR(500) DEFAULT NULL,
    p_new_value      VARCHAR(500) DEFAULT NULL,
    p_ip_address     VARCHAR(45)  DEFAULT NULL
)
LANGUAGE plpgsql
AS $$
BEGIN
    INSERT INTO audit_log (
        affected_table, operation, record_id,
        changed_field, old_value, new_value, user_login, ip_address
    )
    VALUES (
        p_affected_table, p_operation, p_record_id,
        p_changed_field, p_old_value, p_new_value, p_user_login, p_ip_address
    );
END;
$$;


-- SECTION 2: SECURITY & RBAC

-- Authenticate a user. Returns the account row if valid; raises otherwise.
-- Deliberately does not reveal whether the login or the password was wrong.
CREATE FUNCTION fn_authenticate_user(
    p_login         VARCHAR(20),
    p_password_hash VARCHAR(128)
)
RETURNS TABLE (
    user_id       INT,
    login         VARCHAR(20),
    first_name    VARCHAR(50),
    last_name     VARCHAR(50),
    technician_id INT,
    user_status   VARCHAR(15)
)
LANGUAGE plpgsql
AS $$
DECLARE
    v_user_id INT;
    v_status  VARCHAR(15);
BEGIN
    SELECT u.user_id, u.user_status
      INTO v_user_id, v_status
      FROM users u
     WHERE u.login = p_login
       AND u.password_hash = p_password_hash;

    IF v_user_id IS NULL THEN
        RAISE EXCEPTION 'Invalid credentials.' USING ERRCODE = '28000';
    END IF;

    IF v_status <> 'Active' THEN
        RAISE EXCEPTION 'User is inactive or locked.' USING ERRCODE = '28000';
    END IF;

    UPDATE users SET last_login_at = now() WHERE users.user_id = v_user_id;

    RETURN QUERY
        SELECT u.user_id, u.login, u.first_name, u.last_name,
               u.technician_id, u.user_status
          FROM users u
         WHERE u.user_id = v_user_id;
END;
$$;

-- Change a password after validating the current one.
CREATE PROCEDURE sp_change_password(
    p_login        VARCHAR(20),
    p_current_hash VARCHAR(128),
    p_new_hash     VARCHAR(128)
)
LANGUAGE plpgsql
AS $$
DECLARE
    v_user_id INT;
BEGIN
    SELECT u.user_id INTO v_user_id
      FROM users u
     WHERE u.login = p_login
       AND u.password_hash = p_current_hash
       AND u.user_status = 'Active';

    IF v_user_id IS NULL THEN
        RAISE EXCEPTION 'Current password is wrong or user is inactive.'
            USING ERRCODE = '28000';
    END IF;

    UPDATE users SET password_hash = p_new_hash WHERE user_id = v_user_id;

    CALL sp_write_audit('users', 'U', v_user_id::TEXT, p_login,
                        'password_hash', '***', '***');
END;
$$;

-- Effective permissions of a user (union across all active roles).
-- Most-called routine: the app caches these at login.
CREATE FUNCTION fn_user_permissions(p_user_id INT)
RETURNS TABLE (
    permission_id   INT,
    permission_code VARCHAR(50),
    module          VARCHAR(50),
    description     VARCHAR(200)
)
LANGUAGE sql
AS $$
    SELECT DISTINCT p.permission_id, p.permission_code, p.module, p.description
      FROM users u
      JOIN user_roles ur      ON ur.user_id = u.user_id
      JOIN roles r            ON r.role_id = ur.role_id
      JOIN role_permissions rp ON rp.role_id = r.role_id
      JOIN permissions p      ON p.permission_id = rp.permission_id
     WHERE u.user_id = p_user_id
       AND u.user_status = 'Active'
       AND r.role_status = 'Active'
     ORDER BY p.module, p.permission_code;
$$;

-- Change history of a single record.
CREATE FUNCTION fn_audit_by_record(
    p_affected_table VARCHAR(50),
    p_record_id      VARCHAR(50)
)
RETURNS SETOF audit_log
LANGUAGE sql
AS $$
    SELECT *
      FROM audit_log
     WHERE affected_table = p_affected_table
       AND record_id = p_record_id
     ORDER BY logged_at DESC;
$$;

-- Every action by a user within a date range.
CREATE FUNCTION fn_audit_by_user(
    p_user_login VARCHAR(20),
    p_from       DATE,
    p_to         DATE
)
RETURNS SETOF audit_log
LANGUAGE sql
AS $$
    SELECT *
      FROM audit_log
     WHERE user_login = p_user_login
       AND logged_at >= p_from
       AND logged_at <  (p_to + INTERVAL '1 day')
     ORDER BY logged_at DESC;
$$;

-- Create a role.
CREATE FUNCTION fn_create_role(
    p_role_name   VARCHAR(50),
    p_description VARCHAR(200),
    p_user_login  VARCHAR(20)
)
RETURNS INT
LANGUAGE plpgsql
AS $$
DECLARE
    v_role_id INT;
BEGIN
    INSERT INTO roles (role_name, description)
    VALUES (p_role_name, p_description)
    RETURNING role_id INTO v_role_id;

    CALL sp_write_audit('roles', 'I', v_role_id::TEXT, p_user_login,
                        NULL, NULL, p_role_name);
    RETURN v_role_id;
END;
$$;

-- List all roles.
CREATE FUNCTION fn_list_roles()
RETURNS SETOF roles
LANGUAGE sql
AS $$
    SELECT * FROM roles ORDER BY role_name;
$$;

-- Assign a role to a user (N:M). Rejects duplicates.
CREATE PROCEDURE sp_assign_role_to_user(
    p_user_id    INT,
    p_role_id    INT,
    p_user_login VARCHAR(20)
)
LANGUAGE plpgsql
AS $$
BEGIN
    IF EXISTS (SELECT 1 FROM user_roles
                WHERE user_id = p_user_id AND role_id = p_role_id) THEN
        RAISE EXCEPTION 'User already holds this role.' USING ERRCODE = '23505';
    END IF;

    INSERT INTO user_roles (user_id, role_id) VALUES (p_user_id, p_role_id);

    CALL sp_write_audit('user_roles', 'I',
                        p_user_id::TEXT || '-' || p_role_id::TEXT,
                        p_user_login);
END;
$$;

-- Remove a role from a user.
CREATE PROCEDURE sp_remove_role_from_user(
    p_user_id    INT,
    p_role_id    INT,
    p_user_login VARCHAR(20)
)
LANGUAGE plpgsql
AS $$
BEGIN
    DELETE FROM user_roles WHERE user_id = p_user_id AND role_id = p_role_id;

    CALL sp_write_audit('user_roles', 'D',
                        p_user_id::TEXT || '-' || p_role_id::TEXT,
                        p_user_login);
END;
$$;

-- Roles currently held by a user.
CREATE FUNCTION fn_roles_of_user(p_user_id INT)
RETURNS TABLE (role_id INT, role_name VARCHAR(50), assigned_at TIMESTAMP)
LANGUAGE sql
AS $$
    SELECT r.role_id, r.role_name, ur.assigned_at
      FROM user_roles ur
      JOIN roles r ON r.role_id = ur.role_id
     WHERE ur.user_id = p_user_id
     ORDER BY r.role_name;
$$;

-- Grant a permission to a role. Rejects duplicates.
CREATE PROCEDURE sp_grant_permission_to_role(
    p_role_id       INT,
    p_permission_id INT,
    p_user_login    VARCHAR(20)
)
LANGUAGE plpgsql
AS $$
BEGIN
    IF EXISTS (SELECT 1 FROM role_permissions
                WHERE role_id = p_role_id AND permission_id = p_permission_id) THEN
        RAISE EXCEPTION 'Role already has this permission.' USING ERRCODE = '23505';
    END IF;

    INSERT INTO role_permissions (role_id, permission_id)
    VALUES (p_role_id, p_permission_id);

    CALL sp_write_audit('role_permissions', 'I',
                        p_role_id::TEXT || '-' || p_permission_id::TEXT,
                        p_user_login);
END;
$$;

-- List the permission catalog.
CREATE FUNCTION fn_list_permissions()
RETURNS SETOF permissions
LANGUAGE sql
AS $$
    SELECT * FROM permissions ORDER BY module, permission_code;
$$;
-- PROCONTEL - Stored routines, part 2: master-catalog CRUD
-- (technicians, users, serialized equipment, materials)


-- SECTION 3: TECHNICIANS

-- Insert a technician; returns the new internal id.
CREATE FUNCTION fn_create_technician(
    p_crew_code        VARCHAR(10),
    p_national_id      VARCHAR(10),
    p_first_name       VARCHAR(50),
    p_last_name        VARCHAR(50),
    p_phone            VARCHAR(9),
    p_blood_type       VARCHAR(3),
    p_marital_status   VARCHAR(15),
    p_birth_date       DATE,
    p_gender           VARCHAR(10),
    p_user_login       VARCHAR(20),
    p_address          VARCHAR(150) DEFAULT NULL,
    p_license_type     VARCHAR(15)  DEFAULT NULL,
    p_employment_status VARCHAR(15) DEFAULT 'Active'
)
RETURNS INT
LANGUAGE plpgsql
AS $$
DECLARE
    v_id INT;
BEGIN
    INSERT INTO technicians (
        crew_code, national_id, first_name, last_name, address, phone,
        blood_type, marital_status, birth_date, gender, license_type,
        employment_status
    )
    VALUES (
        p_crew_code, p_national_id, p_first_name, p_last_name, p_address, p_phone,
        p_blood_type, p_marital_status, p_birth_date, p_gender, p_license_type,
        p_employment_status
    )
    RETURNING technician_id INTO v_id;

    CALL sp_write_audit('technicians', 'I', v_id::TEXT, p_user_login,
                        NULL, NULL, p_crew_code);
    RETURN v_id;
END;
$$;

-- Update mutable technician fields (crew_code and national_id are fixed).
CREATE PROCEDURE sp_update_technician(
    p_technician_id  INT,
    p_first_name     VARCHAR(50),
    p_last_name      VARCHAR(50),
    p_phone          VARCHAR(9),
    p_blood_type     VARCHAR(3),
    p_marital_status VARCHAR(15),
    p_gender         VARCHAR(10),
    p_user_login     VARCHAR(20),
    p_address        VARCHAR(150) DEFAULT NULL,
    p_license_type   VARCHAR(15)  DEFAULT NULL
)
LANGUAGE plpgsql
AS $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM technicians WHERE technician_id = p_technician_id) THEN
        RAISE EXCEPTION 'Technician not found.' USING ERRCODE = 'P0002';
    END IF;

    UPDATE technicians
       SET first_name = p_first_name, last_name = p_last_name,
           address = p_address, phone = p_phone, blood_type = p_blood_type,
           marital_status = p_marital_status, gender = p_gender,
           license_type = p_license_type
     WHERE technician_id = p_technician_id;

    CALL sp_write_audit('technicians', 'U', p_technician_id::TEXT, p_user_login);
END;
$$;

-- Change a technician's employment status.
CREATE PROCEDURE sp_set_technician_employment_status(
    p_technician_id INT,
    p_new_status    VARCHAR(15),
    p_user_login    VARCHAR(20)
)
LANGUAGE plpgsql
AS $$
DECLARE
    v_old VARCHAR(15);
BEGIN
    SELECT employment_status INTO v_old
      FROM technicians WHERE technician_id = p_technician_id;

    IF v_old IS NULL THEN
        RAISE EXCEPTION 'Technician not found.' USING ERRCODE = 'P0002';
    END IF;

    UPDATE technicians SET employment_status = p_new_status
     WHERE technician_id = p_technician_id;

    CALL sp_write_audit('technicians', 'U', p_technician_id::TEXT, p_user_login,
                        'employment_status', v_old, p_new_status);
END;
$$;

CREATE FUNCTION fn_technician_by_id(p_technician_id INT)
RETURNS SETOF technicians LANGUAGE sql AS $$
    SELECT * FROM technicians WHERE technician_id = p_technician_id;
$$;

CREATE FUNCTION fn_technician_by_national_id(p_national_id VARCHAR(10))
RETURNS SETOF technicians LANGUAGE sql AS $$
    SELECT * FROM technicians WHERE national_id = p_national_id;
$$;

-- Active technicians, for UI dropdowns.
CREATE FUNCTION fn_list_active_technicians()
RETURNS TABLE (technician_id INT, crew_code VARCHAR(10),
               first_name VARCHAR(50), last_name VARCHAR(50), phone VARCHAR(9))
LANGUAGE sql AS $$
    SELECT technician_id, crew_code, first_name, last_name, phone
      FROM technicians
     WHERE employment_status = 'Active'
     ORDER BY crew_code;
$$;

-- General listing with an optional employment-status filter.
CREATE FUNCTION fn_list_technicians(p_employment_status VARCHAR(15) DEFAULT NULL)
RETURNS TABLE (technician_id INT, crew_code VARCHAR(10), national_id VARCHAR(10),
               first_name VARCHAR(50), last_name VARCHAR(50), phone VARCHAR(9),
               license_type VARCHAR(15), employment_status VARCHAR(15))
LANGUAGE sql AS $$
    SELECT technician_id, crew_code, national_id, first_name, last_name,
           phone, license_type, employment_status
      FROM technicians
     WHERE p_employment_status IS NULL OR employment_status = p_employment_status
     ORDER BY crew_code;
$$;


-- SECTION 4: USERS

-- Insert a user. The password arrives already hashed from the application.
CREATE FUNCTION fn_create_user(
    p_new_login     VARCHAR(20),
    p_password_hash VARCHAR(128),
    p_first_name    VARCHAR(50),
    p_last_name     VARCHAR(50),
    p_actor_login   VARCHAR(20),
    p_email         VARCHAR(100) DEFAULT NULL,
    p_technician_id INT          DEFAULT NULL
)
RETURNS INT
LANGUAGE plpgsql
AS $$
DECLARE
    v_id INT;
BEGIN
    INSERT INTO users (login, password_hash, first_name, last_name, email, technician_id)
    VALUES (p_new_login, p_password_hash, p_first_name, p_last_name, p_email, p_technician_id)
    RETURNING user_id INTO v_id;

    CALL sp_write_audit('users', 'I', v_id::TEXT, p_actor_login,
                        NULL, NULL, p_new_login);
    RETURN v_id;
END;
$$;

CREATE PROCEDURE sp_update_user(
    p_user_id     INT,
    p_first_name  VARCHAR(50),
    p_last_name   VARCHAR(50),
    p_actor_login VARCHAR(20),
    p_email       VARCHAR(100) DEFAULT NULL
)
LANGUAGE plpgsql
AS $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM users WHERE user_id = p_user_id) THEN
        RAISE EXCEPTION 'User not found.' USING ERRCODE = 'P0002';
    END IF;

    UPDATE users
       SET first_name = p_first_name, last_name = p_last_name, email = p_email
     WHERE user_id = p_user_id;

    CALL sp_write_audit('users', 'U', p_user_id::TEXT, p_actor_login);
END;
$$;

CREATE PROCEDURE sp_set_user_status(
    p_user_id     INT,
    p_new_status  VARCHAR(15),
    p_actor_login VARCHAR(20)
)
LANGUAGE plpgsql
AS $$
DECLARE
    v_old VARCHAR(15);
BEGIN
    SELECT user_status INTO v_old FROM users WHERE user_id = p_user_id;
    IF v_old IS NULL THEN
        RAISE EXCEPTION 'User not found.' USING ERRCODE = 'P0002';
    END IF;

    UPDATE users SET user_status = p_new_status WHERE user_id = p_user_id;

    CALL sp_write_audit('users', 'U', p_user_id::TEXT, p_actor_login,
                        'user_status', v_old, p_new_status);
END;
$$;

CREATE FUNCTION fn_user_by_id(p_user_id INT)
RETURNS TABLE (user_id INT, login VARCHAR(20), first_name VARCHAR(50),
               last_name VARCHAR(50), email VARCHAR(100),
               technician_id INT, user_status VARCHAR(15))
LANGUAGE sql AS $$
    SELECT user_id, login, first_name, last_name, email, technician_id, user_status
      FROM users WHERE user_id = p_user_id;
$$;

CREATE FUNCTION fn_list_active_users()
RETURNS TABLE (user_id INT, login VARCHAR(20), first_name VARCHAR(50),
               last_name VARCHAR(50), email VARCHAR(100))
LANGUAGE sql AS $$
    SELECT user_id, login, first_name, last_name, email
      FROM users WHERE user_status = 'Active' ORDER BY login;
$$;


-- SECTION 5: SERIALIZED EQUIPMENT

-- Receive one unit into the warehouse.
CREATE PROCEDURE sp_receive_equipment(
    p_serial_number VARCHAR(50),
    p_model         VARCHAR(100),
    p_device_type   VARCHAR(20),
    p_user_login    VARCHAR(20)
)
LANGUAGE plpgsql
AS $$
BEGIN
    INSERT INTO serialized_equipment (serial_number, model, device_type)
    VALUES (p_serial_number, p_model, p_device_type);

    CALL sp_write_audit('serialized_equipment', 'I', p_serial_number, p_user_login,
                        NULL, NULL, p_model);
END;
$$;

-- Receive a batch of units sharing model/type. Items is an array of serials.
CREATE PROCEDURE sp_receive_equipment_batch(
    p_serials     serial_item[],
    p_model       VARCHAR(100),
    p_device_type VARCHAR(20),
    p_user_login  VARCHAR(20)
)
LANGUAGE plpgsql
AS $$
DECLARE
    v_item serial_item;
BEGIN
    FOREACH v_item IN ARRAY p_serials LOOP
        INSERT INTO serialized_equipment (serial_number, model, device_type)
        VALUES (v_item.serial_number, p_model, p_device_type);
    END LOOP;

    CALL sp_write_audit('serialized_equipment', 'I',
                        'batch:' || cardinality(p_serials)::TEXT, p_user_login,
                        NULL, NULL, p_model);
END;
$$;

-- Change a unit's status (any direct status transition).
CREATE PROCEDURE sp_set_equipment_status(
    p_serial_number VARCHAR(50),
    p_new_status    VARCHAR(15),
    p_user_login    VARCHAR(20)
)
LANGUAGE plpgsql
AS $$
DECLARE
    v_old VARCHAR(15);
BEGIN
    SELECT equipment_status INTO v_old
      FROM serialized_equipment WHERE serial_number = p_serial_number;

    IF v_old IS NULL THEN
        RAISE EXCEPTION 'Equipment not found.' USING ERRCODE = 'P0002';
    END IF;

    UPDATE serialized_equipment SET equipment_status = p_new_status
     WHERE serial_number = p_serial_number;
    -- The status-change audit row is written by the trigger on this table.
END;
$$;

CREATE FUNCTION fn_equipment_by_serial(p_serial_number VARCHAR(50))
RETURNS SETOF serialized_equipment LANGUAGE sql AS $$
    SELECT * FROM serialized_equipment WHERE serial_number = p_serial_number;
$$;

CREATE FUNCTION fn_list_available_equipment()
RETURNS SETOF serialized_equipment LANGUAGE sql AS $$
    SELECT * FROM serialized_equipment
     WHERE equipment_status = 'Warehouse' ORDER BY device_type, model;
$$;

-- Units currently in custody of a technician (active assignments).
CREATE FUNCTION fn_list_equipment_by_technician(p_technician_id INT)
RETURNS TABLE (serial_number VARCHAR(50), model VARCHAR(100),
               device_type VARCHAR(20), expires_on DATE,
               assignment_status VARCHAR(12))
LANGUAGE sql AS $$
    SELECT ea.serial_number, se.model, se.device_type,
           ea.expires_on, ea.assignment_status
      FROM equipment_assignments ea
      JOIN invoices i             ON i.invoice_number = ea.invoice_number
      JOIN serialized_equipment se ON se.serial_number = ea.serial_number
     WHERE i.technician_id = p_technician_id
       AND ea.assignment_status IN ('Active','Expired')
     ORDER BY ea.expires_on;
$$;


-- SECTION 6: MATERIALS

CREATE PROCEDURE sp_create_material(
    p_material_code   VARCHAR(15),
    p_material_name   VARCHAR(100),
    p_unit_of_measure VARCHAR(20),
    p_user_login      VARCHAR(20),
    p_initial_stock   NUMERIC(10,2) DEFAULT 0
)
LANGUAGE plpgsql
AS $$
BEGIN
    INSERT INTO materials (material_code, material_name, unit_of_measure, warehouse_stock)
    VALUES (p_material_code, p_material_name, p_unit_of_measure, p_initial_stock);

    CALL sp_write_audit('materials', 'I', p_material_code, p_user_login,
                        NULL, NULL, p_material_name);
END;
$$;

CREATE PROCEDURE sp_update_material(
    p_material_code   VARCHAR(15),
    p_material_name   VARCHAR(100),
    p_unit_of_measure VARCHAR(20),
    p_user_login      VARCHAR(20)
)
LANGUAGE plpgsql
AS $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM materials WHERE material_code = p_material_code) THEN
        RAISE EXCEPTION 'Material not found.' USING ERRCODE = 'P0002';
    END IF;

    UPDATE materials
       SET material_name = p_material_name, unit_of_measure = p_unit_of_measure
     WHERE material_code = p_material_code;

    CALL sp_write_audit('materials', 'U', p_material_code, p_user_login);
END;
$$;

-- Manual stock adjustment (positive or negative). The stock-change audit row
-- is written by the trigger; this routine just guards against negative stock.
CREATE PROCEDURE sp_adjust_material_stock(
    p_material_code VARCHAR(15),
    p_delta         NUMERIC(10,2),
    p_user_login    VARCHAR(20)
)
LANGUAGE plpgsql
AS $$
DECLARE
    v_current NUMERIC(10,2);
BEGIN
    SELECT warehouse_stock INTO v_current
      FROM materials WHERE material_code = p_material_code FOR UPDATE;

    IF v_current IS NULL THEN
        RAISE EXCEPTION 'Material not found.' USING ERRCODE = 'P0002';
    END IF;

    IF v_current + p_delta < 0 THEN
        RAISE EXCEPTION 'Adjustment would drive stock below zero.' USING ERRCODE = '23514';
    END IF;

    UPDATE materials SET warehouse_stock = warehouse_stock + p_delta
     WHERE material_code = p_material_code;
END;
$$;

CREATE FUNCTION fn_material_by_code(p_material_code VARCHAR(15))
RETURNS SETOF materials LANGUAGE sql AS $$
    SELECT * FROM materials WHERE material_code = p_material_code;
$$;

CREATE FUNCTION fn_list_materials_with_stock()
RETURNS SETOF materials LANGUAGE sql AS $$
    SELECT * FROM materials ORDER BY material_name;
$$;

-- Materials below a threshold (default 10) for restock alerts.
CREATE FUNCTION fn_list_low_stock_materials(p_threshold NUMERIC DEFAULT 10)
RETURNS SETOF materials LANGUAGE sql AS $$
    SELECT * FROM materials
     WHERE warehouse_stock < p_threshold ORDER BY warehouse_stock;
$$;
-- PROCONTEL - Stored routines, part 3: transactional business logic
-- The interesting part of the project. These routines coordinate multiple
-- tables atomically: a failure anywhere raises an exception and the whole
-- routine's implicit transaction rolls back.
--
-- Business rules encoded here:
--   * Equipment handed to a technician carries a 90-day custody deadline.
--   * Work-order lifecycle is a state machine (incl. the 'Escalated' state for
--     orders worked but not yet put in service).
--   * Equipment can move technician-to-technician without passing through the
--     warehouse; the 90-day deadline is inherited, not reset.


-- SECTION 7: WORK ORDERS

-- Create a work order (always starts 'Pending').
CREATE PROCEDURE sp_create_work_order(
    p_request_number    VARCHAR(20),
    p_technician_id     INT,
    p_account_holder    VARCHAR(100),
    p_service_order     VARCHAR(100),
    p_technology_type   VARCHAR(20),
    p_primary_contact   VARCHAR(9),
    p_install_address   VARCHAR(200),
    p_user_login        VARCHAR(20),
    p_line_number       VARCHAR(15)   DEFAULT NULL,
    p_secondary_contact VARCHAR(9)    DEFAULT NULL,
    p_technician_fee    NUMERIC(10,2) DEFAULT 0
)
LANGUAGE plpgsql
AS $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM technicians
                    WHERE technician_id = p_technician_id
                      AND employment_status = 'Active') THEN
        RAISE EXCEPTION 'Technician not found or not active.' USING ERRCODE = 'P0002';
    END IF;

    INSERT INTO work_orders (
        request_number, technician_id, account_holder, line_number,
        service_order, technology_type, primary_contact, secondary_contact,
        install_address, technician_fee, order_status
    )
    VALUES (
        p_request_number, p_technician_id, p_account_holder, p_line_number,
        p_service_order, p_technology_type, p_primary_contact, p_secondary_contact,
        p_install_address, p_technician_fee, 'Pending'
    );

    CALL sp_write_audit('work_orders', 'I', p_request_number, p_user_login,
                        NULL, NULL, p_service_order);
END;
$$;

-- Reassign an order to another (active) technician.
CREATE PROCEDURE sp_reassign_work_order(
    p_request_number VARCHAR(20),
    p_new_technician INT,
    p_user_login     VARCHAR(20)
)
LANGUAGE plpgsql
AS $$
DECLARE
    v_old_tech INT;
BEGIN
    SELECT technician_id INTO v_old_tech
      FROM work_orders WHERE request_number = p_request_number;

    IF v_old_tech IS NULL THEN
        RAISE EXCEPTION 'Work order not found.' USING ERRCODE = 'P0002';
    END IF;

    IF NOT EXISTS (SELECT 1 FROM technicians
                    WHERE technician_id = p_new_technician
                      AND employment_status = 'Active') THEN
        RAISE EXCEPTION 'New technician not found or not active.' USING ERRCODE = 'P0002';
    END IF;

    UPDATE work_orders SET technician_id = p_new_technician
     WHERE request_number = p_request_number;

    CALL sp_write_audit('work_orders', 'U', p_request_number, p_user_login,
                        'technician_id', v_old_tech::TEXT, p_new_technician::TEXT);
END;
$$;

-- Work-order state machine. Allowed transitions:
--   Pending     -> In Progress, Escalated, Cancelled
--   In Progress -> Escalated, Completed, Cancelled
--   Escalated   -> In Progress, Completed
--   Completed / Cancelled are terminal.
CREATE PROCEDURE sp_change_order_status(
    p_request_number VARCHAR(20),
    p_new_status     VARCHAR(20),
    p_user_login     VARCHAR(20)
)
LANGUAGE plpgsql
AS $$
DECLARE
    v_old VARCHAR(20);
BEGIN
    SELECT order_status INTO v_old
      FROM work_orders WHERE request_number = p_request_number;

    IF v_old IS NULL THEN
        RAISE EXCEPTION 'Work order not found.' USING ERRCODE = 'P0002';
    END IF;

    IF v_old IN ('Completed','Cancelled') THEN
        RAISE EXCEPTION 'Order is in a terminal state and cannot change.'
            USING ERRCODE = '23514';
    END IF;

    IF v_old = 'Pending'     AND p_new_status NOT IN ('In Progress','Escalated','Cancelled')
       OR v_old = 'In Progress' AND p_new_status NOT IN ('Escalated','Completed','Cancelled')
       OR v_old = 'Escalated' AND p_new_status NOT IN ('In Progress','Completed') THEN
        RAISE EXCEPTION 'Invalid transition from % to %.', v_old, p_new_status
            USING ERRCODE = '23514';
    END IF;

    UPDATE work_orders SET order_status = p_new_status
     WHERE request_number = p_request_number;

    CALL sp_write_audit('work_orders', 'U', p_request_number, p_user_login,
                        'order_status', v_old, p_new_status);
END;
$$;

-- Convenience routine: escalate an order and record the reason in the log.
CREATE PROCEDURE sp_escalate_order(
    p_request_number VARCHAR(20),
    p_reason         VARCHAR(200),
    p_user_login     VARCHAR(20)
)
LANGUAGE plpgsql
AS $$
DECLARE
    v_old VARCHAR(20);
BEGIN
    SELECT order_status INTO v_old
      FROM work_orders WHERE request_number = p_request_number;

    IF v_old IS NULL THEN
        RAISE EXCEPTION 'Work order not found.' USING ERRCODE = 'P0002';
    END IF;

    IF v_old NOT IN ('Pending','In Progress') THEN
        RAISE EXCEPTION 'Can only escalate from Pending or In Progress.'
            USING ERRCODE = '23514';
    END IF;

    UPDATE work_orders SET order_status = 'Escalated'
     WHERE request_number = p_request_number;

    CALL sp_write_audit('work_orders', 'U', p_request_number, p_user_login,
                        'escalation_reason', v_old, p_reason);
END;
$$;

CREATE FUNCTION fn_order_by_number(p_request_number VARCHAR(20))
RETURNS SETOF work_orders LANGUAGE sql AS $$
    SELECT * FROM work_orders WHERE request_number = p_request_number;
$$;

CREATE FUNCTION fn_list_orders_by_technician(p_technician_id INT)
RETURNS SETOF work_orders LANGUAGE sql AS $$
    SELECT * FROM work_orders
     WHERE technician_id = p_technician_id ORDER BY order_date DESC;
$$;

CREATE FUNCTION fn_list_orders_by_status(p_status VARCHAR(20))
RETURNS SETOF work_orders LANGUAGE sql AS $$
    SELECT * FROM work_orders WHERE order_status = p_status ORDER BY order_date;
$$;

CREATE FUNCTION fn_list_open_orders_today()
RETURNS SETOF work_orders LANGUAGE sql AS $$
    SELECT * FROM work_orders
     WHERE order_status IN ('Pending','In Progress','Escalated')
       AND order_date = CURRENT_DATE
     ORDER BY technician_id;
$$;


-- SECTION 8: INVOICES (warehouse dispatch) -- COMPOSITE / TRANSACTIONAL

-- Dispatch equipment + materials to a technician in a single atomic operation.
-- Validates availability and stock, then creates the invoice and its lines,
-- flips equipment to 'Assigned', decrements stock, and sets the 90-day
-- custody deadline on each equipment line. Returns the new invoice number.
CREATE FUNCTION fn_create_full_invoice(
    p_technician_id     INT,
    p_warehouse_user_id INT,
    p_equipment         serial_item[],
    p_materials         material_item[],
    p_user_login        VARCHAR(20),
    p_notes             VARCHAR(200) DEFAULT NULL
)
RETURNS TABLE (invoice_number INT, expires_on DATE)
LANGUAGE plpgsql
AS $$
DECLARE
    v_invoice_number INT;
    v_expires_on     DATE := CURRENT_DATE + INTERVAL '90 days';
BEGIN
    -- Technician must be active
    IF NOT EXISTS (SELECT 1 FROM technicians
                    WHERE technician_id = p_technician_id
                      AND employment_status = 'Active') THEN
        RAISE EXCEPTION 'Technician not found or not active.' USING ERRCODE = 'P0002';
    END IF;

    -- Warehouse user must be active
    IF NOT EXISTS (SELECT 1 FROM users
                    WHERE user_id = p_warehouse_user_id
                      AND user_status = 'Active') THEN
        RAISE EXCEPTION 'Warehouse user not found or not active.' USING ERRCODE = 'P0002';
    END IF;

    -- Every unit must exist and be in the warehouse
    IF EXISTS (
        SELECT 1 FROM unnest(p_equipment) e
        LEFT JOIN serialized_equipment se ON se.serial_number = e.serial_number
        WHERE se.serial_number IS NULL OR se.equipment_status <> 'Warehouse'
    ) THEN
        RAISE EXCEPTION 'At least one unit is missing or not available in warehouse.'
            USING ERRCODE = '23514';
    END IF;

    -- Every material must exist and have enough stock
    IF EXISTS (
        SELECT 1 FROM unnest(p_materials) m
        LEFT JOIN materials mm ON mm.material_code = m.material_code
        WHERE mm.material_code IS NULL OR mm.warehouse_stock < m.quantity
    ) THEN
        RAISE EXCEPTION 'At least one material is missing or short on stock.'
            USING ERRCODE = '23514';
    END IF;

    -- 1) Invoice header
    INSERT INTO invoices (technician_id, warehouse_user_id, notes)
    VALUES (p_technician_id, p_warehouse_user_id, p_notes)
    RETURNING invoices.invoice_number INTO v_invoice_number;

    -- 2) Equipment lines (with the 90-day deadline)
    INSERT INTO equipment_assignments (invoice_number, serial_number, expires_on)
    SELECT v_invoice_number, e.serial_number, v_expires_on
      FROM unnest(p_equipment) e;

    -- 3) Material lines
    INSERT INTO material_assignments (invoice_number, material_code, quantity)
    SELECT v_invoice_number, m.material_code, m.quantity
      FROM unnest(p_materials) m;

    -- 4) Flip equipment to 'Assigned'
    UPDATE serialized_equipment se
       SET equipment_status = 'Assigned'
      FROM unnest(p_equipment) e
     WHERE se.serial_number = e.serial_number;

    -- 5) Decrement material stock
    UPDATE materials mm
       SET warehouse_stock = mm.warehouse_stock - m.quantity
      FROM unnest(p_materials) m
     WHERE mm.material_code = m.material_code;

    CALL sp_write_audit('invoices', 'I', v_invoice_number::TEXT, p_user_login);

    RETURN QUERY SELECT v_invoice_number, v_expires_on;
END;
$$;

-- Full invoice detail (header + equipment + materials), returned as JSON so a
-- single call hands the app everything it needs to render the document.
CREATE FUNCTION fn_full_invoice(p_invoice_number INT)
RETURNS JSONB
LANGUAGE sql
AS $$
    SELECT jsonb_build_object(
        'header', (SELECT to_jsonb(i) FROM invoices i WHERE i.invoice_number = p_invoice_number),
        'equipment', (SELECT COALESCE(jsonb_agg(to_jsonb(ea)), '[]')
                        FROM equipment_assignments ea WHERE ea.invoice_number = p_invoice_number),
        'materials', (SELECT COALESCE(jsonb_agg(to_jsonb(ma)), '[]')
                        FROM material_assignments ma WHERE ma.invoice_number = p_invoice_number)
    );
$$;

CREATE FUNCTION fn_list_invoices_by_technician(p_technician_id INT)
RETURNS SETOF invoices LANGUAGE sql AS $$
    SELECT * FROM invoices
     WHERE technician_id = p_technician_id ORDER BY invoice_date DESC;
$$;

CREATE FUNCTION fn_list_invoices_by_warehouse_user(p_warehouse_user_id INT)
RETURNS SETOF invoices LANGUAGE sql AS $$
    SELECT * FROM invoices
     WHERE warehouse_user_id = p_warehouse_user_id ORDER BY invoice_date DESC;
$$;

-- Void an invoice: reverses stock and equipment status, then deletes the lines.
-- Only allowed while none of the equipment has been installed.
CREATE PROCEDURE sp_void_invoice(
    p_invoice_number INT,
    p_user_login     VARCHAR(20)
)
LANGUAGE plpgsql
AS $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM invoices WHERE invoice_number = p_invoice_number) THEN
        RAISE EXCEPTION 'Invoice not found.' USING ERRCODE = 'P0002';
    END IF;

    IF EXISTS (
        SELECT 1 FROM equipment_assignments ea
         WHERE ea.invoice_number = p_invoice_number
           AND ea.assignment_status <> 'Active'
    ) THEN
        RAISE EXCEPTION 'Cannot void: some equipment already moved past Active.'
            USING ERRCODE = '23514';
    END IF;

    -- Return equipment to warehouse
    UPDATE serialized_equipment se
       SET equipment_status = 'Warehouse'
      FROM equipment_assignments ea
     WHERE ea.invoice_number = p_invoice_number
       AND se.serial_number = ea.serial_number;

    -- Restore material stock
    UPDATE materials mm
       SET warehouse_stock = mm.warehouse_stock + ma.quantity
      FROM material_assignments ma
     WHERE ma.invoice_number = p_invoice_number
       AND mm.material_code = ma.material_code;

    DELETE FROM equipment_assignments WHERE invoice_number = p_invoice_number;
    DELETE FROM material_assignments  WHERE invoice_number = p_invoice_number;
    DELETE FROM invoices              WHERE invoice_number = p_invoice_number;

    CALL sp_write_audit('invoices', 'D', p_invoice_number::TEXT, p_user_login);
END;
$$;


-- SECTION 9: EQUIPMENT EXPIRY & TRANSFERS (design v2.0)

-- Flip 'Active' assignments whose deadline has passed to 'Expired'. Meant to
-- run daily (cron / scheduler). Mutates nothing else; only raises UI alerts.
CREATE FUNCTION fn_mark_expired_equipment(p_user_login VARCHAR(20) DEFAULT 'SYSTEM')
RETURNS INT
LANGUAGE plpgsql
AS $$
DECLARE
    v_count INT;
BEGIN
    SELECT count(*) INTO v_count
      FROM equipment_assignments
     WHERE assignment_status = 'Active' AND expires_on < CURRENT_DATE;

    IF v_count = 0 THEN
        RETURN 0;
    END IF;

    -- Log before updating so the detail is captured
    INSERT INTO audit_log (affected_table, operation, record_id,
                           changed_field, old_value, new_value, user_login)
    SELECT 'equipment_assignments', 'U', ea.assignment_id::TEXT,
           'assignment_status', 'Active', 'Expired', p_user_login
      FROM equipment_assignments ea
     WHERE ea.assignment_status = 'Active' AND ea.expires_on < CURRENT_DATE;

    UPDATE equipment_assignments
       SET assignment_status = 'Expired'
     WHERE assignment_status = 'Active' AND expires_on < CURRENT_DATE;

    RETURN v_count;
END;
$$;

-- List equipment a technician holds that is near (or past) its deadline,
-- classified by urgency. Pass NULL technician for the whole fleet.
CREATE FUNCTION fn_list_equipment_due(
    p_technician_id INT DEFAULT NULL,
    p_max_days      INT DEFAULT 30
)
RETURNS TABLE (
    crew_code      VARCHAR(10),
    technician     TEXT,
    assignment_id  INT,
    serial_number  VARCHAR(50),
    model          VARCHAR(100),
    device_type    VARCHAR(20),
    invoice_number INT,
    invoice_date   DATE,
    expires_on     DATE,
    days_left      INT,
    assignment_status VARCHAR(12),
    alert_level    TEXT
)
LANGUAGE sql
AS $$
    SELECT
        t.crew_code,
        t.first_name || ' ' || t.last_name,
        ea.assignment_id,
        ea.serial_number,
        se.model,
        se.device_type,
        i.invoice_number,
        i.invoice_date,
        ea.expires_on,
        (ea.expires_on - CURRENT_DATE) AS days_left,
        ea.assignment_status,
        CASE
            WHEN ea.assignment_status = 'Expired'           THEN 'EXPIRED'
            WHEN ea.expires_on - CURRENT_DATE <= 7          THEN 'CRITICAL'
            WHEN ea.expires_on - CURRENT_DATE <= 15         THEN 'URGENT'
            WHEN ea.expires_on - CURRENT_DATE <= 30         THEN 'SOON'
            ELSE 'NORMAL'
        END
      FROM equipment_assignments ea
      JOIN invoices i              ON i.invoice_number = ea.invoice_number
      JOIN technicians t           ON t.technician_id = i.technician_id
      JOIN serialized_equipment se ON se.serial_number = ea.serial_number
     WHERE ea.assignment_status IN ('Active','Expired')
       AND (p_technician_id IS NULL OR i.technician_id = p_technician_id)
       AND (ea.expires_on - CURRENT_DATE) <= p_max_days
     ORDER BY ea.expires_on, t.crew_code;
$$;

-- The flagship composite routine: transfer a unit between technicians WITHOUT
-- passing through the warehouse. Closes the source assignment ('Transferred'),
-- opens a new one for the target that INHERITS the original deadline (the
-- 90-day clock does not restart), records the transfer, and audits it.
CREATE FUNCTION fn_transfer_equipment(
    p_serial_number     VARCHAR(50),
    p_source_technician INT,
    p_target_technician INT,
    p_reason            VARCHAR(50),
    p_authorized_by     INT,
    p_user_login        VARCHAR(20),
    p_notes             VARCHAR(200) DEFAULT NULL
)
RETURNS TABLE (transfer_id INT, new_assignment_id INT,
               transfer_invoice INT, inherited_expiry DATE)
LANGUAGE plpgsql
AS $$
DECLARE
    v_source_assignment INT;
    v_source_invoice    INT;
    v_inherited_expiry  DATE;
    v_target_invoice    INT;
    v_target_assignment INT;
    v_transfer_id       INT;
BEGIN
    IF p_source_technician = p_target_technician THEN
        RAISE EXCEPTION 'Cannot transfer to the same technician.' USING ERRCODE = '23514';
    END IF;

    IF NOT EXISTS (SELECT 1 FROM technicians
                    WHERE technician_id = p_source_technician AND employment_status = 'Active') THEN
        RAISE EXCEPTION 'Source technician not found or not active.' USING ERRCODE = 'P0002';
    END IF;

    IF NOT EXISTS (SELECT 1 FROM technicians
                    WHERE technician_id = p_target_technician AND employment_status = 'Active') THEN
        RAISE EXCEPTION 'Target technician not found or not active.' USING ERRCODE = 'P0002';
    END IF;

    IF NOT EXISTS (SELECT 1 FROM users
                    WHERE user_id = p_authorized_by AND user_status = 'Active') THEN
        RAISE EXCEPTION 'Authorizing user is not valid.' USING ERRCODE = 'P0002';
    END IF;

    -- Find the source's active/expired assignment for this unit
    SELECT ea.assignment_id, ea.invoice_number, ea.expires_on
      INTO v_source_assignment, v_source_invoice, v_inherited_expiry
      FROM equipment_assignments ea
      JOIN invoices i ON i.invoice_number = ea.invoice_number
     WHERE ea.serial_number = p_serial_number
       AND i.technician_id = p_source_technician
       AND ea.assignment_status IN ('Active','Expired')
     LIMIT 1;

    IF v_source_assignment IS NULL THEN
        RAISE EXCEPTION 'Unit is not currently assigned to the source technician.'
            USING ERRCODE = 'P0002';
    END IF;

    -- Close the source assignment
    UPDATE equipment_assignments SET assignment_status = 'Transferred'
     WHERE assignment_id = v_source_assignment;

    -- New "virtual" invoice for the target, tagged as a transfer for traceability
    INSERT INTO invoices (technician_id, warehouse_user_id, notes)
    VALUES (p_target_technician, p_authorized_by,
            'TRANSFER from invoice #' || v_source_invoice::TEXT
            || COALESCE(' - ' || p_notes, ''))
    RETURNING invoice_number INTO v_target_invoice;

    -- New assignment for the target, inheriting the original deadline
    INSERT INTO equipment_assignments (invoice_number, serial_number, expires_on)
    VALUES (v_target_invoice, p_serial_number, v_inherited_expiry)
    RETURNING assignment_id INTO v_target_assignment;

    -- Record the transfer
    INSERT INTO equipment_transfers (
        serial_number, source_technician_id, target_technician_id,
        transfer_reason, source_assignment_id, target_assignment_id,
        authorized_by_user_id, notes
    )
    VALUES (
        p_serial_number, p_source_technician, p_target_technician,
        p_reason, v_source_assignment, v_target_assignment,
        p_authorized_by, p_notes
    )
    RETURNING equipment_transfers.transfer_id INTO v_transfer_id;

    CALL sp_write_audit('equipment_transfers', 'I', v_transfer_id::TEXT, p_user_login,
                        'serial_number', p_serial_number, p_reason);

    RETURN QUERY SELECT v_transfer_id, v_target_assignment, v_target_invoice, v_inherited_expiry;
END;
$$;

-- Full custody chain of a unit (chain-of-custody report).
CREATE FUNCTION fn_transfer_history(p_serial_number VARCHAR(50))
RETURNS TABLE (
    transfer_id     INT,
    transferred_at  TIMESTAMP,
    source_crew     VARCHAR(10),
    source_tech     TEXT,
    target_crew     VARCHAR(10),
    target_tech     TEXT,
    transfer_reason VARCHAR(50),
    authorized_by   VARCHAR(20),
    notes           VARCHAR(200)
)
LANGUAGE sql
AS $$
    SELECT
        te.transfer_id, te.transferred_at,
        src.crew_code, src.first_name || ' ' || src.last_name,
        tgt.crew_code, tgt.first_name || ' ' || tgt.last_name,
        te.transfer_reason, u.login, te.notes
      FROM equipment_transfers te
      JOIN technicians src ON src.technician_id = te.source_technician_id
      JOIN technicians tgt ON tgt.technician_id = te.target_technician_id
      JOIN users u         ON u.user_id = te.authorized_by_user_id
     WHERE te.serial_number = p_serial_number
     ORDER BY te.transferred_at;
$$;


-- SECTION 10: LIQUIDATION / INSTALLATION DETAIL -- COMPOSITE

-- Declare what a technician actually installed on a job, in one atomic step.
-- Accepts orders in Pending / In Progress / Escalated (an escalated order that
-- finally goes into service must still be liquidatable). Marks units Installed,
-- closes their assignments, and completes the order.
CREATE PROCEDURE sp_register_liquidation(
    p_request_number   VARCHAR(20),
    p_technician_id    INT,
    p_installed_on     DATE,
    p_installed_equip  serial_item[],
    p_used_materials   material_item[],
    p_user_login       VARCHAR(20)
)
LANGUAGE plpgsql
AS $$
DECLARE
    v_status VARCHAR(20);
BEGIN
    SELECT order_status INTO v_status
      FROM work_orders WHERE request_number = p_request_number;

    IF v_status IS NULL THEN
        RAISE EXCEPTION 'Work order not found.' USING ERRCODE = 'P0002';
    END IF;

    IF v_status NOT IN ('Pending','In Progress','Escalated') THEN
        RAISE EXCEPTION 'Order is not in a valid state for liquidation.'
            USING ERRCODE = '23514';
    END IF;

    -- Each installed unit must be assigned (Active or Expired) to this technician
    IF EXISTS (
        SELECT 1 FROM unnest(p_installed_equip) ei
        WHERE NOT EXISTS (
            SELECT 1 FROM equipment_assignments ea
              JOIN invoices i ON i.invoice_number = ea.invoice_number
             WHERE ea.serial_number = ei.serial_number
               AND ea.assignment_status IN ('Active','Expired')
               AND i.technician_id = p_technician_id
        )
    ) THEN
        RAISE EXCEPTION 'At least one unit is not currently assigned to this technician.'
            USING ERRCODE = '23514';
    END IF;

    -- 1) Equipment installation rows
    INSERT INTO installation_details (request_number, technician_id, installed_on, serial_number)
    SELECT p_request_number, p_technician_id, p_installed_on, ei.serial_number
      FROM unnest(p_installed_equip) ei;

    -- 2) Material usage rows
    INSERT INTO installation_details (request_number, technician_id, installed_on, material_code, quantity_used)
    SELECT p_request_number, p_technician_id, p_installed_on, um.material_code, um.quantity
      FROM unnest(p_used_materials) um;

    -- 3) Units to 'Installed'
    UPDATE serialized_equipment se
       SET equipment_status = 'Installed'
      FROM unnest(p_installed_equip) ei
     WHERE se.serial_number = ei.serial_number;

    -- 4) Close those assignments (no longer in custody, now installed)
    UPDATE equipment_assignments ea
       SET assignment_status = 'Returned'
      FROM invoices i, unnest(p_installed_equip) ei
     WHERE i.invoice_number = ea.invoice_number
       AND ea.serial_number = ei.serial_number
       AND i.technician_id = p_technician_id
       AND ea.assignment_status IN ('Active','Expired');

    -- 5) Complete the order
    UPDATE work_orders SET order_status = 'Completed'
     WHERE request_number = p_request_number;

    CALL sp_write_audit('work_orders', 'U', p_request_number, p_user_login,
                        'order_status', v_status, 'Completed');
END;
$$;

-- Warehouse confirms a technician's declared installation.
CREATE PROCEDURE sp_validate_liquidation(
    p_detail_id  INT,
    p_user_login VARCHAR(20)
)
LANGUAGE plpgsql
AS $$
BEGIN
    UPDATE installation_details
       SET warehouse_validated = TRUE
     WHERE detail_id = p_detail_id;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Installation detail not found.' USING ERRCODE = 'P0002';
    END IF;

    CALL sp_write_audit('installation_details', 'U', p_detail_id::TEXT, p_user_login,
                        'warehouse_validated', 'false', 'true');
END;
$$;

CREATE FUNCTION fn_order_detail(p_request_number VARCHAR(20))
RETURNS SETOF installation_details LANGUAGE sql AS $$
    SELECT * FROM installation_details
     WHERE request_number = p_request_number ORDER BY detail_id;
$$;

CREATE FUNCTION fn_list_pending_validation()
RETURNS SETOF installation_details LANGUAGE sql AS $$
    SELECT * FROM installation_details
     WHERE warehouse_validated = FALSE ORDER BY installed_on;
$$;

CREATE FUNCTION fn_list_liquidations_by_technician(p_technician_id INT)
RETURNS SETOF installation_details LANGUAGE sql AS $$
    SELECT * FROM installation_details
     WHERE technician_id = p_technician_id ORDER BY installed_on DESC;
$$;


-- SECTION 11: WARRANTY VISITS

-- Register a fault/warranty visit. The composite CHECK on warranty_visits keeps
-- the inventory columns coherent with visit_type.
CREATE PROCEDURE sp_register_warranty_visit(
    p_ticket_number     VARCHAR(20),
    p_request_number    VARCHAR(20),
    p_technician_id     INT,
    p_visit_date        DATE,
    p_reported_problem  VARCHAR(200),
    p_visit_type        VARCHAR(20),
    p_user_login        VARCHAR(20),
    p_technician_comment VARCHAR(200) DEFAULT NULL,
    p_installed_serial  VARCHAR(50)   DEFAULT NULL,
    p_removed_serial    VARCHAR(50)   DEFAULT NULL,
    p_material_code     VARCHAR(15)   DEFAULT NULL,
    p_material_quantity NUMERIC(10,2) DEFAULT NULL
)
LANGUAGE plpgsql
AS $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM work_orders WHERE request_number = p_request_number) THEN
        RAISE EXCEPTION 'Original work order not found.' USING ERRCODE = 'P0002';
    END IF;

    INSERT INTO warranty_visits (
        ticket_number, request_number, technician_id, visit_date,
        reported_problem, technician_comment, visit_type,
        installed_serial, removed_serial, material_code, material_quantity
    )
    VALUES (
        p_ticket_number, p_request_number, p_technician_id, p_visit_date,
        p_reported_problem, p_technician_comment, p_visit_type,
        p_installed_serial, p_removed_serial, p_material_code, p_material_quantity
    );

    -- If a unit was swapped in, mark it Installed and decrement material stock
    IF p_installed_serial IS NOT NULL THEN
        UPDATE serialized_equipment SET equipment_status = 'Installed'
         WHERE serial_number = p_installed_serial;
    END IF;
    IF p_material_code IS NOT NULL THEN
        UPDATE materials SET warehouse_stock = warehouse_stock - p_material_quantity
         WHERE material_code = p_material_code;
    END IF;

    CALL sp_write_audit('warranty_visits', 'I', p_ticket_number, p_user_login,
                        NULL, NULL, p_visit_type);
END;
$$;

CREATE FUNCTION fn_warranty_by_order(p_request_number VARCHAR(20))
RETURNS SETOF warranty_visits LANGUAGE sql AS $$
    SELECT * FROM warranty_visits
     WHERE request_number = p_request_number ORDER BY visit_date DESC;
$$;

CREATE FUNCTION fn_list_warranty_by_technician(p_technician_id INT)
RETURNS SETOF warranty_visits LANGUAGE sql AS $$
    SELECT * FROM warranty_visits
     WHERE technician_id = p_technician_id ORDER BY visit_date DESC;
$$;

-- Visits still within the 90-day warranty window relative to the order date.
CREATE FUNCTION fn_list_warranty_within_window()
RETURNS TABLE (ticket_number VARCHAR(20), request_number VARCHAR(20),
               visit_date DATE, days_since_install INT)
LANGUAGE sql AS $$
    SELECT wv.ticket_number, wv.request_number, wv.visit_date,
           (wv.visit_date - wo.order_date) AS days_since_install
      FROM warranty_visits wv
      JOIN work_orders wo ON wo.request_number = wv.request_number
     WHERE (wv.visit_date - wo.order_date) <= 90
     ORDER BY wv.visit_date DESC;
$$;


-- SECTION 12: INVENTORY RETURNS

-- Technician returns stock to the warehouse. Equipment goes back to 'Warehouse'
-- (or 'Damaged'); materials add back to stock when reusable.
CREATE PROCEDURE sp_register_return(
    p_technician_id     INT,
    p_warehouse_user_id INT,
    p_item_condition    VARCHAR(20),
    p_user_login        VARCHAR(20),
    p_serial_number     VARCHAR(50)   DEFAULT NULL,
    p_material_code     VARCHAR(15)   DEFAULT NULL,
    p_returned_quantity NUMERIC(10,2) DEFAULT NULL
)
LANGUAGE plpgsql
AS $$
DECLARE
    v_return_id INT;
BEGIN
    IF p_serial_number IS NULL AND p_material_code IS NULL THEN
        RAISE EXCEPTION 'A return must reference a unit or a material.' USING ERRCODE = '23514';
    END IF;

    INSERT INTO inventory_returns (
        technician_id, warehouse_user_id, serial_number,
        material_code, returned_quantity, item_condition
    )
    VALUES (
        p_technician_id, p_warehouse_user_id, p_serial_number,
        p_material_code, p_returned_quantity, p_item_condition
    )
    RETURNING return_id INTO v_return_id;

    -- Equipment: damaged units go to 'Damaged', otherwise back to 'Warehouse'
    IF p_serial_number IS NOT NULL THEN
        UPDATE serialized_equipment
           SET equipment_status = CASE
                   WHEN p_item_condition IN ('Factory Defect','Damaged In Use')
                   THEN 'Damaged' ELSE 'Warehouse' END
         WHERE serial_number = p_serial_number;

        UPDATE equipment_assignments ea
           SET assignment_status = 'Returned'
          FROM invoices i
         WHERE i.invoice_number = ea.invoice_number
           AND ea.serial_number = p_serial_number
           AND i.technician_id = p_technician_id
           AND ea.assignment_status IN ('Active','Expired');
    END IF;

    -- Reusable materials add back to stock
    IF p_material_code IS NOT NULL AND p_item_condition = 'Good/Surplus' THEN
        UPDATE materials SET warehouse_stock = warehouse_stock + p_returned_quantity
         WHERE material_code = p_material_code;
    END IF;

    CALL sp_write_audit('inventory_returns', 'I', v_return_id::TEXT, p_user_login);
END;
$$;

CREATE FUNCTION fn_returns_by_technician(p_technician_id INT)
RETURNS SETOF inventory_returns LANGUAGE sql AS $$
    SELECT * FROM inventory_returns
     WHERE technician_id = p_technician_id ORDER BY return_date DESC;
$$;

CREATE FUNCTION fn_list_returns_by_warehouse_user(p_warehouse_user_id INT)
RETURNS SETOF inventory_returns LANGUAGE sql AS $$
    SELECT * FROM inventory_returns
     WHERE warehouse_user_id = p_warehouse_user_id ORDER BY return_date DESC;
$$;
-- PROCONTEL - Stored routines, part 4: management reports
-- Read-only reporting functions used by the desktop app and ad-hoc queries.
-- The BI layer (see 04_views.sql) covers dashboard needs; these target the
-- operational screens and audit defenses.


-- SECTION 13: REPORTS

-- Warehouse equipment on hand, grouped by device type.
CREATE FUNCTION fn_report_warehouse_equipment()
RETURNS TABLE (device_type VARCHAR(20), quantity BIGINT)
LANGUAGE sql AS $$
    SELECT device_type, count(*)
      FROM serialized_equipment
     WHERE equipment_status = 'Warehouse'
     GROUP BY device_type
     ORDER BY device_type;
$$;

-- Equipment currently held by technicians (active assignments) and by whom.
CREATE FUNCTION fn_report_equipment_in_field()
RETURNS TABLE (crew_code VARCHAR(10), technician TEXT, device_type VARCHAR(20),
               serial_number VARCHAR(50), model VARCHAR(100),
               invoice_number INT, invoice_date DATE)
LANGUAGE sql AS $$
    SELECT t.crew_code, t.first_name || ' ' || t.last_name,
           se.device_type, se.serial_number, se.model,
           i.invoice_number, i.invoice_date
      FROM equipment_assignments ea
      JOIN invoices i              ON i.invoice_number = ea.invoice_number
      JOIN technicians t           ON t.technician_id = i.technician_id
      JOIN serialized_equipment se ON se.serial_number = ea.serial_number
     WHERE ea.assignment_status = 'Active'
     ORDER BY t.crew_code, se.device_type;
$$;

-- Key audit-defense report: units assigned to a technician that are neither
-- installed nor returned (i.e. unexplained "ghost" equipment).
CREATE FUNCTION fn_report_technician_discrepancies(
    p_technician_id INT,
    p_from          DATE,
    p_to            DATE
)
RETURNS TABLE (serial_number VARCHAR(50), model VARCHAR(100),
               device_type VARCHAR(20), invoice_number INT,
               invoice_date DATE, equipment_status VARCHAR(15),
               assignment_status VARCHAR(12))
LANGUAGE sql AS $$
    SELECT ea.serial_number, se.model, se.device_type,
           i.invoice_number, i.invoice_date,
           se.equipment_status, ea.assignment_status
      FROM equipment_assignments ea
      JOIN invoices i              ON i.invoice_number = ea.invoice_number
      JOIN serialized_equipment se ON se.serial_number = ea.serial_number
     WHERE i.technician_id = p_technician_id
       AND i.invoice_date BETWEEN p_from AND p_to
       AND ea.assignment_status = 'Active'
       AND NOT EXISTS (
            SELECT 1 FROM installation_details d
             WHERE d.serial_number = ea.serial_number)
     ORDER BY i.invoice_date;
$$;

-- Productivity per technician over a date range.
CREATE FUNCTION fn_report_technician_productivity(p_from DATE, p_to DATE)
RETURNS TABLE (crew_code VARCHAR(10), technician TEXT,
               total_orders BIGINT, completed BIGINT, cancelled BIGINT,
               total_billed NUMERIC)
LANGUAGE sql AS $$
    SELECT t.crew_code, t.first_name || ' ' || t.last_name,
           count(o.request_number),
           count(*) FILTER (WHERE o.order_status = 'Completed'),
           count(*) FILTER (WHERE o.order_status = 'Cancelled'),
           COALESCE(sum(o.technician_fee) FILTER (WHERE o.order_status = 'Completed'), 0)
      FROM technicians t
      LEFT JOIN work_orders o
             ON o.technician_id = t.technician_id
            AND o.order_date BETWEEN p_from AND p_to
     GROUP BY t.crew_code, t.first_name, t.last_name
     ORDER BY t.crew_code;
$$;

-- Material consumption over a date range (from installation details).
CREATE FUNCTION fn_report_material_consumption(p_from DATE, p_to DATE)
RETURNS TABLE (material_code VARCHAR(15), material_name VARCHAR(100),
               unit_of_measure VARCHAR(20), total_used NUMERIC)
LANGUAGE sql AS $$
    SELECT mm.material_code, mm.material_name, mm.unit_of_measure,
           COALESCE(sum(d.quantity_used), 0) AS total_used
      FROM materials mm
      LEFT JOIN installation_details d
             ON d.material_code = mm.material_code
            AND d.installed_on BETWEEN p_from AND p_to
     GROUP BY mm.material_code, mm.material_name, mm.unit_of_measure
     ORDER BY COALESCE(sum(d.quantity_used), 0) DESC;
$$;

-- Liquidations still awaiting warehouse validation (operational bottleneck).
CREATE FUNCTION fn_report_pending_liquidations()
RETURNS TABLE (detail_id INT, request_number VARCHAR(20), installed_on DATE,
               days_waiting INT, crew_code VARCHAR(10), technician TEXT)
LANGUAGE sql AS $$
    SELECT d.detail_id, d.request_number, d.installed_on,
           (CURRENT_DATE - d.installed_on),
           t.crew_code, t.first_name || ' ' || t.last_name
      FROM installation_details d
      JOIN technicians t ON t.technician_id = d.technician_id
     WHERE d.warehouse_validated = FALSE
     ORDER BY d.installed_on;
$$;

-- Damaged equipment inventory.
CREATE FUNCTION fn_report_damaged_equipment()
RETURNS TABLE (serial_number VARCHAR(50), model VARCHAR(100),
               device_type VARCHAR(20), received_date DATE)
LANGUAGE sql AS $$
    SELECT serial_number, model, device_type, received_date
      FROM serialized_equipment
     WHERE equipment_status = 'Damaged'
     ORDER BY device_type, model;
$$;

-- End-to-end flow of a single invoice (header + lines), as JSON.
CREATE FUNCTION fn_report_invoice_flow(p_invoice_number INT)
RETURNS JSONB
LANGUAGE sql AS $$
    SELECT jsonb_build_object(
        'invoice',  (SELECT to_jsonb(i) FROM invoices i WHERE i.invoice_number = p_invoice_number),
        'equipment',(SELECT COALESCE(jsonb_agg(jsonb_build_object(
                        'serial', ea.serial_number,
                        'status', ea.assignment_status,
                        'expires_on', ea.expires_on))
                        , '[]')
                       FROM equipment_assignments ea WHERE ea.invoice_number = p_invoice_number),
        'materials',(SELECT COALESCE(jsonb_agg(jsonb_build_object(
                        'code', ma.material_code,
                        'quantity', ma.quantity))
                        , '[]')
                       FROM material_assignments ma WHERE ma.invoice_number = p_invoice_number)
    );
$$;

-- Audit movements within a date range, optionally filtered by table.
CREATE FUNCTION fn_report_audit_movements(
    p_from           DATE,
    p_to             DATE,
    p_affected_table VARCHAR(50) DEFAULT NULL
)
RETURNS SETOF audit_log
LANGUAGE sql AS $$
    SELECT *
      FROM audit_log
     WHERE logged_at >= p_from
       AND logged_at <  (p_to + INTERVAL '1 day')
       AND (p_affected_table IS NULL OR affected_table = p_affected_table)
     ORDER BY logged_at DESC;
$$;

-- SECTION C  -  TRIGGERS

-- PROCONTEL - Audit triggers
-- PostgreSQL splits a trigger into a trigger FUNCTION (the body) and the
-- CREATE TRIGGER that binds it to a table/event. These triggers capture the
-- "physical" state changes that matter most in audits, regardless of whether
-- the change came through a routine or a direct UPDATE.
--
-- current_user stands in for the SQL Server SUSER_SNAME() used originally.


-- Capture status changes on serialized_equipment.
CREATE FUNCTION trg_fn_equipment_status_audit()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
    IF NEW.equipment_status IS DISTINCT FROM OLD.equipment_status THEN
        INSERT INTO audit_log (affected_table, operation, record_id,
                               changed_field, old_value, new_value, user_login)
        VALUES ('serialized_equipment', 'U', NEW.serial_number,
                'equipment_status_TRG', OLD.equipment_status, NEW.equipment_status,
                current_user);
    END IF;
    RETURN NEW;
END;
$$;

CREATE TRIGGER trg_equipment_status_audit
    AFTER UPDATE OF equipment_status ON serialized_equipment
    FOR EACH ROW
    EXECUTE FUNCTION trg_fn_equipment_status_audit();


-- Capture stock changes on materials (the figure auditors question most).
CREATE FUNCTION trg_fn_material_stock_audit()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
    IF NEW.warehouse_stock IS DISTINCT FROM OLD.warehouse_stock THEN
        INSERT INTO audit_log (affected_table, operation, record_id,
                               changed_field, old_value, new_value, user_login)
        VALUES ('materials', 'U', NEW.material_code,
                'warehouse_stock_TRG',
                OLD.warehouse_stock::TEXT, NEW.warehouse_stock::TEXT,
                current_user);
    END IF;
    RETURN NEW;
END;
$$;

CREATE TRIGGER trg_material_stock_audit
    AFTER UPDATE OF warehouse_stock ON materials
    FOR EACH ROW
    EXECUTE FUNCTION trg_fn_material_stock_audit();


-- Capture order-status changes on work_orders (lets you rebuild each order's
-- timeline from the log for SLA reporting).
CREATE FUNCTION trg_fn_order_status_audit()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
    IF NEW.order_status IS DISTINCT FROM OLD.order_status THEN
        INSERT INTO audit_log (affected_table, operation, record_id,
                               changed_field, old_value, new_value, user_login)
        VALUES ('work_orders', 'U', NEW.request_number,
                'order_status_TRG', OLD.order_status, NEW.order_status,
                current_user);
    END IF;
    RETURN NEW;
END;
$$;

CREATE TRIGGER trg_order_status_audit
    AFTER UPDATE OF order_status ON work_orders
    FOR EACH ROW
    EXECUTE FUNCTION trg_fn_order_status_audit();

-- SECTION D  -  VIEWS

-- PROCONTEL - Analytical views (BI layer)
-- Views consumed by the BI tool. They are intentionally wide and partly
-- denormalized: a BI model prefers a few wide tables over many narrow ones.
--   * vw_dim_*   : dimension tables (slicers / filters)
--   * vw_fact_*  : one row per event (BI aggregates dynamically -> drill-down)
--   * vw_kpi_*   : pre-aggregated figures for dashboard cards


-- DIMENSIONS

-- Technician dimension enriched with computed age / age band.
CREATE VIEW vw_dim_technician AS
SELECT
    t.technician_id,
    t.crew_code,
    t.national_id,
    t.first_name || ' ' || t.last_name              AS full_name,
    t.gender,
    t.marital_status,
    t.blood_type,
    t.license_type,
    t.employment_status,
    t.birth_date,
    date_part('year', age(t.birth_date))::INT       AS age,
    CASE
        WHEN date_part('year', age(t.birth_date)) < 25 THEN '18-24'
        WHEN date_part('year', age(t.birth_date)) < 35 THEN '25-34'
        WHEN date_part('year', age(t.birth_date)) < 45 THEN '35-44'
        WHEN date_part('year', age(t.birth_date)) < 55 THEN '45-54'
        ELSE '55+'
    END                                             AS age_band,
    t.phone,
    t.address
FROM technicians t;

-- Equipment dimension with the technician currently holding each unit.
CREATE VIEW vw_dim_equipment AS
SELECT
    se.serial_number,
    se.model,
    se.device_type,
    se.equipment_status,
    se.received_date,
    (CURRENT_DATE - se.received_date)               AS days_in_system,
    t.technician_id                                 AS current_technician_id,
    t.crew_code                                     AS current_crew_code,
    t.first_name || ' ' || t.last_name              AS current_technician_name
FROM serialized_equipment se
LEFT JOIN equipment_assignments ea
       ON ea.serial_number = se.serial_number
      AND ea.assignment_status = 'Active'
LEFT JOIN invoices i    ON i.invoice_number = ea.invoice_number
LEFT JOIN technicians t ON t.technician_id = i.technician_id;


-- FACT TABLES (one row = one event)

-- One row per work order, with flattened date parts and measure flags.
CREATE VIEW vw_fact_orders AS
SELECT
    o.request_number,
    o.order_date,
    date_part('year',  o.order_date)::INT           AS year,
    date_part('month', o.order_date)::INT           AS month,
    to_char(o.order_date, 'Month')                  AS month_name,
    date_part('quarter', o.order_date)::INT         AS quarter,
    to_char(o.order_date, 'Day')                    AS weekday,
    o.order_status,
    o.technology_type,
    o.technician_fee,
    o.account_holder,
    o.install_address,
    t.technician_id,
    t.crew_code,
    t.first_name || ' ' || t.last_name              AS technician_name,
    (o.order_status = 'Completed')::INT             AS is_completed,
    (o.order_status = 'Cancelled')::INT             AS is_cancelled,
    (o.order_status IN ('Pending','In Progress','Escalated'))::INT AS is_open
FROM work_orders o
JOIN technicians t ON t.technician_id = o.technician_id;

-- One row per installation detail (equipment or material) at max granularity.
CREATE VIEW vw_fact_installations AS
SELECT
    d.detail_id,
    d.request_number,
    d.installed_on,
    date_part('year',  d.installed_on)::INT         AS year,
    date_part('month', d.installed_on)::INT         AS month,
    d.warehouse_validated,
    t.technician_id,
    t.crew_code,
    t.first_name || ' ' || t.last_name              AS technician_name,
    o.technology_type,
    d.serial_number,
    se.model                                        AS equipment_model,
    se.device_type,
    d.material_code,
    mm.material_name,
    mm.unit_of_measure,
    d.quantity_used,
    CASE
        WHEN d.serial_number IS NOT NULL THEN 'Equipment'
        WHEN d.material_code IS NOT NULL THEN 'Material'
    END                                             AS detail_type
FROM installation_details d
JOIN work_orders o            ON o.request_number = d.request_number
JOIN technicians t            ON t.technician_id = d.technician_id
LEFT JOIN serialized_equipment se ON se.serial_number = d.serial_number
LEFT JOIN materials mm        ON mm.material_code = d.material_code;

-- One row per warranty visit, with warranty-window classification.
CREATE VIEW vw_fact_warranty AS
SELECT
    wv.ticket_number,
    wv.request_number,
    wv.visit_date,
    date_part('year',  wv.visit_date)::INT          AS year,
    date_part('month', wv.visit_date)::INT          AS month,
    wv.visit_type,
    wv.reported_problem,
    wv.installed_serial,
    wv.removed_serial,
    wv.material_code,
    wv.material_quantity,
    t.crew_code,
    t.first_name || ' ' || t.last_name              AS technician_name,
    o.order_date                                    AS original_order_date,
    o.technology_type,
    (wv.visit_date - o.order_date)                  AS days_since_install,
    CASE WHEN (wv.visit_date - o.order_date) <= 90
         THEN 'Under Warranty' ELSE 'Out Of Warranty' END AS warranty_status
FROM warranty_visits wv
JOIN technicians t  ON t.technician_id = wv.technician_id
JOIN work_orders o  ON o.request_number = wv.request_number;

-- Consolidated inventory movements: each row is a dispatch or a return.
CREATE VIEW vw_fact_inventory_movements AS
SELECT
    'Dispatch'                                      AS movement_type,
    i.invoice_date                                  AS movement_date,
    date_part('year',  i.invoice_date)::INT         AS year,
    date_part('month', i.invoice_date)::INT         AS month,
    t.crew_code,
    t.first_name || ' ' || t.last_name              AS technician_name,
    ea.serial_number,
    NULL::VARCHAR(15)                               AS material_code,
    1::NUMERIC                                      AS quantity,
    NULL::VARCHAR(20)                               AS item_condition
FROM invoices i
JOIN technicians t           ON t.technician_id = i.technician_id
JOIN equipment_assignments ea ON ea.invoice_number = i.invoice_number

UNION ALL

SELECT
    'Dispatch',
    i.invoice_date,
    date_part('year',  i.invoice_date)::INT,
    date_part('month', i.invoice_date)::INT,
    t.crew_code,
    t.first_name || ' ' || t.last_name,
    NULL,
    ma.material_code,
    ma.quantity,
    NULL
FROM invoices i
JOIN technicians t            ON t.technician_id = i.technician_id
JOIN material_assignments ma  ON ma.invoice_number = i.invoice_number

UNION ALL

SELECT
    'Return',
    r.return_date,
    date_part('year',  r.return_date)::INT,
    date_part('month', r.return_date)::INT,
    t.crew_code,
    t.first_name || ' ' || t.last_name,
    r.serial_number,
    r.material_code,
    COALESCE(r.returned_quantity, 1),
    r.item_condition
FROM inventory_returns r
JOIN technicians t ON t.technician_id = r.technician_id;


-- KPI VIEWS (pre-aggregated for dashboard cards)

-- Inventory health: count by device type and status.
CREATE VIEW vw_kpi_inventory_global AS
SELECT device_type, equipment_status, count(*) AS quantity
FROM serialized_equipment
GROUP BY device_type, equipment_status;

-- Lifetime productivity per technician with a success rate.
CREATE VIEW vw_kpi_technician_productivity AS
SELECT
    t.technician_id,
    t.crew_code,
    t.first_name || ' ' || t.last_name              AS technician_name,
    t.employment_status,
    count(o.request_number)                         AS total_orders,
    count(*) FILTER (WHERE o.order_status = 'Completed') AS completed_orders,
    count(*) FILTER (WHERE o.order_status = 'Cancelled') AS cancelled_orders,
    count(*) FILTER (WHERE o.order_status IN ('Pending','In Progress','Escalated')) AS open_orders,
    COALESCE(sum(o.technician_fee) FILTER (WHERE o.order_status = 'Completed'), 0) AS total_billed,
    CASE
        WHEN count(*) FILTER (WHERE o.order_status IN ('Completed','Cancelled')) = 0 THEN NULL
        ELSE round(
            count(*) FILTER (WHERE o.order_status = 'Completed')::NUMERIC
            / count(*) FILTER (WHERE o.order_status IN ('Completed','Cancelled')), 2)
    END                                             AS success_rate
FROM technicians t
LEFT JOIN work_orders o ON o.technician_id = t.technician_id
GROUP BY t.technician_id, t.crew_code, t.first_name, t.last_name, t.employment_status;

-- Active discrepancies: assigned units not installed and not returned. The most
-- politically sensitive report -- the ISP asks for it at every audit.
CREATE VIEW vw_kpi_discrepancies AS
SELECT
    t.crew_code,
    t.first_name || ' ' || t.last_name              AS technician_name,
    ea.serial_number,
    se.model,
    se.device_type,
    i.invoice_number,
    i.invoice_date,
    (CURRENT_DATE - i.invoice_date)                 AS days_unresolved,
    CASE
        WHEN (CURRENT_DATE - i.invoice_date) <= 7  THEN '0-7 days'
        WHEN (CURRENT_DATE - i.invoice_date) <= 30 THEN '8-30 days'
        WHEN (CURRENT_DATE - i.invoice_date) <= 90 THEN '31-90 days'
        ELSE '90+ days'
    END                                             AS age_band
FROM equipment_assignments ea
JOIN invoices i              ON i.invoice_number = ea.invoice_number
JOIN technicians t           ON t.technician_id = i.technician_id
JOIN serialized_equipment se ON se.serial_number = ea.serial_number
WHERE ea.assignment_status = 'Active'
  AND NOT EXISTS (SELECT 1 FROM installation_details d
                   WHERE d.serial_number = ea.serial_number)
  AND NOT EXISTS (SELECT 1 FROM inventory_returns r
                   WHERE r.serial_number = ea.serial_number
                     AND r.technician_id = i.technician_id);

-- Material stock with a traffic-light level and rough days of cover.
CREATE VIEW vw_kpi_material_stock AS
SELECT
    mm.material_code,
    mm.material_name,
    mm.unit_of_measure,
    mm.warehouse_stock,
    COALESCE((
        SELECT sum(d.quantity_used) / 30.0
          FROM installation_details d
         WHERE d.material_code = mm.material_code
           AND d.installed_on >= CURRENT_DATE - INTERVAL '30 days'
    ), 0)                                           AS avg_daily_consumption,
    CASE
        WHEN COALESCE((
            SELECT sum(d.quantity_used) / 30.0
              FROM installation_details d
             WHERE d.material_code = mm.material_code
               AND d.installed_on >= CURRENT_DATE - INTERVAL '30 days'
        ), 0) = 0 THEN NULL
        ELSE mm.warehouse_stock / (
            SELECT sum(d.quantity_used) / 30.0
              FROM installation_details d
             WHERE d.material_code = mm.material_code
               AND d.installed_on >= CURRENT_DATE - INTERVAL '30 days')
    END                                             AS days_of_cover,
    CASE
        WHEN mm.warehouse_stock = 0  THEN 'Out Of Stock'
        WHEN mm.warehouse_stock < 10 THEN 'Critical'
        WHEN mm.warehouse_stock < 50 THEN 'Low'
        ELSE 'Normal'
    END                                             AS stock_level
FROM materials mm;

-- Liquidations pending warehouse validation (operational bottleneck card).
CREATE VIEW vw_kpi_pending_liquidations AS
SELECT
    d.detail_id,
    d.request_number,
    d.installed_on,
    (CURRENT_DATE - d.installed_on)                 AS days_pending,
    t.crew_code,
    t.first_name || ' ' || t.last_name              AS technician_name,
    d.serial_number,
    d.material_code,
    d.quantity_used,
    o.technology_type
FROM installation_details d
JOIN technicians t  ON t.technician_id = d.technician_id
JOIN work_orders o  ON o.request_number = d.request_number
WHERE d.warehouse_validated = FALSE;

-- SECTION E  -  RBAC SEED

-- PROCONTEL - RBAC seed data
-- System data (not test data): the five business roles, the atomic permission
-- catalog grouped by module, and the role->permission grants. Permission codes
-- follow a "Module.Action" convention so the app can check them by string.


-- ROLES (5 business roles)
INSERT INTO roles (role_name, description) VALUES
    ('Manager',        'General manager. Full system access, management reports, user administration.'),
    ('WarehouseLead',  'Warehouse lead. Inventory oversight, audit responses, CRUD on equipment/materials.'),
    ('WarehouseClerk', 'Warehouse clerk. Executes dispatches (invoices) and receives returns.'),
    ('Technician',     'Field technician. Sees only assigned orders and records own liquidations.'),
    ('Auditor',        'Auditor. Read-only access for internal or external review.');


-- PERMISSIONS (atomic, grouped by module)
INSERT INTO permissions (permission_code, module, description) VALUES
    -- Users
    ('User.Create',         'Users',     'Create system users'),
    ('User.Edit',           'Users',     'Edit existing users'),
    ('User.ChangeStatus',   'Users',     'Activate or deactivate users'),
    ('User.View',           'Users',     'View user list'),
    ('User.AssignRole',     'Users',     'Assign or remove user roles'),
    -- Roles & permissions
    ('Role.Create',         'Roles',     'Create roles'),
    ('Role.Edit',           'Roles',     'Edit roles'),
    ('Role.View',           'Roles',     'View role list'),
    ('Role.AssignPermission','Roles',    'Assign or remove role permissions'),
    -- Technicians
    ('Technician.Create',       'Technicians', 'Create technicians'),
    ('Technician.Edit',         'Technicians', 'Edit technician data'),
    ('Technician.ChangeStatus', 'Technicians', 'Change technician employment status'),
    ('Technician.View',         'Technicians', 'View technician list'),
    ('Technician.ViewOwn',      'Technicians', 'View own technician profile only'),
    -- Equipment
    ('Equipment.Receive',     'Equipment', 'Receive serialized equipment into warehouse'),
    ('Equipment.ChangeStatus','Equipment', 'Change equipment status'),
    ('Equipment.View',        'Equipment', 'View full equipment list'),
    ('Equipment.ViewAssigned','Equipment', 'View only equipment assigned to current user'),
    -- Materials
    ('Material.Create',      'Materials', 'Create materials'),
    ('Material.Edit',        'Materials', 'Edit materials'),
    ('Material.AdjustStock', 'Materials', 'Adjust material stock'),
    ('Material.View',        'Materials', 'View material list'),
    -- Work orders
    ('Order.Create',         'Orders', 'Create work orders'),
    ('Order.Edit',           'Orders', 'Edit work orders'),
    ('Order.ChangeStatus',   'Orders', 'Change order status'),
    ('Order.AssignTechnician','Orders','Assign or reassign technician to an order'),
    ('Order.View',           'Orders', 'View full order list'),
    ('Order.ViewOwn',        'Orders', 'View only orders assigned to current user'),
    -- Invoices
    ('Invoice.Create',       'Invoices', 'Create invoices (dispatch to technicians)'),
    ('Invoice.Void',         'Invoices', 'Void invoices'),
    ('Invoice.View',         'Invoices', 'View invoice list'),
    -- Liquidation / installation
    ('Liquidation.Register', 'Liquidation', 'Register order liquidation (technician)'),
    ('Liquidation.Validate', 'Liquidation', 'Validate liquidation (warehouse)'),
    ('Liquidation.View',     'Liquidation', 'View installation details'),
    -- Warranty
    ('Warranty.Register',    'Warranty', 'Register fault/warranty visit'),
    ('Warranty.View',        'Warranty', 'View warranty visit list'),
    -- Returns
    ('Return.Register',      'Returns', 'Register equipment/material return'),
    ('Return.View',          'Returns', 'View return list'),
    -- Audit
    ('Audit.View',           'Audit',   'View the audit log'),
    -- Reports
    ('Report.Operational',   'Reports', 'View operational reports'),
    ('Report.Management',    'Reports', 'View management & financial reports');


-- ROLE -> PERMISSION GRANTS

-- Manager: everything.
INSERT INTO role_permissions (role_id, permission_id)
SELECT r.role_id, p.permission_id
FROM roles r CROSS JOIN permissions p
WHERE r.role_name = 'Manager';

-- Warehouse lead: all operations except user/role admin and management reports.
INSERT INTO role_permissions (role_id, permission_id)
SELECT r.role_id, p.permission_id
FROM roles r CROSS JOIN permissions p
WHERE r.role_name = 'WarehouseLead'
  AND p.permission_code IN (
    'User.View','Role.View',
    'Technician.Create','Technician.Edit','Technician.ChangeStatus','Technician.View',
    'Equipment.Receive','Equipment.ChangeStatus','Equipment.View',
    'Material.Create','Material.Edit','Material.AdjustStock','Material.View',
    'Order.Create','Order.Edit','Order.ChangeStatus','Order.AssignTechnician','Order.View',
    'Invoice.Create','Invoice.Void','Invoice.View',
    'Liquidation.Validate','Liquidation.View',
    'Warranty.Register','Warranty.View',
    'Return.Register','Return.View',
    'Audit.View','Report.Operational'
  );

-- Warehouse clerk: dispatch (invoices) and receiving returns.
INSERT INTO role_permissions (role_id, permission_id)
SELECT r.role_id, p.permission_id
FROM roles r CROSS JOIN permissions p
WHERE r.role_name = 'WarehouseClerk'
  AND p.permission_code IN (
    'Technician.View',
    'Equipment.Receive','Equipment.View',
    'Material.View',
    'Order.View',
    'Invoice.Create','Invoice.View',
    'Liquidation.Validate','Liquidation.View',
    'Return.Register','Return.View'
  );

-- Technician: only their own orders and field actions.
INSERT INTO role_permissions (role_id, permission_id)
SELECT r.role_id, p.permission_id
FROM roles r CROSS JOIN permissions p
WHERE r.role_name = 'Technician'
  AND p.permission_code IN (
    'Technician.ViewOwn',
    'Equipment.ViewAssigned',
    'Material.View',
    'Order.ViewOwn',
    'Liquidation.Register',
    'Warranty.Register',
    'Return.Register'
  );

-- Auditor: read-only across the board.
INSERT INTO role_permissions (role_id, permission_id)
SELECT r.role_id, p.permission_id
FROM roles r CROSS JOIN permissions p
WHERE r.role_name = 'Auditor'
  AND p.permission_code IN (
    'User.View','Role.View','Technician.View','Equipment.View','Material.View',
    'Order.View','Invoice.View','Liquidation.View','Warranty.View','Return.View',
    'Audit.View','Report.Operational','Report.Management'
  );
