CREATE OR REPLACE TYPE method4_dynamic_ot UNDER method4_ot
--See Method4 package specification for details.
(
  STATIC FUNCTION Re_Evaluate_Statement(
                  stmt    IN VARCHAR2
                  ) RETURN VARCHAR2

, STATIC FUNCTION ODCITableDescribe(
                  rtype   OUT ANYTYPE,
                  stmt    IN  VARCHAR2
                  ) RETURN NUMBER

, STATIC FUNCTION ODCITablePrepare(
                  sctx    OUT method4_dynamic_ot,
                  tf_info IN  sys.ODCITabFuncInfo,
                  stmt    IN  VARCHAR2
                  ) RETURN NUMBER

, STATIC FUNCTION ODCITableStart(
                  sctx    IN OUT method4_dynamic_ot,
                  stmt    IN     VARCHAR2
                  ) RETURN NUMBER

) NOT FINAL INSTANTIABLE;
/