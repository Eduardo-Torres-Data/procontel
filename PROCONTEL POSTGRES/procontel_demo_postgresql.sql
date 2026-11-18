-- ============================================================================
--  PROCONTEL  -  Sample data load  (PostgreSQL)
-- ============================================================================
--  Loads demo technicians, accounts, inventory, orders and field operations
--  for testing the PostgreSQL schema and BI views.
--
--  Run AFTER procontel_postgresql.sql (the schema must already exist).
--  The script is re-runnable: SECTION 0 wipes operational data and restarts
--  identity sequences, so you can reload from a clean slate every time.
--
--  Notes for reviewers:
--    - Bulk generation uses generate_series and set-based INSERTs rather than
--      row-by-row loops where possible; procedural blocks use DO $$ ... $$.
--    - Randomness uses random()/md5(random()...) instead of T-SQL NEWID().
--    - Dates span Dec 2025 .. Apr 2026 to give the BI views something to chart.
-- ============================================================================


-- ############################################################################
-- SECTION 0: WIPE OPERATIONAL DATA (keeps structure)
-- ############################################################################
-- TRUNCATE ... RESTART IDENTITY CASCADE clears the tables and resets every
-- serial/identity column in one shot. Order does not matter with CASCADE.

TRUNCATE TABLE
    audit_log,
    equipment_transfers,
    installation_details,
    warranty_visits,
    inventory_returns,
    equipment_assignments,
    material_assignments,
    invoices,
    work_orders,
    user_roles,
    users,
    serialized_equipment,
    materials,
    technicians
RESTART IDENTITY CASCADE;


-- ############################################################################
-- SECTION 1: 39 TECHNICIANS
-- ############################################################################
-- Generate 39 fictional technicians that match the schema's format checks.
INSERT INTO technicians
    (crew_code, national_id, first_name, last_name, address, phone,
     blood_type, marital_status, birth_date, gender, license_type)
SELECT
    'PRO' || lpad(n::text, 2, '0'),
    lpad(n::text, 8, '0') || '-0',
    'Tecnico ' || n,
    'Demo',
    'Direccion de prueba ' || n,
    '0000-' || lpad(n::text, 4, '0'),
    'O+',
    'Single',
    DATE '1990-01-01' + n,
    CASE WHEN n % 2 = 0 THEN 'Female' ELSE 'Male' END,
    'Light'
FROM generate_series(1, 39) AS demo(n);


-- ############################################################################
-- SECTION 2: 5 ADMINISTRATIVE USERS + ROLE ASSIGNMENTS
-- ############################################################################
-- Demo users remain locked. They are used to link inventory and audit records.
INSERT INTO users
    (login, password_hash, first_name, last_name, email, technician_id, user_status)
VALUES
    ('demo_admin', '!', 'Usuario 1', 'Demo', 'demo_admin@example.invalid', NULL, 'Locked'),
    ('demo_bodega1', '!', 'Usuario 2', 'Demo', 'demo_bodega1@example.invalid', NULL, 'Locked'),
    ('demo_bodega2', '!', 'Usuario 3', 'Demo', 'demo_bodega2@example.invalid', NULL, 'Locked'),
    ('demo_supervisor', '!', 'Usuario 4', 'Demo', 'demo_supervisor@example.invalid', NULL, 'Locked'),
    ('demo_auditor', '!', 'Usuario 5', 'Demo', 'demo_auditor@example.invalid', NULL, 'Locked');

-- Assign roles by looking up ids (no hardcoding), so it works regardless of
-- how far the identity sequences have advanced.
INSERT INTO user_roles (user_id, role_id)
SELECT u.user_id, r.role_id
FROM users u JOIN roles r ON
     (u.login = 'demo_admin' AND r.role_name = 'Manager')
  OR (u.login = 'demo_bodega1'  AND r.role_name = 'WarehouseLead')
  OR (u.login = 'demo_bodega2'   AND r.role_name = 'WarehouseClerk')
  OR (u.login = 'demo_supervisor'   AND r.role_name = 'WarehouseClerk')
  OR (u.login = 'demo_auditor' AND r.role_name = 'Auditor');


-- ############################################################################
-- SECTION 3: TECHNICIAN USER ACCOUNTS (one per technician)
-- ############################################################################
-- Technician accounts use the crew code and remain locked in the demo.

INSERT INTO users (login, password_hash, first_name, last_name, technician_id, user_status)
SELECT lower(t.crew_code), '!', t.first_name, t.last_name, t.technician_id, 'Locked'
FROM technicians t;

INSERT INTO user_roles (user_id, role_id)
SELECT u.user_id, r.role_id
FROM users u
JOIN technicians t ON t.technician_id = u.technician_id
CROSS JOIN roles r
WHERE r.role_name = 'Technician';

