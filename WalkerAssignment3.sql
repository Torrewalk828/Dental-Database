

-- Create & Use Database
------------------------------------------------------------
IF DB_ID('Dental') IS NULL
BEGIN
    CREATE DATABASE Dental;
END
GO
USE Dental;
GO

------------------------------------------------------------
-- DROP old objects if re-running (optional safety)
------------------------------------------------------------
IF OBJECT_ID('dbo.trg_visit_payment_method_guard','TR') IS NOT NULL
    DROP TRIGGER dbo.trg_visit_payment_method_guard;
GO
IF OBJECT_ID('dbo.visit_payment','U') IS NOT NULL DROP TABLE dbo.visit_payment;
IF OBJECT_ID('dbo.payment','U')       IS NOT NULL DROP TABLE dbo.payment;
IF OBJECT_ID('dbo.visit_xray','U')    IS NOT NULL DROP TABLE dbo.visit_xray;
IF OBJECT_ID('dbo.visit_service','U') IS NOT NULL DROP TABLE dbo.visit_service;
IF OBJECT_ID('dbo.visit','U')         IS NOT NULL DROP TABLE dbo.visit;
IF OBJECT_ID('dbo.patient_insurance','U') IS NOT NULL DROP TABLE dbo.patient_insurance;
IF OBJECT_ID('dbo.patient_card','U')  IS NOT NULL DROP TABLE dbo.patient_card;
IF OBJECT_ID('dbo.hygienist_email','U') IS NOT NULL DROP TABLE dbo.hygienist_email;
IF OBJECT_ID('dbo.dentist_email','U')   IS NOT NULL DROP TABLE dbo.dentist_email;
IF OBJECT_ID('dbo.patient_phone','U')   IS NOT NULL DROP TABLE dbo.patient_phone;
IF OBJECT_ID('dbo.xray','U')        IS NOT NULL DROP TABLE dbo.xray;
IF OBJECT_ID('dbo.service','U')     IS NOT NULL DROP TABLE dbo.service;
IF OBJECT_ID('dbo.card','U')        IS NOT NULL DROP TABLE dbo.card;
IF OBJECT_ID('dbo.insurance','U')   IS NOT NULL DROP TABLE dbo.insurance;
IF OBJECT_ID('dbo.hygienist','U')   IS NOT NULL DROP TABLE dbo.hygienist;
IF OBJECT_ID('dbo.dentist','U')     IS NOT NULL DROP TABLE dbo.dentist;
IF OBJECT_ID('dbo.patient','U')     IS NOT NULL DROP TABLE dbo.patient;
GO

/* =========================================================
   CORE ENTITIES
   ========================================================= */
CREATE TABLE dbo.patient (
  patient_id     BIGINT IDENTITY(1,1) PRIMARY KEY,
  first_name     VARCHAR(50)  NOT NULL,
  middle_name    VARCHAR(50)  NULL,
  last_name      VARCHAR(50)  NOT NULL,
  dob            DATE         NOT NULL,
  sex            CHAR(1)      NOT NULL CHECK (sex IN ('F','M','O')),
  address        VARCHAR(120) NULL,
  city           VARCHAR(60)  NULL,
  state          CHAR(2)      NULL,
  zip            VARCHAR(10)  NULL
);
GO

CREATE TABLE dbo.dentist (
  dentist_id     BIGINT IDENTITY(1,1) PRIMARY KEY,
  first_name     VARCHAR(50) NOT NULL,
  last_name      VARCHAR(50) NOT NULL,
  license_no     VARCHAR(40) NOT NULL UNIQUE
);
GO

CREATE TABLE dbo.hygienist (
  hygienist_id   BIGINT IDENTITY(1,1) PRIMARY KEY,
  first_name     VARCHAR(50) NOT NULL,
  last_name      VARCHAR(50) NOT NULL,
  license_no     VARCHAR(40) NOT NULL UNIQUE
);
GO

