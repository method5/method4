CREATE OR REPLACE TYPE method4_pivot_ot AUTHID CURRENT_USER AS OBJECT
--See Method4 package specification for details.
(
  atype ANYTYPE --<-- transient record type

, STATIC FUNCTION Get_Pivot_SQL(
                  P_SQL                IN VARCHAR2,
                  P_AGGREGATE_FUNCTION IN VARCHAR2
                  ) RETURN VARCHAR2

, STATIC FUNCTION ODCITableDescribe(
                  rtype   OUT ANYTYPE,
                  stmt    IN  VARCHAR2,
                  p_aggregate_function IN VARCHAR2 DEFAULT 'MAX'
                  ) RETURN NUMBER

, STATIC FUNCTION ODCITablePrepare(
                  sctx    OUT method4_pivot_ot,
                  tf_info IN  sys.ODCITabFuncInfo,
                  stmt    IN  VARCHAR2,
                  p_aggregate_function IN VARCHAR2 DEFAULT 'MAX'
                  ) RETURN NUMBER

, STATIC FUNCTION ODCITableStart(
                  sctx    IN OUT method4_pivot_ot,
                  stmt    IN     VARCHAR2,
                  p_aggregate_function IN VARCHAR2 DEFAULT 'MAX'
                  ) RETURN NUMBER

, MEMBER FUNCTION ODCITableFetch(
                  SELF  IN OUT method4_pivot_ot,
                  nrows IN     NUMBER,
                  rws   OUT    anydataset
                  ) RETURN NUMBER

, MEMBER FUNCTION ODCITableClose(
                  SELF IN method4_pivot_ot
                  ) RETURN NUMBER

) NOT FINAL INSTANTIABLE;
/
