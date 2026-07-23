/*==============================================================================
  BANKING SYSTEM - DATABASE AUDIT LOGGING SOLUTION
  Author : Group members:
•	31322/2025
•	31234/2025
•	31882/2025
•	32657/2025
•	

  Course : Database Programming - Lecture 9 (Triggers)
  Purpose: Track every INSERT / UPDATE / DELETE on six critical banking
           tables (ALLOWANCES, ATTENDANCE, COUNTRIES, DEPARTMENTS,
           EMPLOYEES, ROLES) using row-level AFTER triggers, plus two
           stored procedures with exception handling for ALLOWANCES.
==============================================================================*/


/*==============================================================================
  SECTION 0: BASE SCHEMA
  These six tables are the "critical tables" the assignment refers to.
  They are not explicitly defined in the brief, so a standard banking-HR
  structure is used here so the audit triggers have real tables to fire on.
==============================================================================*/

CREATE TABLE countries (
    country_id      NUMBER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    country_name    VARCHAR2(50)  NOT NULL,
    country_code    VARCHAR2(5)
);

CREATE TABLE departments (
    department_id    NUMBER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    department_name  VARCHAR2(50) NOT NULL,
    country_id       NUMBER,
    CONSTRAINT fk_dept_country FOREIGN KEY (country_id)
        REFERENCES countries (country_id)
);

CREATE TABLE roles (
    role_id       NUMBER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    role_name     VARCHAR2(50) NOT NULL,
    base_salary   NUMBER(12,2)
);

CREATE TABLE employees (
    employee_id     NUMBER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    first_name      VARCHAR2(50)  NOT NULL,
    last_name       VARCHAR2(50)  NOT NULL,
    email           VARCHAR2(100) UNIQUE,
    hire_date       DATE DEFAULT SYSDATE,
    department_id   NUMBER,
    role_id         NUMBER,
    CONSTRAINT fk_emp_dept FOREIGN KEY (department_id)
        REFERENCES departments (department_id),
    CONSTRAINT fk_emp_role FOREIGN KEY (role_id)
        REFERENCES roles (role_id)
);

CREATE TABLE attendance (
    attendance_id     NUMBER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    employee_id       NUMBER NOT NULL,
    attendance_date   DATE DEFAULT SYSDATE,
    status            VARCHAR2(20)
        CHECK (status IN ('PRESENT','ABSENT','LATE','ON_LEAVE')),
    CONSTRAINT fk_att_emp FOREIGN KEY (employee_id)
        REFERENCES employees (employee_id)
);

CREATE TABLE allowances (
    allowance_id     NUMBER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    employee_id      NUMBER NOT NULL,
    allowance_type   VARCHAR2(30),
    amount           NUMBER(10,2),
    allowance_date   DATE DEFAULT SYSDATE,
    CONSTRAINT fk_allow_emp FOREIGN KEY (employee_id)
        REFERENCES employees (employee_id)
);


/*==============================================================================
  TASK 1: AUDIT TABLE
  Generic table that stores audit rows for ALL six monitored tables.
  old_data / new_data are CLOBs holding a "COLUMN=value" snapshot of the row,
  since a single audit table cannot have per-table typed columns.
==============================================================================*/

CREATE TABLE audit_log (
    audit_id             NUMBER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    operation_type       VARCHAR2(10)  NOT NULL,   -- INSERT / UPDATE / DELETE
    object_name          VARCHAR2(30)  NOT NULL,   -- table the change happened on
    operation_user       VARCHAR2(30)  NOT NULL,   -- DB user who made the change
    operation_timestamp  TIMESTAMP DEFAULT SYSTIMESTAMP,
    old_data             CLOB,                     -- row image BEFORE the change
    new_data             CLOB                      -- row image AFTER the change
);


/*==============================================================================
  ERROR LOG TABLE (supports Task 3)
==============================================================================*/

CREATE TABLE error_log (
    error_id           NUMBER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    procedure_name     VARCHAR2(50),
    error_message      VARCHAR2(4000),
    error_code         NUMBER,
    error_timestamp    TIMESTAMP DEFAULT SYSTIMESTAMP
);


/*==============================================================================
  Helper procedure: LOG_ERROR
  Uses PRAGMA AUTONOMOUS_TRANSACTION so an error record is written and
  committed independently, even if the calling procedure later rolls back.
  This is called from every exception handler in Task 3.
==============================================================================*/

