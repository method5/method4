CREATE OR REPLACE PACKAGE method4 AUTHID CURRENT_USER AS

   C_VERSION constant varchar2(10) := '2.3.1';

   /*
   || ---------------------------------------------------------------------------------
   ||
   || Name:        Method4
   ||
   ||
   || Description: A PL/SQL application to run dynamic SQL in SQL. This package
   ||              contains interfaces to pipelind functions implemented by
   ||              types using ANYDATASET.
   ||
   ||
   || Usage:       See the README.md file for example.
   ||
   ||
   || Version:     This version is for Oracle 10.2.0.x and upwards.
   ||
   ||              Semantically and syntactically, this application should run on
   ||              10.1.x databases, but there is an ORA-0600 error which appears
   ||              to be a bug in the way ANYDATASET fetches CLOBs.
   ||
   || Notes:       1. The pipelined function returns a record structure that matches
   ||                 the column structure of the underlying query.
   ||                 The only exception is the LONG column, which is returned as a CLOB.
   ||
   ||              2. The ANYDATASET interface has been available as a Data Cartridge
   ||                 since Oracle 9i. However, the ODCI methods needed to enable dynamic
   ||                 describe of a SQL statement were not available until 10g (that is,
   ||                 we could only interface to a known query structure). 10g enables
   ||                 us to combine DBMS_SQL with ANYDATASET/ANYTYPE methods to build
   ||                 a self-describing return structure for the first time.
   ||
   ||              3. The boring type-conversion logic is stored in the type
   ||                 method4_ot. To intercept and modify SQL statements,
   ||                 extend method4_ot. See method4_dynamic_ot for an example.
   ||
   ||
   || License:     MIT License
   ||              Original work Copyright (c) 2007 Adrian Billington, www.oracle-developer.net
   ||              Modified work Copyright 2016 Jon Heller
   ||
   ||
   || ---------------------------------------------------------------------------------
   */

   /*
   || Pipelined function interface.
   */
   FUNCTION query(
            p_stmt    IN VARCHAR2
            ) RETURN ANYDATASET PIPELINED USING method4_ot;
   FUNCTION dynamic_query(
            p_stmt    IN VARCHAR2
            ) RETURN ANYDATASET PIPELINED USING method4_dynamic_ot;
   FUNCTION pivot(
            p_stmt               IN VARCHAR2,
            p_aggregate_function IN VARCHAR2 DEFAULT 'MAX'
            ) RETURN ANYDATASET PIPELINED USING method4_pivot_ot;
   FUNCTION poll_table(
            p_table_name              IN VARCHAR2,
            p_sql_statement_condition IN VARCHAR2,
            p_refresh_seconds         IN NUMBER DEFAULT 3
            ) RETURN ANYDATASET PIPELINED USING method4_poll_table_ot;

   /*
   || Record types for use across multiple METHOD4 methods.
   */
   TYPE rt_dynamic_sql IS RECORD
   ( cursor      INTEGER
   , column_cnt  PLS_INTEGER
   , description DBMS_SQL.DESC_TAB2
   , execute     INTEGER
   );

   TYPE rt_anytype_metadata IS RECORD
   ( precision PLS_INTEGER
   , scale     PLS_INTEGER
   , length    PLS_INTEGER
   , csid      PLS_INTEGER
   , csfrm     PLS_INTEGER
   , schema    VARCHAR2(128)
   , type      ANYTYPE
   --This must be 129, not 128.
   --For weird column names ANYTYPE.GetAttrElemInfo returns 129 bytes instead of 128.
   --(It did something similar in previous versions with the 30 byte limit. In past
   -- versions this value had to be 31 instead of 30.)
   , name      VARCHAR2(129)
   , version   VARCHAR2(30)
   , attr_cnt  PLS_INTEGER
   , attr_type ANYTYPE
   , attr_name VARCHAR2(129)
   , typecode  PLS_INTEGER
   );

   /*
   || State variable for use across multiple METHOD4 methods.
   */
   r_sql rt_dynamic_sql;

   TYPE statement_cache_type IS TABLE OF CLOB INDEX BY VARCHAR2(4000);
   r_statement_cache statement_cache_type;

   r_pivot_sql clob;

   --Common procedures used by multiple types.
   procedure purge_sql(p_search_string varchar2);
   procedure check_for_null_stmt(stmt varchar2);

   --Contexts used by METHOD4_POLL_TABLE.
   procedure set_temp_object_id(p_temp_object_id varchar2);
   procedure set_owner(p_owner varchar2);
   procedure set_table_name(p_table_name varchar2);

END method4;
/