-- ############################################################################
-- SECTION 4: 44 CONSUMABLE MATERIALS
-- ############################################################################
-- 44 consumable materials with opening stock.
INSERT INTO materials (material_code, material_name, unit_of_measure, warehouse_stock) VALUES
    ('CAB-ALAMB-VVDA', 'ALAMBRE ACOMDA EXT. VVDA 1X2X22,642035AM', 'Meters', 2500.00),
    ('CAB-RG6-MENS', 'CABLE RG6 TRI-SHIELD MENSAJERO 801355AM', 'Meters', 3500.00),
    ('CAB-RG6-DUCTO', 'CABLE RG6 TRISHIELD DUCTO NEGRO 801357AM', 'Meters', 2800.00),
    ('CAB-UTP-CAT5E', 'CABLE UTP CAT5E TT-U5EV22 TELETECHNO', 'Meters', 1800.00),
    ('CAB-UTP-CAT6', 'CABLES CAT6-UTP', 'Meters', 1500.00),
    ('CAB-CONDUMEX', 'CABLEDRP CONDUMEX 1FO3MM MOTED69176011AN', 'Meters', 2000.00),
    ('CAB-DROP050', 'HUAWEI DESBAL CABLE AEREODUCTO DROP 050M', 'Meters', 3000.00),
    ('CAB-DROP100', 'HUAWEI DESBAL CABLE AEREODUCTO DROP 100M', 'Meters', 4500.00),
    ('CAB-DROP150', 'HUAWEI DESBAL CABLE AEREODUCTO DROP 150M', 'Meters', 2200.00),
    ('CAB-DROP200', 'HUAWEI DESBAL CABLE AEREODUCTO DROP 200M', 'Meters', 1800.00),
    ('CON-BOTA-RJ45', 'BOTA PARA CONECTOR RJ45 CAT6', 'Units', 800.00),
    ('CON-FO-SCA', 'CONECTOR FO TT HOUSING+SCA M TTFC-SCX-CE', 'Units', 600.00),
    ('CON-RG6-F', 'CONECTOR RG-6 F 75 OHM QC1-H HOLLAND', 'Units', 1500.00),
    ('CON-RJ45-CAT6', 'CONECTOR RJ45 CAT 6', 'Units', 1200.00),
    ('CON-RJ45-CAT5E', 'CONECTOR RJ45 CAT5E TT-RJ45E TELETECHNO', 'Units', 900.00),
    ('CON-FMC2104', 'HUAWEI CONECTOR MECANICO FMC2104-SA', 'Units', 2000.00),
    ('CON-ROS-RJ11', 'ROSETA RJ-11', 'Units', 400.00),
    ('CON-ROS-OPT', 'ROSETA OPTICA SC/APC', 'Units', 700.00),
    ('ABR-COND-114', 'ABRAZADERAS CONDUIT 1 1/4', 'Units', 500.00),
    ('CAN-GALV-3', 'CANO GALVANIZADO 3 C/1MTR', 'Units', 200.00),
    ('CAN-GALV-114', 'CANO GALVANIZADO LIGERO 1 1/4', 'Units', 300.00),
    ('LNB-ELTEL-6022', 'LNB DOBLE ELTEL 6022C', 'Units', 80.00),
    ('LNB-NEW-M203', 'LNB DOBLE NEWLAND NL-M203', 'Units', 60.00),
    ('LNB-NEW-M103', 'LNB SENCILLO NEWLAND NL-M103', 'Units', 50.00),
    ('MSW-ZH-2X4', 'MULTISWITCH ZHONGSHAN 2X4 SH24C', 'Units', 40.00),
    ('MSW-ZH-2X8', 'MULTISWITCH ZHONGSHAN 2X8 SH28C', 'Units', 25.00),
    ('SPL-2V', 'SPLITER 2 VIAS RG-6 /CATV', 'Units', 300.00),
    ('SPL-3V-NB', 'SPLITER 3 VIAS NO BALANCEADO RG-6 /CATV', 'Units', 200.00),
    ('SPL-3V-B', 'SPLITER 3 VIAS BALANCEADO RG-6 /CATV', 'Units', 150.00),
    ('SPL-4V', 'SPLITER 4 VIAS RG-6 /CATV', 'Units', 100.00),
    ('GRA-NEG-3MM', 'GRAPA NEGRA 3MM P/1 FIBRA', 'Units', 2000.00),
    ('GRA-NEG-RG6', 'GRAPA NEGRAS RG-6', 'Units', 2500.00),
    ('GRA-PLANA-FRP', 'GRAPA PLANA GS P/CABLE DROP FO TIPO FRP', 'Units', 1800.00),
    ('TEN-PLAST-GAN', 'TENSOR PLASTICO CON GANCHO METALICO', 'Units', 1500.00),
    ('TEN-SINT-NEG', 'TENSOR SINTETICO COLOR NEGRO', 'Units', 1200.00),
    ('ANT-DS100', 'ANTENA SATEL 90CM DISHSTONE DS100-S9102U', 'Units', 35.00),
    ('ANT-GKF100', 'ANTENA SATELI ELTEL GKF-100 + KIT INSTAL', 'Units', 40.00),
    ('CIN-PLAST-11', 'CINCHOS PLASTICOS GRANDES DE 11', 'Units', 3000.00),
    ('CIN-AISL', 'CINTA AISLANTE', 'Rolls', 200.00),
    ('EBIAS-BD', 'EBIAS BAN-DIT', 'Boxes', 50.00),
    ('PROT-CSI-CPE', 'PROTECTOR CONTRA PICOS HOLLAND CSI-CPE', 'Units', 180.00),
    ('SIKA-300', 'SIKAFLEX 300 ml', 'Units', 120.00),
    ('TAPS-DC9', 'TAPS DC-9', 'Units', 80.00),
    ('TOR-ROCA-10X18', 'TORNILLO CON ARANDELA PUNTA ROCA 10x18', 'Units', 4000.00);