CREATE TABLE dbo.insurance (
  insurance_id   BIGINT IDENTITY(1,1) PRIMARY KEY,
  name           VARCHAR(80) NOT NULL,
  phone          VARCHAR(30) NULL,
  address        VARCHAR(120) NULL
);
GO

CREATE TABLE dbo.card (
  card_id        BIGINT IDENTITY(1,1) PRIMARY KEY,
  masked_number  VARCHAR(25) NOT NULL,
  [type]         VARCHAR(20) NOT NULL,   -- Visa, MC, etc.
  exp_month      SMALLINT NOT NULL CHECK (exp_month BETWEEN 1 AND 12),
  exp_year       SMALLINT NOT NULL CHECK (exp_year BETWEEN 2000 AND 2100),
  name_on_card   VARCHAR(80) NOT NULL
);
GO

CREATE TABLE dbo.service (
  service_id     BIGINT IDENTITY(1,1) PRIMARY KEY,
  [description]  VARCHAR(120) NOT NULL,
  default_cost   DECIMAL(10,2) NOT NULL CHECK (default_cost >= 0)
);
GO

CREATE TABLE dbo.xray (
  xray_id        BIGINT IDENTITY(1,1) PRIMARY KEY,
  [type]         VARCHAR(60) NOT NULL,
  base_cost      DECIMAL(10,2) NOT NULL CHECK (base_cost >= 0)
);
GO

/* =========================================================
   MULTIVALUED ATTRIBUTES AS TABLES
   ========================================================= */
CREATE TABLE dbo.patient_phone (
  patient_id     BIGINT NOT NULL,
  phone_number   VARCHAR(30) NOT NULL,
  [type]         VARCHAR(20) NULL,            -- mobile, home, work...
  CONSTRAINT PK_patient_phone PRIMARY KEY (patient_id, phone_number),
  CONSTRAINT FK_patient_phone_patient
      FOREIGN KEY (patient_id) REFERENCES dbo.patient(patient_id) ON DELETE CASCADE
);
GO

CREATE TABLE dbo.dentist_email (
  dentist_id     BIGINT NOT NULL,
  email          VARCHAR(120) NOT NULL,
  CONSTRAINT PK_dentist_email PRIMARY KEY (dentist_id, email),
  CONSTRAINT FK_dentist_email_dentist
      FOREIGN KEY (dentist_id) REFERENCES dbo.dentist(dentist_id) ON DELETE CASCADE
);
GO

CREATE TABLE dbo.hygienist_email (
  hygienist_id   BIGINT NOT NULL,
  email          VARCHAR(120) NOT NULL,
  CONSTRAINT PK_hygienist_email PRIMARY KEY (hygienist_id, email),
  CONSTRAINT FK_hygienist_email_hygienist
      FOREIGN KEY (hygienist_id) REFERENCES dbo.hygienist(hygienist_id) ON DELETE CASCADE
);
GO

/* =========================================================
   BRIDGES (M:N)
   ========================================================= */
CREATE TABLE dbo.patient_card (
  patient_id     BIGINT NOT NULL,
  card_id        BIGINT NOT NULL,
  CONSTRAINT PK_patient_card PRIMARY KEY (patient_id, card_id),
  CONSTRAINT FK_patient_card_patient  FOREIGN KEY (patient_id) REFERENCES dbo.patient(patient_id) ON DELETE CASCADE,
  CONSTRAINT FK_patient_card_card     FOREIGN KEY (card_id)    REFERENCES dbo.card(card_id)
);
GO

CREATE TABLE dbo.patient_insurance (
  patient_id     BIGINT NOT NULL,
  insurance_id   BIGINT NOT NULL,
  policy_number  VARCHAR(60) NOT NULL,
  group_number   VARCHAR(60) NULL,
  effective_date DATE NOT NULL,
  end_date       DATE NULL,
  is_primary     BIT  NOT NULL DEFAULT (0),
  CONSTRAINT PK_patient_insurance PRIMARY KEY (patient_id, insurance_id, policy_number),
  CONSTRAINT FK_patient_insurance_patient   FOREIGN KEY (patient_id)   REFERENCES dbo.patient(patient_id)   ON DELETE CASCADE,
  CONSTRAINT FK_patient_insurance_insurance FOREIGN KEY (insurance_id) REFERENCES dbo.insurance(insurance_id),
  CONSTRAINT CK_patient_insurance_dates CHECK (end_date IS NULL OR end_date >= effective_date)
);
GO

