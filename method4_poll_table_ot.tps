CREATE OR REPLACE TYPE method4_poll_table_ot UNDER method4_ot
--See Method4 package specification for details.
(
  STATIC FUNCTION ODCITableDescribe(
                  rtype                     OUT ANYTYPE,
                  p_table_name              IN VARCHAR2,
                  p_sql_statement_condition IN VARCHAR2,
                  p_refresh_seconds         IN NUMBER DEFAULT 3
                  ) RETURN NUMBER

, STATIC FUNCTION ODCITablePrepare(
                  sctx                      OUT method4_poll_table_ot,
                  tf_info                   IN  sys.ODCITabFuncInfo,
                  p_table_name              IN VARCHAR2,
                  p_sql_statement_condition IN VARCHAR2,
                  p_refresh_seconds         IN NUMBER DEFAULT 3
                  ) RETURN NUMBER

, STATIC FUNCTION ODCITableStart(
                  sctx                      IN OUT method4_poll_table_ot,
                  p_table_name              IN VARCHAR2,
                  p_sql_statement_condition IN VARCHAR2,
                  p_refresh_seconds         IN NUMBER DEFAULT 3
                  ) RETURN NUMBER

, OVERRIDING MEMBER FUNCTION ODCITableClose(
                  SELF IN method4_poll_table_ot
                  ) RETURN NUMBER

) NOT FINAL INSTANTIABLE;
/