CREATE OR REPLACE PROCEDURE log_error (
    p_procedure_name IN VARCHAR2,
    p_error_message  IN VARCHAR2,
    p_error_code     IN NUMBER
)
IS
    PRAGMA AUTONOMOUS_TRANSACTION;
BEGIN
    INSERT INTO error_log (procedure_name, error_message, error_code, error_timestamp)
    VALUES (p_procedure_name, p_error_message, p_error_code, SYSTIMESTAMP);
    COMMIT;
END log_error;
/


/*==============================================================================
  TASK 2: DML AUDIT TRIGGERS
  One AFTER INSERT OR UPDATE OR DELETE, FOR EACH ROW trigger per table.
  Each trigger builds a readable "COLUMN=value" string for old/new row
  images and inserts one row into AUDIT_LOG.
==============================================================================*/

-- 2.1 ALLOWANCES -------------------------------------------------------------
CREATE OR REPLACE TRIGGER trg_allowances_audit
AFTER INSERT OR UPDATE OR DELETE ON allowances
FOR EACH ROW
DECLARE
    v_operation VARCHAR2(10);
    v_old_data  CLOB;
    v_new_data  CLOB;
BEGIN
    IF INSERTING THEN
        v_operation := 'INSERT';
        v_new_data  := 'ALLOWANCE_ID=' || :NEW.allowance_id ||
                        ', EMPLOYEE_ID=' || :NEW.employee_id ||
                        ', ALLOWANCE_TYPE=' || :NEW.allowance_type ||
                        ', AMOUNT=' || :NEW.amount ||
                        ', ALLOWANCE_DATE=' || TO_CHAR(:NEW.allowance_date,'YYYY-MM-DD');
    ELSIF UPDATING THEN
        v_operation := 'UPDATE';
        v_old_data  := 'ALLOWANCE_ID=' || :OLD.allowance_id ||
                        ', EMPLOYEE_ID=' || :OLD.employee_id ||
                        ', ALLOWANCE_TYPE=' || :OLD.allowance_type ||
                        ', AMOUNT=' || :OLD.amount ||
                        ', ALLOWANCE_DATE=' || TO_CHAR(:OLD.allowance_date,'YYYY-MM-DD');
        v_new_data  := 'ALLOWANCE_ID=' || :NEW.allowance_id ||
                        ', EMPLOYEE_ID=' || :NEW.employee_id ||
                        ', ALLOWANCE_TYPE=' || :NEW.allowance_type ||
                        ', AMOUNT=' || :NEW.amount ||
                        ', ALLOWANCE_DATE=' || TO_CHAR(:NEW.allowance_date,'YYYY-MM-DD');
    ELSIF DELETING THEN
        v_operation := 'DELETE';
        v_old_data  := 'ALLOWANCE_ID=' || :OLD.allowance_id ||
                        ', EMPLOYEE_ID=' || :OLD.employee_id ||
                        ', ALLOWANCE_TYPE=' || :OLD.allowance_type ||
                        ', AMOUNT=' || :OLD.amount ||
                        ', ALLOWANCE_DATE=' || TO_CHAR(:OLD.allowance_date,'YYYY-MM-DD');
    END IF;

    INSERT INTO audit_log (operation_type, object_name, operation_user,
                            operation_timestamp, old_data, new_data)
    VALUES (v_operation, 'ALLOWANCES', USER, SYSTIMESTAMP, v_old_data, v_new_data);
END;
/

-- 2.2 ATTENDANCE --------------------------------------------------------------
CREATE OR REPLACE TRIGGER trg_attendance_audit
AFTER INSERT OR UPDATE OR DELETE ON attendance
FOR EACH ROW
DECLARE
    v_operation VARCHAR2(10);
    v_old_data  CLOB;
    v_new_data  CLOB;