-- One primary policy per patient (optional but useful)
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'UX_patient_primary_insurance')
BEGIN
    CREATE UNIQUE INDEX UX_patient_primary_insurance
      ON dbo.patient_insurance(patient_id)
      WHERE is_primary = 1;
END
GO

/* =========================================================
   ASSOCIATIVE ENTITY: VISIT (composite PK)
   ========================================================= */
CREATE TABLE dbo.visit (
  patient_id       BIGINT      NOT NULL,
  dentist_id       BIGINT      NOT NULL,
  hygienist_id     BIGINT      NOT NULL,
  visit_datetime   DATETIME2   NOT NULL,
  cost             DECIMAL(10,2) NOT NULL CHECK (cost >= 0),
  treatment        NVARCHAR(MAX) NULL,
  next_visit_date  DATE NULL,
  CONSTRAINT PK_visit PRIMARY KEY (patient_id, dentist_id, hygienist_id, visit_datetime),
  CONSTRAINT FK_visit_patient   FOREIGN KEY (patient_id)   REFERENCES dbo.patient(patient_id)   ON DELETE CASCADE,
  CONSTRAINT FK_visit_dentist   FOREIGN KEY (dentist_id)   REFERENCES dbo.dentist(dentist_id),
  CONSTRAINT FK_visit_hygienist FOREIGN KEY (hygienist_id) REFERENCES dbo.hygienist(hygienist_id)
);
GO

/* =========================================================
   MULTIVALUED ATTRIBUTES OF VISIT
   ========================================================= */
CREATE TABLE dbo.visit_service (
  patient_id       BIGINT      NOT NULL,
  dentist_id       BIGINT      NOT NULL,
  hygienist_id     BIGINT      NOT NULL,
  visit_datetime   DATETIME2   NOT NULL,
  service_id       BIGINT      NOT NULL,
  quantity         INT         NOT NULL DEFAULT (1) CHECK (quantity >= 1),
  cost             DECIMAL(10,2) NOT NULL CHECK (cost >= 0),
  CONSTRAINT PK_visit_service PRIMARY KEY (patient_id, dentist_id, hygienist_id, visit_datetime, service_id),
  CONSTRAINT FK_visit_service_visit FOREIGN KEY (patient_id, dentist_id, hygienist_id, visit_datetime)
      REFERENCES dbo.visit(patient_id, dentist_id, hygienist_id, visit_datetime) ON DELETE CASCADE,
  CONSTRAINT FK_visit_service_service FOREIGN KEY (service_id)
      REFERENCES dbo.service(service_id)
);
GO

CREATE TABLE dbo.visit_xray (
  patient_id       BIGINT      NOT NULL,
  dentist_id       BIGINT      NOT NULL,
  hygienist_id     BIGINT      NOT NULL,
  visit_datetime   DATETIME2   NOT NULL,
  xray_id          BIGINT      NOT NULL,
  findings         NVARCHAR(MAX) NULL,
  CONSTRAINT PK_visit_xray PRIMARY KEY (patient_id, dentist_id, hygienist_id, visit_datetime, xray_id),
  CONSTRAINT FK_visit_xray_visit FOREIGN KEY (patient_id, dentist_id, hygienist_id, visit_datetime)
      REFERENCES dbo.visit(patient_id, dentist_id, hygienist_id, visit_datetime) ON DELETE CASCADE,
  CONSTRAINT FK_visit_xray_xray FOREIGN KEY (xray_id)
      REFERENCES dbo.xray(xray_id)
);
GO

/* =========================================================
   PAYMENTS (+ trigger to validate method vs. fields)
   ========================================================= */