-- ############################################################################
-- SECTION 5: ~790 SERIALIZED UNITS (15 device models)
-- ############################################################################
-- Each block generates N units with a model-specific serial prefix, zero-padded
-- counter, status 'Warehouse' and a random received_date in the load window.
-- helper: a random date between 2025-12-01 and 2026-04-30.

DO $$
DECLARE
    d_start DATE := DATE '2025-12-01';
    d_days  INT  := DATE '2026-04-30' - DATE '2025-12-01';
BEGIN
    -- Block 1: ONT GPON HUAWEI HG8145X6-10 (200)
    INSERT INTO serialized_equipment (serial_number, model, device_type, equipment_status, received_date)
    SELECT '48575443' || lpad(n::TEXT, 8, '0'),
           'ONT GPON HUAWEI HG8145X6-10', 'ONT', 'Warehouse',
           d_start + (floor(random() * d_days))::INT
    FROM generate_series(1, 200) n;

    -- Block 2: ONT GPON ZTE ZXHN F6600P (60)
    INSERT INTO serialized_equipment (serial_number, model, device_type, equipment_status, received_date)
    SELECT 'ZTEONT' || lpad(n::TEXT, 6, '0'),
           'ONT GPON ZTE ZXHN F6600P', 'ONT', 'Warehouse',
           d_start + (floor(random() * d_days))::INT
    FROM generate_series(1, 60) n;

    -- Block 3: BUNDLE ZTE B866V2-H + REMOTE (150)
    INSERT INTO serialized_equipment (serial_number, model, device_type, equipment_status, received_date)
    SELECT 'ZTEATV45503' || lpad(n::TEXT, 6, '0'),
           'BUNDLE ZTE B866V2-H + REMOTE', 'STB', 'Warehouse',
           d_start + (floor(random() * d_days))::INT
    FROM generate_series(1, 150) n;

    -- Block 4: STB ZTE ZXV10 B710S2-A16 (50)
    INSERT INTO serialized_equipment (serial_number, model, device_type, equipment_status, received_date)
    SELECT 'ZTEB710' || lpad(n::TEXT, 6, '0'),
           'STB ZTE ZXV10 B710S2-A16', 'STB', 'Warehouse',
           d_start + (floor(random() * d_days))::INT
    FROM generate_series(1, 50) n;

    -- Block 5: EMTA DOCSIS CG2200 KAONMEDIA (80)
    INSERT INTO serialized_equipment (serial_number, model, device_type, equipment_status, received_date)
    SELECT 'BS1001094' || lpad(n::TEXT, 6, '0'),
           'EMTA DOCSIS CG2200 KAONMEDIA', 'Modem', 'Warehouse',
           d_start + (floor(random() * d_days))::INT
    FROM generate_series(1, 80) n;

    -- Block 6: EMTA DOCSIS 3.1 CG3000 KAONMEDIA (40)
    INSERT INTO serialized_equipment (serial_number, model, device_type, equipment_status, received_date)
    SELECT 'KAONCG3' || lpad(n::TEXT, 6, '0'),
           'EMTA DOCSIS 3.1 CG3000 KAONMEDIA', 'Modem', 'Warehouse',
           d_start + (floor(random() * d_days))::INT
    FROM generate_series(1, 40) n;

    -- Block 7: CABLE MODEM EMTA ARRIS TG2482AP2-85 (30)
    INSERT INTO serialized_equipment (serial_number, model, device_type, equipment_status, received_date)
    SELECT 'ARRTG2482' || lpad(n::TEXT, 6, '0'),
           'CABLE MODEM EMTA ARRIS TG2482AP2-85', 'Modem', 'Warehouse',
           d_start + (floor(random() * d_days))::INT
    FROM generate_series(1, 30) n;

    -- Block 8: EMTA 3.0 BC-RT905 BLUECASTLE (25)
    INSERT INTO serialized_equipment (serial_number, model, device_type, equipment_status, received_date)
    SELECT 'BCRT905' || lpad(n::TEXT, 6, '0'),
           'EMTA 3.0 BC-RT905 BLUECASTLE', 'Modem', 'Warehouse',
           d_start + (floor(random() * d_days))::INT
    FROM generate_series(1, 25) n;

    -- Block 9: ROUTER HUAWEI AX3 NEW (40)
    INSERT INTO serialized_equipment (serial_number, model, device_type, equipment_status, received_date)
    SELECT 'HWAX3' || lpad(n::TEXT, 6, '0'),
           'ROUTER HUAWEI AX3 NEW', 'Router', 'Warehouse',
           d_start + (floor(random() * d_days))::INT
    FROM generate_series(1, 40) n;

    -- Block 10: STB JIUZHOU DTS-8206 (15)
    INSERT INTO serialized_equipment (serial_number, model, device_type, equipment_status, received_date)
    SELECT 'JZDTS8206' || lpad(n::TEXT, 6, '0'),
           'STB JIUZHOU DTS-8206', 'STB', 'Warehouse',
           d_start + (floor(random() * d_days))::INT
    FROM generate_series(1, 15) n;

    -- Block 11: STB FOR DTH NEWLAND NL5101 LB (15)
    INSERT INTO serialized_equipment (serial_number, model, device_type, equipment_status, received_date)
    SELECT 'NLDTH' || lpad(n::TEXT, 6, '0'),
           'STB FOR DTH NEWLAND NL5101 LB', 'STB', 'Warehouse',
           d_start + (floor(random() * d_days))::INT
    FROM generate_series(1, 15) n;

    -- Block 12: SWITCH DLINK DGS105 (12)
    INSERT INTO serialized_equipment (serial_number, model, device_type, equipment_status, received_date)
    SELECT 'U8KY159' || lpad(n::TEXT, 6, '0'),
           'SWITCH DLINK DGS105', 'Switch', 'Warehouse',
           d_start + (floor(random() * d_days))::INT
    FROM generate_series(1, 12) n;

    -- Block 13: SWITCH DLINK DGS108 (8)
    INSERT INTO serialized_equipment (serial_number, model, device_type, equipment_status, received_date)
    SELECT 'U8KY108' || lpad(n::TEXT, 6, '0'),
           'SWITCH DLINK DGS108', 'Switch', 'Warehouse',
           d_start + (floor(random() * d_days))::INT
    FROM generate_series(1, 8) n;

    -- Block 14: IP PHONES XIM (35, four models rotating)
    INSERT INTO serialized_equipment (serial_number, model, device_type, equipment_status, received_date)
    SELECT 'TELXIM' || lpad(n::TEXT, 6, '0'),
           CASE (n % 4)
               WHEN 0 THEN 'XIM IP PHONE X1001'
               WHEN 1 THEN 'XIM IP PHONE X1002'
               WHEN 2 THEN 'XIM IP PHONE X1003'
               ELSE 'XIM IP PHONE X1004'
           END,
           'Phone', 'Warehouse',
           d_start + (floor(random() * d_days))::INT
    FROM generate_series(1, 35) n;

    -- Block 15: USIM CHIPS FOR DTH (30)
    INSERT INTO serialized_equipment (serial_number, model, device_type, equipment_status, received_date)
    SELECT 'USIM2FF' || lpad(n::TEXT, 6, '0'),
           'USIM 2FF-3FF-4FF 25.0 256K EXP DTH', 'SIM', 'Warehouse',
           d_start + (floor(random() * d_days))::INT
    FROM generate_series(1, 30) n;