BEGIN
    IF INSERTING THEN
        v_operation := 'INSERT';
        v_new_data  := 'ATTENDANCE_ID=' || :NEW.attendance_id ||
                        ', EMPLOYEE_ID=' || :NEW.employee_id ||
                        ', ATTENDANCE_DATE=' || TO_CHAR(:NEW.attendance_date,'YYYY-MM-DD') ||
                        ', STATUS=' || :NEW.status;
    ELSIF UPDATING THEN
        v_operation := 'UPDATE';
        v_old_data  := 'ATTENDANCE_ID=' || :OLD.attendance_id ||
                        ', EMPLOYEE_ID=' || :OLD.employee_id ||
                        ', ATTENDANCE_DATE=' || TO_CHAR(:OLD.attendance_date,'YYYY-MM-DD') ||
                        ', STATUS=' || :OLD.status;
        v_new_data  := 'ATTENDANCE_ID=' || :NEW.attendance_id ||
                        ', EMPLOYEE_ID=' || :NEW.employee_id ||
                        ', ATTENDANCE_DATE=' || TO_CHAR(:NEW.attendance_date,'YYYY-MM-DD') ||
                        ', STATUS=' || :NEW.status;
    ELSIF DELETING THEN
        v_operation := 'DELETE';
        v_old_data  := 'ATTENDANCE_ID=' || :OLD.attendance_id ||
                        ', EMPLOYEE_ID=' || :OLD.employee_id ||
                        ', ATTENDANCE_DATE=' || TO_CHAR(:OLD.attendance_date,'YYYY-MM-DD') ||
                        ', STATUS=' || :OLD.status;
    END IF;

    INSERT INTO audit_log (operation_type, object_name, operation_user,
                            operation_timestamp, old_data, new_data)
    VALUES (v_operation, 'ATTENDANCE', USER, SYSTIMESTAMP, v_old_data, v_new_data);
END;
/

-- 2.3 COUNTRIES -----------------------------------------------------------
CREATE OR REPLACE TRIGGER trg_countries_audit
AFTER INSERT OR UPDATE OR DELETE ON countries
FOR EACH ROW
DECLARE
    v_operation VARCHAR2(10);
    v_old_data  CLOB;
    v_new_data  CLOB;
BEGIN
    IF INSERTING THEN
        v_operation := 'INSERT';
        v_new_data  := 'COUNTRY_ID=' || :NEW.country_id ||
                        ', COUNTRY_NAME=' || :NEW.country_name ||
                        ', COUNTRY_CODE=' || :NEW.country_code;
    ELSIF UPDATING THEN
        v_operation := 'UPDATE';
        v_old_data  := 'COUNTRY_ID=' || :OLD.country_id ||
                        ', COUNTRY_NAME=' || :OLD.country_name ||
                        ', COUNTRY_CODE=' || :OLD.country_code;
        v_new_data  := 'COUNTRY_ID=' || :NEW.country_id ||
                        ', COUNTRY_NAME=' || :NEW.country_name ||
                        ', COUNTRY_CODE=' || :NEW.country_code;
    ELSIF DELETING THEN
        v_operation := 'DELETE';
        v_old_data  := 'COUNTRY_ID=' || :OLD.country_id ||
                        ', COUNTRY_NAME=' || :OLD.country_name ||
                        ', COUNTRY_CODE=' || :OLD.country_code;
    END IF;

    INSERT INTO audit_log (operation_type, object_name, operation_user,
                            operation_timestamp, old_data, new_data)
    VALUES (v_operation, 'COUNTRIES', USER, SYSTIMESTAMP, v_old_data, v_new_data);
END;
/

-- 2.4 DEPARTMENTS -----------------------------------------------------------
CREATE OR REPLACE TRIGGER trg_departments_audit
AFTER INSERT OR UPDATE OR DELETE ON departments
FOR EACH ROW
DECLARE
    v_operation VARCHAR2(10);
    v_old_data  CLOB;
    v_new_data  CLOB;
BEGIN
    IF INSERTING THEN
        v_operation := 'INSERT';
        v_new_data  := 'DEPARTMENT_ID=' || :NEW.department_id ||
                        ', DEPARTMENT_NAME=' || :NEW.department_name ||
                        ', COUNTRY_ID=' || :NEW.country_id;
    ELSIF UPDATING THEN
        v_operation := 'UPDATE';
        v_old_data  := 'DEPARTMENT_ID=' || :OLD.department_id ||
                        ', DEPARTMENT_NAME=' || :OLD.department_name ||
                        ', COUNTRY_ID=' || :OLD.country_id;
        v_new_data  := 'DEPARTMENT_ID=' || :NEW.department_id ||
                        ', DEPARTMENT_NAME=' || :NEW.department_name ||
                        ', COUNTRY_ID=' || :NEW.country_id;
    ELSIF DELETING THEN
        v_operation := 'DELETE';
        v_old_data  := 'DEPARTMENT_ID=' || :OLD.department_id ||
                        ', DEPARTMENT_NAME=' || :OLD.department_name ||
                        ', COUNTRY_ID=' || :OLD.country_id;
    END IF;

    INSERT INTO audit_log (operation_type, object_name, operation_user,
                            operation_timestamp, old_data, new_data)
    VALUES (v_operation, 'DEPARTMENTS', USER, SYSTIMESTAMP, v_old_data, v_new_data);
END;
/