CREATE TABLE dbo.payment (
  payment_id     BIGINT IDENTITY(1,1) PRIMARY KEY,
  method         VARCHAR(12) NOT NULL CHECK (method IN ('self-pay','card','insurance')),
  amount         DECIMAL(10,2) NOT NULL CHECK (amount >= 0),
  paid_on        DATETIME2 NOT NULL DEFAULT SYSUTCDATETIME()
);
GO

CREATE TABLE dbo.visit_payment (
  payment_id     BIGINT     NOT NULL PRIMARY KEY,  -- 1:1 with payment row
  patient_id     BIGINT     NOT NULL,
  dentist_id     BIGINT     NOT NULL,
  hygienist_id   BIGINT     NOT NULL,
  visit_datetime DATETIME2  NOT NULL,
  card_id        BIGINT     NULL,   -- if method='card'
  insurance_id   BIGINT     NULL,   -- if method='insurance'
  CONSTRAINT FK_visit_payment_payment FOREIGN KEY (payment_id)
      REFERENCES dbo.payment(payment_id) ON DELETE CASCADE,
  CONSTRAINT FK_visit_payment_visit FOREIGN KEY (patient_id, dentist_id, hygienist_id, visit_datetime)
      REFERENCES dbo.visit(patient_id, dentist_id, hygienist_id, visit_datetime) ON DELETE CASCADE,
  CONSTRAINT FK_visit_payment_card FOREIGN KEY (card_id)
      REFERENCES dbo.card(card_id),
  CONSTRAINT FK_visit_payment_ins FOREIGN KEY (insurance_id)
      REFERENCES dbo.insurance(insurance_id)
);
GO

CREATE OR ALTER TRIGGER dbo.trg_visit_payment_method_guard
ON dbo.visit_payment
AFTER INSERT, UPDATE
AS
BEGIN
    SET NOCOUNT ON;

    -- method=card -> require card_id and no insurance_id
    IF EXISTS (
        SELECT 1
        FROM inserted i
        JOIN dbo.payment p ON p.payment_id = i.payment_id
        WHERE p.method = 'card' AND (i.card_id IS NULL OR i.insurance_id IS NOT NULL)
    )
    BEGIN
        RAISERROR('For method=card, card_id must be set and insurance_id must be NULL.', 16, 1);
        ROLLBACK TRANSACTION; RETURN;
    END

    -- method=insurance -> require insurance_id and no card_id
    IF EXISTS (
        SELECT 1
        FROM inserted i
        JOIN dbo.payment p ON p.payment_id = i.payment_id
        WHERE p.method = 'insurance' AND (i.insurance_id IS NULL OR i.card_id IS NOT NULL)
    )
    BEGIN
        RAISERROR('For method=insurance, insurance_id must be set and card_id must be NULL.', 16, 1);
        ROLLBACK TRANSACTION; RETURN;
    END

    -- method=self-pay -> neither id present
    IF EXISTS (
        SELECT 1
        FROM inserted i
        JOIN dbo.payment p ON p.payment_id = i.payment_id
        WHERE p.method = 'self-pay' AND (i.card_id IS NOT NULL OR i.insurance_id IS NOT NULL)
    )
    BEGIN
        RAISERROR('For method=self-pay, card_id and insurance_id must be NULL.', 16, 1);
        ROLLBACK TRANSACTION; RETURN;
    END
END;
GO

/* =========================================================
   Helpful Indexes
   ========================================================= */
CREATE INDEX ix_patient_phone_patient      ON dbo.patient_phone(patient_id);
CREATE INDEX ix_patient_card_card          ON dbo.patient_card(card_id);
CREATE INDEX ix_patient_insurance_ins      ON dbo.patient_insurance(insurance_id);
CREATE INDEX ix_dentist_email_dentist      ON dbo.dentist_email(dentist_id);
CREATE INDEX ix_hygienist_email_hygienist  ON dbo.hygienist_email(hygienist_id);
CREATE INDEX ix_visit_patient              ON dbo.visit(patient_id);
CREATE INDEX ix_visit_service_service      ON dbo.visit_service(service_id);
CREATE INDEX ix_visit_xray_xray            ON dbo.visit_xray(xray_id);
CREATE INDEX ix_visit_payment_visit        ON dbo.visit_payment(patient_id, dentist_id, hygienist_id, visit_datetime);
GO