END $$;


-- ############################################################################
-- SECTION 6: 200 WORK ORDERS
-- ############################################################################
-- Spread across the 5-month window. Status mix mirrors real operations:
-- ~60% Completed, ~15% Cancelled, ~10% Escalated, ~10% In Progress, ~5% Pending.

DO $$
DECLARE
    d_start   DATE := DATE '2025-12-01';
    d_days    INT  := DATE '2026-04-30' - DATE '2025-12-01';
    n_techs   INT;
    -- service order text + its technology type (already mapped to schema values)
    svc_text TEXT[] := ARRAY[
        '1 Play Internet 100MB','1 Play Internet 200MB','2 Play Internet + TV',
        '2 Play Internet + Voice','3 Play Internet TV Voice','TV HD Premium install',
        'Internet 50MB + TV','Tech change HFC to Fiber','Traditional Voice install',
        'DTH Satellite TV install','Satellite Internet install','Copper-to-Fiber migration'];
    svc_tech TEXT[] := ARRAY[
        'Fiber','Fiber','Fiber','Fiber','Fiber','HFC','HFC','Fiber','Copper','DTH','Satellite','Fiber'];
    tech_ids INT[];
    i INT;
    v_tech INT;
    v_status VARCHAR(20);
    v_svc INT;
    v_date DATE;
    r INT;
