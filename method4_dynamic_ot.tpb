CREATE OR REPLACE TYPE BODY method4_dynamic_ot AS
--See Method4 package specification for details.

	----------------------------------------------------------------------------
	--Purpose: Create new SQL statement by concatenating result of original
	--	statement with UNION ALLs.
	--
	--If you want to modify Method4, this is probably the spot to add your code.
	--
	--re_eval: "YES" to re-evaluate SQL statement to generate a new statement.
	--	"NO" to use the original string as-is.
	static function re_evaluate_statement(
		stmt    in varchar2
	) return varchar2 is
		v_new_stmt clob;
		--pre-defind table of varchar2(4000).
		sql_statements sys.ku$_vcnt;
	begin
		--Use cached statement if available.
		if method4.r_statement_cache.exists(stmt) then
			v_new_stmt := method4.r_statement_cache(stmt);
		--Else retrieve the statement.
		else
			--Get all the statements.
			execute immediate stmt
			bulk collect into sql_statements;

			--Throw error if it returned no rows.
			if sql_statements.count = 0 then
				raise_application_error(-20000, 'The SQL statement did not generate any other SQL statements.');
			end if;

			--Convert them into a single large union-all statement.
			for i in 1 .. sql_statements.count loop
				if i = 1 then
					v_new_stmt := sql_statements(i);
				else
					v_new_stmt := v_new_stmt || chr(10) || 'union all' || chr(10) || sql_statements(i);
				end if;
			end loop;

			--Save it in the cache.
			method4.r_statement_cache(stmt) := v_new_stmt;
		end if;

		return v_new_stmt;
	end re_evaluate_statement;


   ----------------------------------------------------------------------------
   STATIC FUNCTION ODCITableDescribe(
                   rtype   OUT ANYTYPE,
                   stmt    IN  VARCHAR2
                   ) RETURN NUMBER IS
  BEGIN
      RETURN method4_ot.ODCITableDescribe(rtype, re_evaluate_statement(stmt));
   END;

   ----------------------------------------------------------------------------
   STATIC FUNCTION ODCITablePrepare(
                   sctx    OUT method4_dynamic_ot,
                   tf_info IN  sys.ODCITabFuncInfo,
                   stmt    IN  VARCHAR2
                   ) RETURN NUMBER IS

      super_sctx method4_ot;
      status     number;

  BEGIN
      super_sctx := sctx;
      status := method4_ot.ODCITablePrepare(super_sctx, tf_info, re_evaluate_statement(stmt));
      sctx := method4_dynamic_ot(super_sctx.atype);
      return odciconst.success;
   END;

   ----------------------------------------------------------------------------
   STATIC FUNCTION ODCITableStart(
                   sctx IN OUT method4_dynamic_ot,
                   stmt IN     VARCHAR2
                   ) RETURN NUMBER IS
  BEGIN
      RETURN method4_ot.ODCITableStart(sctx, re_evaluate_statement(stmt));
   END;

END;
/