/* =========================================================
   SAMPLE DATA (? 3 ROWS PER TABLE)
   ========================================================= */

-- Patients
INSERT INTO dbo.patient (first_name,middle_name,last_name,dob,sex,address,city,state,zip) VALUES
('Alex',  NULL,'Rivera','1999-04-05','M','12 Lakeview Dr','Kennesaw','GA','30144'),
('Bailey','Q',  'Kim',  '2000-08-17','F','88 Pine St','Marietta','GA','30060'),
('Chris', NULL,'Jordan','2001-11-23','O','501 Oak Ave','Atlanta','GA','30303');

-- Dentists
INSERT INTO dbo.dentist (first_name,last_name,license_no) VALUES
('Dana','Smith','DN-1001'),
('Erin','Patel','DN-1002'),
('Leo','Chen','DN-1003');

-- Hygienists
INSERT INTO dbo.hygienist (first_name,last_name,license_no) VALUES
('Haley','Jones','HY-2002'),
('Maya','Ruiz','HY-2003'),
('Owen','Li','HY-2004');

-- Phones (multivalued)
INSERT INTO dbo.patient_phone (patient_id, phone_number, [type]) VALUES
(1,'404-555-1111','mobile'),
(1,'770-555-2222','home'),
(2,'678-555-3333','mobile'),
(3,'470-555-4444','mobile');

-- Emails (multivalued)
INSERT INTO dbo.dentist_email (dentist_id, email) VALUES
(1,'dsmith@clinic.com'), (2,'epatel@clinic.com'), (3,'lchen@clinic.com');

INSERT INTO dbo.hygienist_email (hygienist_id, email) VALUES
(1,'hjones@clinic.com'), (2,'mruiz@clinic.com'), (3,'oli@clinic.com');

-- Catalogs
INSERT INTO dbo.service ([description], default_cost) VALUES
('Cleaning', 80.00), ('Filling', 150.00), ('Whitening', 250.00);

INSERT INTO dbo.xray ([type], base_cost) VALUES
('Bitewing', 60.00), ('Panoramic', 120.00), ('Periapical', 75.00);

-- Insurance & Cards
INSERT INTO dbo.insurance (name, phone, address) VALUES
('PeachCare','800-000-0000','100 Main St'),
('DeltaDental','877-111-2222','200 Broad St'),
('HealthyOne','866-333-4444','300 Center Rd');

INSERT INTO dbo.card (masked_number,[type],exp_month,exp_year,name_on_card) VALUES
('**** **** **** 1234','Visa',12,2028,'Alex Rivera'),
('**** **** **** 9876','Mastercard',7,2027,'Bailey Kim'),
('**** **** **** 4444','Amex',3,2029,'Chris Jordan');

-- Bridges
INSERT INTO dbo.patient_card (patient_id, card_id) VALUES
(1,1),(2,2),(3,3);

INSERT INTO dbo.patient_insurance (patient_id, insurance_id, policy_number, group_number, effective_date, end_date, is_primary) VALUES
(1,1,'POL-A1','G-A', '2025-01-01', NULL, 1),
(2,2,'POL-B2','G-B', '2024-06-01', NULL, 1),
(3,3,'POL-C3','G-C', '2024-01-01', '2025-01-01', 0);

-- Visits (associative)
INSERT INTO dbo.visit (patient_id,dentist_id,hygienist_id,visit_datetime,cost,treatment,next_visit_date) VALUES
(1,1,1,'2025-10-15 09:30',230.00,'Routine cleaning','2025-12-01'),
(2,2,2,'2025-10-16 10:15',300.00,'Filling upper left','2026-01-10'),
(3,3,3,'2025-10-17 14:00',420.00,'Whitening + XRay','2025-11-20');