BEGIN
    -- snapshot of technician ids in stable order, to round-robin assign
    SELECT array_agg(technician_id ORDER BY technician_id) INTO tech_ids FROM technicians;
    n_techs := array_length(tech_ids, 1);

    FOR i IN 1..200 LOOP
        v_tech := tech_ids[((i - 1) % n_techs) + 1];
        v_svc  := ((i - 1) % 12) + 1;
        v_date := d_start + ((i * d_days) / 200);

        -- deterministic status mix
        r := i % 20;
        v_status := CASE
            WHEN r < 12 THEN 'Completed'
            WHEN r < 15 THEN 'Cancelled'
            WHEN r < 17 THEN 'Escalated'
            WHEN r < 19 THEN 'In Progress'
            ELSE 'Pending'
        END;

        INSERT INTO work_orders (
            request_number, technician_id, account_holder, line_number,
            service_order, technology_type, primary_contact, secondary_contact,
            install_address, technician_fee, order_date, order_status
        )
        VALUES (
            'SOL-' || lpad((75000 + i)::TEXT, 6, '0'),
            v_tech,
            'Cliente Demo ' || (((i - 1) % 40) + 1),
            '0001-' || lpad(i::TEXT, 4, '0'),
            svc_text[v_svc],
            svc_tech[v_svc],
            '0002-' || lpad(i::TEXT, 4, '0'),
            CASE WHEN i % 3 = 0
                 THEN '0003-' || lpad(i::TEXT, 4, '0')
                 ELSE NULL END,
            'Direccion de prueba ' || (((i - 1) % 35) + 1),
            round((15 + (i % 25))::NUMERIC, 2),
            v_date,
            v_status
        );
    END LOOP;
END $$;


-- ############################################################################
-- SECTION 7: 120 DISPATCH INVOICES WITH ASSIGNMENTS
-- ############################################################################
-- Each invoice: 3-10 serialized units + 4-9 materials.
-- expires_on = invoice_date + 90 days (business rule). Equipment goes to
-- 'Assigned'; material stock is decremented only when there is enough on hand.

DO $$
DECLARE
    d_start   DATE := DATE '2025-12-01';
    d_days    INT  := DATE '2026-04-30' - DATE '2025-12-01';
    n_techs   INT;
    tech_ids  INT[];
    avail     TEXT[];          -- queue of available serial numbers
    avail_pos INT := 1;
    mat_codes TEXT[];          -- materials with stock >= 100
    f INT;
    v_tech INT;
    v_clerk INT;
    v_invoice INT;
    v_date DATE;
    n_equip INT;
    n_mat INT;
    j INT;
    v_serial TEXT;
    v_matcode TEXT;
    v_qty NUMERIC(10,2);
    v_stock NUMERIC(10,2);
    clerk_ids INT[];
BEGIN
    SELECT array_agg(technician_id ORDER BY technician_id) INTO tech_ids FROM technicians;
    n_techs := array_length(tech_ids, 1);

    -- the two warehouse clerks
    SELECT array_agg(user_id ORDER BY user_id) INTO clerk_ids
      FROM users WHERE login IN ('demo_bodega2','demo_supervisor');

    -- queue of warehouse units in random order
    SELECT array_agg(serial_number ORDER BY random()) INTO avail
      FROM serialized_equipment WHERE equipment_status = 'Warehouse';

    -- materials with enough stock to distribute, highest stock first
    SELECT array_agg(material_code ORDER BY warehouse_stock DESC) INTO mat_codes
      FROM materials WHERE warehouse_stock >= 100;

    FOR f IN 1..120 LOOP
        v_date  := d_start + ((f * d_days) / 120);
        v_tech  := tech_ids[((f - 1) % n_techs) + 1];
        v_clerk := clerk_ids[(f % 2) + 1];
        n_equip := 3 + (f % 8);
        n_mat   := 4 + (f % 6);

        INSERT INTO invoices (invoice_date, technician_id, warehouse_user_id, notes)
        VALUES (v_date, v_tech, v_clerk, 'Dispatch invoice #' || f)
        RETURNING invoice_number INTO v_invoice;

        -- equipment lines: take the next n_equip serials from the queue
        FOR j IN 1..n_equip LOOP
            IF avail_pos > array_length(avail, 1) THEN EXIT; END IF;
            v_serial := avail[avail_pos];
            avail_pos := avail_pos + 1;

            INSERT INTO equipment_assignments
                (invoice_number, serial_number, quantity, assignment_status, expires_on)
            VALUES (v_invoice, v_serial, 1, 'Active', v_date + 90);

            UPDATE serialized_equipment SET equipment_status = 'Assigned'
             WHERE serial_number = v_serial;
        END LOOP;

        -- material lines: validate stock before inserting/decrementing
        FOR j IN 1..n_mat LOOP
            v_matcode := mat_codes[((f * 3 + j) % array_length(mat_codes, 1)) + 1];
            v_qty := CASE WHEN j % 3 = 0 THEN 5.0 + (f % 15) ELSE 1.0 + (f % 5) END;

            SELECT warehouse_stock INTO v_stock FROM materials WHERE material_code = v_matcode;

            IF v_stock >= v_qty AND NOT EXISTS (
                SELECT 1 FROM material_assignments
                 WHERE invoice_number = v_invoice AND material_code = v_matcode
            ) THEN
                INSERT INTO material_assignments (invoice_number, material_code, quantity)
                VALUES (v_invoice, v_matcode, v_qty);

                UPDATE materials SET warehouse_stock = warehouse_stock - v_qty
                 WHERE material_code = v_matcode;
            END IF;
        END LOOP;
    END LOOP;