-- 2.5 EMPLOYEES ---------------------------------------------------------------
CREATE OR REPLACE TRIGGER trg_employees_audit
AFTER INSERT OR UPDATE OR DELETE ON employees
FOR EACH ROW
DECLARE
    v_operation VARCHAR2(10);
    v_old_data  CLOB;
    v_new_data  CLOB;
BEGIN
    IF INSERTING THEN
        v_operation := 'INSERT';
        v_new_data  := 'EMPLOYEE_ID=' || :NEW.employee_id ||
                        ', FIRST_NAME=' || :NEW.first_name ||
                        ', LAST_NAME=' || :NEW.last_name ||
                        ', EMAIL=' || :NEW.email ||
                        ', DEPARTMENT_ID=' || :NEW.department_id ||
                        ', ROLE_ID=' || :NEW.role_id;
    ELSIF UPDATING THEN
        v_operation := 'UPDATE';
        v_old_data  := 'EMPLOYEE_ID=' || :OLD.employee_id ||
                        ', FIRST_NAME=' || :OLD.first_name ||
                        ', LAST_NAME=' || :OLD.last_name ||
                        ', EMAIL=' || :OLD.email ||
                        ', DEPARTMENT_ID=' || :OLD.department_id ||
                        ', ROLE_ID=' || :OLD.role_id;
        v_new_data  := 'EMPLOYEE_ID=' || :NEW.employee_id ||
                        ', FIRST_NAME=' || :NEW.first_name ||
                        ', LAST_NAME=' || :NEW.last_name ||
                        ', EMAIL=' || :NEW.email ||
                        ', DEPARTMENT_ID=' || :NEW.department_id ||
                        ', ROLE_ID=' || :NEW.role_id;
    ELSIF DELETING THEN
        v_operation := 'DELETE';
        v_old_data  := 'EMPLOYEE_ID=' || :OLD.employee_id ||
                        ', FIRST_NAME=' || :OLD.first_name ||
                        ', LAST_NAME=' || :OLD.last_name ||
                        ', EMAIL=' || :OLD.email ||
                        ', DEPARTMENT_ID=' || :OLD.department_id ||
                        ', ROLE_ID=' || :OLD.role_id;
    END IF;

    INSERT INTO audit_log (operation_type, object_name, operation_user,
                            operation_timestamp, old_data, new_data)
    VALUES (v_operation, 'EMPLOYEES', USER, SYSTIMESTAMP, v_old_data, v_new_data);
END;
/

-- 2.6 ROLES ---------------------------------------------------------------------
CREATE OR REPLACE TRIGGER trg_roles_audit
AFTER INSERT OR UPDATE OR DELETE ON roles
FOR EACH ROW
DECLARE
    v_operation VARCHAR2(10);
    v_old_data  CLOB;
    v_new_data  CLOB;
BEGIN
    IF INSERTING THEN
        v_operation := 'INSERT';
        v_new_data  := 'ROLE_ID=' || :NEW.role_id ||
                        ', ROLE_NAME=' || :NEW.role_name ||
                        ', BASE_SALARY=' || :NEW.base_salary;
    ELSIF UPDATING THEN
        v_operation := 'UPDATE';
        v_old_data  := 'ROLE_ID=' || :OLD.role_id ||
                        ', ROLE_NAME=' || :OLD.role_name ||
                        ', BASE_SALARY=' || :OLD.base_salary;
        v_new_data  := 'ROLE_ID=' || :NEW.role_id ||
                        ', ROLE_NAME=' || :NEW.role_name ||
                        ', BASE_SALARY=' || :NEW.base_salary;
    ELSIF DELETING THEN
        v_operation := 'DELETE';
        v_old_data  := 'ROLE_ID=' || :OLD.role_id ||
                        ', ROLE_NAME=' || :OLD.role_name ||
                        ', BASE_SALARY=' || :OLD.base_salary;
    END IF;

    INSERT INTO audit_log (operation_type, object_name, operation_user,
                            operation_timestamp, old_data, new_data)
    VALUES (v_operation, 'ROLES', USER, SYSTIMESTAMP, v_old_data, v_new_data);
END;
/


/*==============================================================================
  TASK 3: STORED PROCEDURES WITH EXCEPTION HANDLING (ALLOWANCES)
==============================================================================*/

-- 3.1 UPDATE ------------------------------------------------------------------
CREATE OR REPLACE PROCEDURE sp_update_allowance (
    p_allowance_id    IN allowances.allowance_id%TYPE,
    p_allowance_type  IN allowances.allowance_type%TYPE,
    p_amount          IN allowances.amount%TYPE
)
IS
    e_not_found EXCEPTION;
