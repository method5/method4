CREATE OR REPLACE PACKAGE method4 AS

   /*
   || ---------------------------------------------------------------------------------
   ||
   || Name:        method4
   ||
   || Description: A PL/SQL application to run dynamic SQL in SQL.  This package
   ||              contains a single interface to a pipelined function implemented by
   ||              an object type (DLA_OT) using ANYDATASET.
   ||
   || Version:     This version is for Oracle 10.2.0.x and upwards.
   ||
   ||              Semantically and syntactically, this application should run on
   ||              10.1.x databases, but there is an ORA-0600 error which appears
   ||              to be a bug in the way ANYDATASET fetches CLOBs.
   ||
   || Notes:       1. The pipelined function returns a record structure that matches
   ||                 the column structure of the underlying DBA_% view (or query
   ||                 from that view). The only exception to this is of course the
   ||                 LONG column, which is returned from each DBA_% view as a CLOB.
   ||
   ||              2. The ANYDATASET interface has been available as a Data Cartridge
   ||                 since Oracle 9i. However, the ODCI methods needed to enable dynamic
   ||                 describe of a SQL statement were not available until 10g (that is,
   ||                 we could only interface to a known query structure). 10g enables
   ||                 us to combine DBMS_SQL with ANYDATASET/ANYTYPE methods to build
   ||                 a self-describing return structure for the first time.
   ||
   ||
   || Usage:       a) Run a query.
   ||              --------------------------------------------
   ||              select * from table(method4.run('select * from dual'));
   ||
   ||              b) Run a query to build another query that produces results.
   ||              ------------------------------------------------------
   ||
   ||              select * from table(method4.run(
   ||                 p_stmt =>
   ||                    q'[
   ||                       select 'select '''||table_name||''' table_name, count(*) a from '||table_name sql
   ||                       from user_tables
   ||                       where table_name like 'TEST%'
   ||                    ]',
   ||                 p_re_eval => 'YES'
   ||              ));
   ||
   ||              ------------------------------------------------------
   ||              (c) Adrian Billington, www.oracle-developer.net.
   ||
   || ---------------------------------------------------------------------------------
   */

   /*
   || Pipelined function interface.
   */
   FUNCTION run(
            p_stmt    IN VARCHAR2,
            p_re_eval IN VARCHAR2 DEFAULT 'NO'
            ) RETURN ANYDATASET PIPELINED USING method4_ot;

   /*
   || Record types for use across multiple DLA_OT methods.
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
   , schema    VARCHAR2(30)
   , type      ANYTYPE
   , name      VARCHAR2(30)
   , version   VARCHAR2(30)
   , attr_cnt  PLS_INTEGER
   , attr_type ANYTYPE
   , attr_name VARCHAR2(128)
   , typecode  PLS_INTEGER
   );

   /*
   || State variable for use across multiple DLA_OT methods.
   */
   r_sql rt_dynamic_sql;

END method4;
/