END $$;


-- ############################################################################
-- SECTION 8: LIQUIDATIONS (installation_details)
-- ############################################################################
-- For Completed orders only: install some assigned units (-> 'Installed', the
-- assignment closes as 'Returned') and record material usage.

DO $$
DECLARE
    rec RECORD;
    o   INT := 0;
    v_install DATE;
    n_eq INT;
    n_mat INT;
    v_validated BOOLEAN;
    v_serial TEXT;
    used_serials TEXT[] := ARRAY[]::TEXT[];
    k INT;
    mat_codes TEXT[];
BEGIN
    -- materials usable for liquidation lines (exclude a couple of code families)
    SELECT array_agg(material_code) INTO mat_codes
      FROM materials
     WHERE material_code NOT LIKE 'EBIAS%' AND material_code NOT LIKE 'MSW%';

    FOR rec IN
        SELECT o.request_number, o.technician_id, o.order_date
          FROM work_orders o
         WHERE o.order_status = 'Completed'
         ORDER BY o.order_date
    LOOP
        o := o + 1;
        v_install   := rec.order_date + (1 + (o % 15));
        n_eq        := 1 + (o % 3);
        n_mat       := 2 + (o % 4);
        v_validated := (o % 5 <> 0);   -- ~20% left unvalidated on purpose

        -- install up to n_eq units still actively assigned to this technician
        FOR v_serial IN
            SELECT ea.serial_number
              FROM equipment_assignments ea
              JOIN invoices i ON i.invoice_number = ea.invoice_number
             WHERE i.technician_id = rec.technician_id
               AND ea.assignment_status = 'Active'
               AND ea.serial_number <> ALL (used_serials)
             ORDER BY ea.assignment_id
             LIMIT n_eq
        LOOP
            INSERT INTO installation_details
                (request_number, technician_id, installed_on, serial_number, warehouse_validated)
            VALUES (rec.request_number, rec.technician_id, v_install, v_serial, v_validated);

            UPDATE serialized_equipment SET equipment_status = 'Installed'
             WHERE serial_number = v_serial;

            UPDATE equipment_assignments SET assignment_status = 'Returned'
             WHERE serial_number = v_serial AND assignment_status = 'Active';

            used_serials := used_serials || v_serial;
        END LOOP;

        -- material usage lines (stock was already decremented at dispatch time)
        FOR k IN 1..n_mat LOOP
            INSERT INTO installation_details
                (request_number, technician_id, installed_on, material_code, quantity_used, warehouse_validated)
            VALUES (
                rec.request_number, rec.technician_id, v_install,
                mat_codes[((o + k) % array_length(mat_codes, 1)) + 1],
                CASE WHEN k % 2 = 0 THEN 5.0 + (o % 20) ELSE 1.0 + (o % 5) END,
                v_validated
            );
        END LOOP;
    END LOOP;
END $$;


-- ############################################################################
-- SECTION 9: WARRANTY VISITS (15)
-- ############################################################################
-- A mix of the four visit types, each kept coherent with the inventory columns
-- (the composite CHECK on warranty_visits enforces this). Falls back to
-- 'Software Support' if no suitable unit/material is available.

DO $$
DECLARE
    rec RECORD;
    a   INT := 0;
    v_ticket TEXT;
    v_visit DATE;
    v_new TEXT;
    v_old TEXT;
    v_mat TEXT;