-- Visit Services
INSERT INTO dbo.visit_service (patient_id,dentist_id,hygienist_id,visit_datetime,service_id,quantity,cost) VALUES
(1,1,1,'2025-10-15 09:30', 1, 1, 80.00),      -- Cleaning
(2,2,2,'2025-10-16 10:15', 2, 1, 150.00),     -- Filling
(3,3,3,'2025-10-17 14:00', 3, 1, 250.00);     -- Whitening

-- Visit XRays
INSERT INTO dbo.visit_xray (patient_id,dentist_id,hygienist_id,visit_datetime,xray_id,findings) VALUES
(1,1,1,'2025-10-15 09:30', 1, 'No issues'),
(2,2,2,'2025-10-16 10:15', 2, 'Tooth decay visible'),
(3,3,3,'2025-10-17 14:00', 3, 'Whitening prep OK');

-- Payments (one per visit; mixes methods)
INSERT INTO dbo.payment (method, amount) VALUES
('self-pay', 230.00), ('card', 300.00), ('insurance', 420.00);

-- Map payments to visits (trigger enforces correctness)
INSERT INTO dbo.visit_payment (payment_id, patient_id, dentist_id, hygienist_id, visit_datetime)
VALUES (1,1,1,1,'2025-10-15 09:30');   -- self-pay (no card/ins)

INSERT INTO dbo.visit_payment (payment_id, patient_id, dentist_id, hygienist_id, visit_datetime, card_id)
VALUES (2,2,2,2,'2025-10-16 10:15', 2); -- card

INSERT INTO dbo.visit_payment (payment_id, patient_id, dentist_id, hygienist_id, visit_datetime, insurance_id)
VALUES (3,3,3,3,'2025-10-17 14:00', 3); -- insurance
GO

/* =========================================================
   QUERIES FOR SCREENSHOTS (run and screenshot results)
   ========================================================= */
SELECT * FROM dbo.patient;
SELECT * FROM dbo.dentist;
SELECT * FROM dbo.hygienist;
SELECT * FROM dbo.insurance;
SELECT * FROM dbo.card;
SELECT * FROM dbo.service;
SELECT * FROM dbo.xray;
SELECT * FROM dbo.patient_phone;
SELECT * FROM dbo.dentist_email;
SELECT * FROM dbo.hygienist_email;
SELECT * FROM dbo.patient_card;
SELECT * FROM dbo.patient_insurance;
SELECT * FROM dbo.visit;
SELECT * FROM dbo.visit_service;
SELECT * FROM dbo.visit_xray;
SELECT * FROM dbo.payment;
SELECT * FROM dbo.visit_payment;
GO


USE Dental; 
GO

-- 1) List all base tables
SELECT TABLE_SCHEMA, TABLE_NAME
FROM INFORMATION_SCHEMA.TABLES
WHERE TABLE_TYPE = 'BASE TABLE'
ORDER BY TABLE_SCHEMA, TABLE_NAME;

-- 2) See columns for the likely tables (edit LIKE patterns if needed)
SELECT TABLE_NAME, COLUMN_NAME, DATA_TYPE
FROM INFORMATION_SCHEMA.COLUMNS
WHERE TABLE_NAME LIKE '%patient%' OR TABLE_NAME LIKE '%visit%' OR TABLE_NAME LIKE '%insur%'
   OR TABLE_NAME LIKE '%dent%'   OR TABLE_NAME LIKE '%hyg%'  OR TABLE_NAME LIKE '%card%'
   OR TABLE_NAME LIKE '%pay%'
ORDER BY TABLE_NAME, COLUMN_NAME;

-- 3) Quick scan for common column variants (edit list as needed)
SELECT TABLE_NAME, COLUMN_NAME
FROM INFORMATION_SCHEMA.COLUMNS
WHERE COLUMN_NAME IN ('PatientID','patient_id','PatID','CardID','card_id','VisitID','visit_id',
                      'FirstName','first_name','FName','LastName','last_name','LName',
                      'AmountPaid','amount_paid','PaidAmount','paid_amount')
ORDER BY TABLE_NAME, COLUMN_NAME;