BEGIN
    UPDATE allowances
    SET    allowance_type = p_allowance_type,
           amount         = p_amount
    WHERE  allowance_id   = p_allowance_id;

    IF SQL%ROWCOUNT = 0 THEN
        RAISE e_not_found;
    END IF;

    COMMIT;

EXCEPTION
    WHEN e_not_found THEN
        log_error('SP_UPDATE_ALLOWANCE',
                   'No allowance found with ID ' || p_allowance_id, -20001);
        ROLLBACK;
    WHEN OTHERS THEN
        log_error('SP_UPDATE_ALLOWANCE', SQLERRM, SQLCODE);
        ROLLBACK;
END sp_update_allowance;
/

-- 3.2 DELETE ------------------------------------------------------------------
CREATE OR REPLACE PROCEDURE sp_delete_allowance (
    p_allowance_id IN allowances.allowance_id%TYPE
)
IS
    e_not_found EXCEPTION;
BEGIN
    DELETE FROM allowances
    WHERE  allowance_id = p_allowance_id;

    IF SQL%ROWCOUNT = 0 THEN
        RAISE e_not_found;
    END IF;

    COMMIT;

EXCEPTION
    WHEN e_not_found THEN
        log_error('SP_DELETE_ALLOWANCE',
                   'No allowance found with ID ' || p_allowance_id, -20002);
        ROLLBACK;
    WHEN OTHERS THEN
        log_error('SP_DELETE_ALLOWANCE', SQLERRM, SQLCODE);
        ROLLBACK;
END sp_delete_allowance;
/


/*==============================================================================
  TASK 4: TESTING AND VALIDATION
==============================================================================*/

-- 4.0 Seed data needed before ALLOWANCES can have a valid employee_id ---------
INSERT INTO countries (country_name, country_code) VALUES ('Rwanda', 'RW');

INSERT INTO departments (department_name, country_id) VALUES ('Human Resources', 1);

INSERT INTO roles (role_name, base_salary) VALUES ('Bank Teller', 350000);

INSERT INTO employees (first_name, last_name, email, department_id, role_id)
VALUES ('Jean', 'Uwimana', 'jean.uwimana@bank.rw', 1, 1);

COMMIT;

-- 4.1 TEST 1: INSERT -----------------------------------------------------------
INSERT INTO allowances (employee_id, allowance_type, amount)
VALUES (1, 'Transport', 50000);
COMMIT;

-- Expected: allowances has 1 row; audit_log has 1 INSERT row for ALLOWANCES
SELECT * FROM allowances;
SELECT * FROM audit_log WHERE object_name = 'ALLOWANCES' ORDER BY audit_id;

-- 4.2 TEST 2: UPDATE (via stored procedure) -------------------------------------
EXEC sp_update_allowance(1, 'Transport', 65000);

-- Expected: audit_log has an UPDATE row with OLD amount=50000, NEW amount=65000
SELECT * FROM audit_log WHERE object_name = 'ALLOWANCES' ORDER BY audit_id;

-- 4.3 TEST 3: DELETE (via stored procedure) -------------------------------------
EXEC sp_delete_allowance(1);

-- Expected: allowances table empty again; audit_log has a DELETE row
-- storing the deleted row as old_data
SELECT * FROM allowances;
SELECT * FROM audit_log WHERE object_name = 'ALLOWANCES' ORDER BY audit_id;

-- 4.4 TEST 4: ERROR HANDLING -----------------------------------------------------
-- Allowance ID 9999 does not exist -> should NOT raise an unhandled error,
-- it should be caught and logged into ERROR_LOG instead.
EXEC sp_update_allowance(9999, 'Housing', 100000);
EXEC sp_delete_allowance(9999);

SELECT * FROM error_log ORDER BY error_id;


/*==============================================================================
  DELIVERABLE 8: FINAL CONTENTS OF AUDIT_LOG AND ERROR_LOG
==============================================================================*/

SELECT audit_id, operation_type, object_name, operation_user,
       TO_CHAR(operation_timestamp, 'YYYY-MM-DD HH24:MI:SS') AS operation_time,
       old_data, new_data
FROM   audit_log
ORDER BY audit_id;

SELECT error_id, procedure_name, error_message, error_code,
       TO_CHAR(error_timestamp, 'YYYY-MM-DD HH24:MI:SS') AS error_time
FROM   error_log
ORDER BY error_id;