BEGIN
    FOR rec IN
        SELECT request_number, technician_id, order_date
          FROM work_orders
         WHERE order_status = 'Completed'
         ORDER BY random()
         LIMIT 15
    LOOP
        a := a + 1;
        v_ticket := 'TKT-' || lpad(a::TEXT, 6, '0');
        v_visit  := rec.order_date + (30 + a * 5);

        IF a <= 5 THEN
            -- Software Support
            INSERT INTO warranty_visits
                (ticket_number, request_number, technician_id, visit_date, reported_problem, visit_type)
            VALUES (v_ticket, rec.request_number, rec.technician_id, v_visit,
                    'Customer reports intermittence; device rebooted and OK', 'Software Support');

        ELSIF a <= 10 THEN
            -- Equipment Swap
            SELECT serial_number INTO v_new FROM serialized_equipment
             WHERE equipment_status = 'Warehouse' AND device_type = 'ONT'
             ORDER BY random() LIMIT 1;
            SELECT serial_number INTO v_old FROM serialized_equipment
             WHERE equipment_status = 'Installed' ORDER BY random() LIMIT 1;

            IF v_new IS NOT NULL AND v_old IS NOT NULL THEN
                INSERT INTO warranty_visits
                    (ticket_number, request_number, technician_id, visit_date,
                     reported_problem, visit_type, installed_serial, removed_serial)
                VALUES (v_ticket, rec.request_number, rec.technician_id, v_visit,
                        'No signal; unit swapped for a new one', 'Equipment Swap', v_new, v_old);
                UPDATE serialized_equipment SET equipment_status = 'Installed' WHERE serial_number = v_new;
                UPDATE serialized_equipment SET equipment_status = 'Damaged'   WHERE serial_number = v_old;
            ELSE
                INSERT INTO warranty_visits
                    (ticket_number, request_number, technician_id, visit_date, reported_problem, visit_type)
                VALUES (v_ticket, rec.request_number, rec.technician_id, v_visit,
                        'On-site technical support', 'Software Support');
            END IF;

        ELSIF a <= 13 THEN
            -- Material Use
            SELECT material_code INTO v_mat FROM materials
             WHERE material_name ILIKE '%CABLE%' AND warehouse_stock > 20
             ORDER BY random() LIMIT 1;

            IF v_mat IS NOT NULL THEN
                INSERT INTO warranty_visits
                    (ticket_number, request_number, technician_id, visit_date,
                     reported_problem, visit_type, material_code, material_quantity)
                VALUES (v_ticket, rec.request_number, rec.technician_id, v_visit,
                        'Damaged cable section replaced', 'Material Use', v_mat, 10.0);
                UPDATE materials SET warehouse_stock = warehouse_stock - 10.0 WHERE material_code = v_mat;
            ELSE
                INSERT INTO warranty_visits
                    (ticket_number, request_number, technician_id, visit_date, reported_problem, visit_type)
                VALUES (v_ticket, rec.request_number, rec.technician_id, v_visit,
                        'Routine check, no changes', 'Software Support');
            END IF;

        ELSE
            -- Swap And Material
            SELECT serial_number INTO v_new FROM serialized_equipment
             WHERE equipment_status = 'Warehouse' ORDER BY random() LIMIT 1;
            SELECT material_code INTO v_mat FROM materials
             WHERE warehouse_stock > 10 ORDER BY random() LIMIT 1;

            IF v_new IS NOT NULL AND v_mat IS NOT NULL THEN
                INSERT INTO warranty_visits
                    (ticket_number, request_number, technician_id, visit_date,
                     reported_problem, visit_type, installed_serial, material_code, material_quantity)
                VALUES (v_ticket, rec.request_number, rec.technician_id, v_visit,
                        'Surge damage; unit swap + new cable', 'Swap And Material', v_new, v_mat, 5.0);
                UPDATE serialized_equipment SET equipment_status = 'Installed' WHERE serial_number = v_new;
                UPDATE materials SET warehouse_stock = warehouse_stock - 5.0 WHERE material_code = v_mat;
            ELSE
                INSERT INTO warranty_visits
                    (ticket_number, request_number, technician_id, visit_date, reported_problem, visit_type)
                VALUES (v_ticket, rec.request_number, rec.technician_id, v_visit,
                        'Diagnostics performed', 'Software Support');
            END IF;
        END IF;
    END LOOP;
END $$;


-- ############################################################################
-- SECTION 10: TECHNICIAN-TO-TECHNICIAN TRANSFERS (8)
-- ############################################################################
-- Demonstrates moving a unit between crews without returning it to the
-- warehouse. The new assignment INHERITS the original 90-day deadline.

DO $$
DECLARE
    rec RECORD;
    t   INT := 0;
    n_techs INT;
    tech_ids INT[];
    v_target INT;
    v_invoice INT;
    v_new_assignment INT;
    v_auth INT;
    reasons TEXT[] := ARRAY[
        'Near Expiry','Technician No Longer Needs','Crew Reassignment',
        'Requested By Target','Other'];
BEGIN
    SELECT array_agg(technician_id ORDER BY technician_id) INTO tech_ids FROM technicians;
    n_techs := array_length(tech_ids, 1);
    SELECT user_id INTO v_auth FROM users WHERE login = 'demo_bodega1';

    FOR rec IN
        SELECT ea.assignment_id, ea.serial_number, i.technician_id AS source_tech, ea.expires_on
          FROM equipment_assignments ea
          JOIN invoices i ON i.invoice_number = ea.invoice_number
         WHERE ea.assignment_status = 'Active'
         ORDER BY random()
         LIMIT 8
    LOOP
        t := t + 1;

        -- pick a target technician different from the source
        v_target := tech_ids[((rec.source_tech + t) % n_techs) + 1];
        IF v_target = rec.source_tech THEN
            v_target := tech_ids[((rec.source_tech + t + 1) % n_techs) + 1];
        END IF;

        -- close source assignment
        UPDATE equipment_assignments SET assignment_status = 'Transferred'
         WHERE assignment_id = rec.assignment_id;

        -- virtual invoice for the target, tagged as a transfer
        INSERT INTO invoices (technician_id, warehouse_user_id, notes)
        VALUES (v_target, v_auth, 'TRANSFER of unit ' || rec.serial_number)
        RETURNING invoice_number INTO v_invoice;

        -- new assignment inherits the original deadline (clock does not reset)
        INSERT INTO equipment_assignments
            (invoice_number, serial_number, quantity, assignment_status, expires_on)
        VALUES (v_invoice, rec.serial_number, 1, 'Active', rec.expires_on)
        RETURNING assignment_id INTO v_new_assignment;

        INSERT INTO equipment_transfers (
            serial_number, source_technician_id, target_technician_id,
            transfer_reason, source_assignment_id, target_assignment_id,
            authorized_by_user_id, notes
        )
        VALUES (
            rec.serial_number, rec.source_tech, v_target,
            reasons[(t % 5) + 1], rec.assignment_id, v_new_assignment,
            v_auth, 'Field reassignment between crews'
        );
    END LOOP;
END $$;


-- ############################################################################
-- SECTION 11: INVENTORY RETURNS (12)
-- ############################################################################
-- Surplus material returns add back to stock; equipment returns flip the unit
-- back to 'Warehouse' (or 'Damaged') and close the assignment.

DO $$
DECLARE
    rec RECORD;
    c   INT := 0;
    v_clerk INT;
    v_cond TEXT;
    conditions TEXT[] := ARRAY['Good/Surplus','Factory Defect','Damaged In Use'];
BEGIN
    SELECT user_id INTO v_clerk FROM users WHERE login = 'demo_bodega2';

    -- a few equipment returns from still-active assignments
    FOR rec IN
        SELECT ea.serial_number, i.technician_id
          FROM equipment_assignments ea
          JOIN invoices i ON i.invoice_number = ea.invoice_number
         WHERE ea.assignment_status = 'Active'
         ORDER BY random()
         LIMIT 7
    LOOP
        c := c + 1;
        v_cond := conditions[(c % 3) + 1];

        INSERT INTO inventory_returns
            (technician_id, warehouse_user_id, serial_number, item_condition)
        VALUES (rec.technician_id, v_clerk, rec.serial_number, v_cond);

        UPDATE serialized_equipment
           SET equipment_status = CASE
                   WHEN v_cond IN ('Factory Defect','Damaged In Use') THEN 'Damaged'
                   ELSE 'Warehouse' END
         WHERE serial_number = rec.serial_number;

        UPDATE equipment_assignments SET assignment_status = 'Returned'
         WHERE serial_number = rec.serial_number AND assignment_status = 'Active';
    END LOOP;

    -- a few surplus material returns
    FOR rec IN
        SELECT material_code FROM materials ORDER BY random() LIMIT 5
    LOOP
        c := c + 1;
        INSERT INTO inventory_returns
            (technician_id, warehouse_user_id, material_code, returned_quantity, item_condition)
        VALUES (
            (SELECT technician_id FROM technicians ORDER BY random() LIMIT 1),
            v_clerk, rec.material_code, 2.0 + (c % 5), 'Good/Surplus'
        );
        UPDATE materials SET warehouse_stock = warehouse_stock + (2.0 + (c % 5))
         WHERE material_code = rec.material_code;
    END LOOP;
END $$;


-- ############################################################################
-- SECTION 12: FINAL TOTALS
-- ############################################################################
-- Quick row counts so you can confirm the load at a glance.

SELECT 'technicians'           AS entity, count(*) AS rows FROM technicians
UNION ALL SELECT 'users',                 count(*) FROM users
UNION ALL SELECT 'materials',             count(*) FROM materials
UNION ALL SELECT 'serialized_equipment',  count(*) FROM serialized_equipment
UNION ALL SELECT 'work_orders',           count(*) FROM work_orders
UNION ALL SELECT 'invoices',              count(*) FROM invoices
UNION ALL SELECT 'equipment_assignments', count(*) FROM equipment_assignments
UNION ALL SELECT 'material_assignments',  count(*) FROM material_assignments
UNION ALL SELECT 'installation_details',  count(*) FROM installation_details
UNION ALL SELECT 'warranty_visits',       count(*) FROM warranty_visits
UNION ALL SELECT 'equipment_transfers',   count(*) FROM equipment_transfers
UNION ALL SELECT 'inventory_returns',     count(*) FROM inventory_returns
ORDER BY entity;
