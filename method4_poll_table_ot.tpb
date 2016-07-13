CREATE OR REPLACE TYPE BODY method4_poll_table_ot AS
--See Method4 package specification for details.

--------------------------------------------------------------------------------
static function ODCITableDescribe(
	rtype                     out anytype,
	p_table_name              in varchar2,
	p_sql_statement_condition in varchar2,
	p_refresh_seconds         in number default 3
) return number is

--Template for the type.
v_type_template varchar2(32767) := '
create or replace type m4_temp_type_#ID is object(
	--This temporary type is used for a single call to METHOD4.POLL_TABLE.
	--It is safe to drop this object as long as that statement has completed.
	--Normally these object should be automatically dropped, but it is possible
	--for them to not get dropped if the SQL statement was cancelled.
'||/*prevent SQL*Plus parse error*/''||'#COLUMNS
)';

v_type_table_template varchar2(32767) := '
create or replace type m4_temp_table_#ID
is table of m4_temp_type_#ID
--This temporary type is used for a single call to METHOD4.POLL_TABLE.
--It is safe to drop this object as long as that statement has completed.
--Normally these object should be automatically dropped, but it is possible
--for them to not get dropped if the SQL statement was cancelled.';

v_function_template varchar2(32767) := q'[
create or replace function m4_temp_function_#ID return m4_temp_table_#ID pipelined authid current_user is
	v_cursor sys_refcursor;
	v_rows m4_temp_table_#ID;
	type number_table is table of number;
	v_ora_rowscns number_table;
	v_max_ora_rowscn number := 0;
	v_condition number;
begin
	--Continually poll table.
	loop
		--Open cursor to retrieve all new rows - those with a SCN higher than previous SCNs.
		open v_cursor for '
			select m4_temp_type_#ID(#COLUMNS) v_result, ora_rowscn
			from #OWNER.#TABLE_NAME
			where ora_rowscn > :v_max_ora_rowscn'
		using v_max_ora_rowscn;

		--Fetch and process data.
		loop
			--Dynamic SQL is used to simplify privileges.
			fetch v_cursor
			bulk collect into v_rows, v_ora_rowscns
			limit 100;

			exit when v_rows.count = 0;

			--Track SCN and pipe row.
			for i in 1 .. v_rows.count loop
				--Keep the highest SCN.
				if v_ora_rowscns(i) > v_max_ora_rowscn then
					v_max_ora_rowscn := v_ora_rowscns(i);
				end if;

				--Output the row.
				pipe row(v_rows(i));
			end loop;

		end loop;

		--Exit when condition is met.
		execute immediate '#CONDITION'
		into v_condition;
		exit when v_condition = 1;

		--Wait N seconds.
		--Use execute immediate to simplify privilege requirements.
		execute immediate 'begin dbms_lock.sleep(#SECONDS_TO_WAIT); end;';
	end loop;
end;
]';


	---------------------------------------
	--Purpose: Set common variables used in other methods.
	procedure set_context_attributes is
	begin
		--Create random id number to name the temporary objects.
		method4.set_temp_object_id(lpad(round(dbms_random.value * 1000000000), 9, '0'));

		--Get the owner and tablename.
		--
		--Split the value if there's a ".".
		if instr(p_table_name, ',') > 0 then
			method4.set_owner(upper(trim(substr(p_table_name, 1, instr(p_table_name, ',') - 1))));
			method4.set_table_name(upper(trim(substr(p_table_name, instr(p_table_name, ',') + 1))));
		--Assume the owner is the current_schema
		else
			method4.set_owner(sys_context('userenv', 'current_schema'));
			method4.set_table_name(upper(trim(p_table_name)));
		end if;
	end set_context_attributes;

	---------------------------------------
	--Purpose: Throw an error if the table has ROWDEPENDENCIES disabled.
	--	ORA_ROWSCN will not be accurate if that setting is not enabled.
	procedure check_for_rowdependencies is
		v_dependencies varchar2(4000);
	begin
		--Get dependencies.
		select dependencies
		into v_dependencies
		from all_tables
		where owner = sys_context('method4_context', 'owner')
			and table_name = sys_context('method4_context', 'table_name');

		--Throw error if it's not set to enabled.
		if v_dependencies = 'DISABLED' then
			raise_application_error(-20000, 'Row-level dependency tracking must be enabled on '||
				sys_context('method4_context', 'owner')||'.'||
				sys_context('method4_context', 'table_name')||' in order to track the changes.  '||
				'The table must be created with the keyword "ROWDEPENDENCIES", there is no '||
				'way to change the setting after the table is created.');
		end if;
	end;

	---------------------------------------
	--Purpose: Create the base type and the nested table type to hold results from the polling table.
	procedure create_temp_types is
		v_column_list varchar2(32767);
	begin
		--Add columns.
		--This is used instead of DBMS_METADATA because DBMS_METADATA is often too slow.
		for cols in
		(
			select *
			from all_tab_columns
			where owner = sys_context('method4_context', 'owner')
				and table_name = sys_context('method4_context', 'table_name')
			order by column_id
		) loop
			v_column_list := v_column_list || ',' || chr(10) || '	"'||cols.column_name||'" '||
				case
					when cols.data_type in ('NUMBER', 'FLOAT') then
						case
							when cols.data_precision is null and cols.data_scale is null then cols.data_type
							--For tables this could be "*", but "*" does not work with types.
							when cols.data_precision is null and cols.data_scale is not null then cols.data_type||'(38,'||cols.data_scale||')'
							when cols.data_precision is not null and cols.data_scale is null then cols.data_type||'('||cols.data_precision||')'
							when cols.data_precision is not null and cols.data_scale is not null then cols.data_type||'('||cols.data_precision||','||cols.data_scale||')'
						end
					when cols.data_type in ('CHAR', 'NCHAR', 'VARCHAR2', 'NVARCHAR2') then cols.data_type||'('||cols.data_length||' '||
						case cols.char_used when 'B' then 'byte' when 'C' then 'char' end || ')'
					when cols.data_type in ('RAW') then cols.data_type||'('||cols.data_length||')'
					else
						--DATE, TIMESTAMP, INTERVAL, many other types.
						cols.data_type
				end;
		end loop;

		--Create the type after replacing the columns and temp ID.
		execute immediate replace(replace(v_type_template, '#COLUMNS', substr(v_column_list, 3)), '#ID', sys_context('method4_context', 'temp_object_id'));

		--Create the nested table type after replacing the temp ID.
		execute immediate replace(v_type_table_template, '#ID', sys_context('method4_context', 'temp_object_id'));
	end create_temp_types;

	---------------------------------------
	--Purpose: Create the function that returns results from the table.
	procedure create_temp_function is
		v_column_list varchar2(32767);
	begin
		--Create comma-separated list of columns in the table.
		select listagg('"'||column_name||'"', ',') within group (order by column_id) column_list
		into v_column_list
		from all_tab_columns
		where owner = sys_context('method4_context', 'owner')
			and table_name = sys_context('method4_context', 'table_name');

		--Create the function
		execute immediate replace(replace(replace(replace(replace(replace(v_function_template,
			'#ID', sys_context('method4_context', 'temp_object_id')),
			'#OWNER', sys_context('method4_context', 'owner')),
			'#TABLE_NAME', sys_context('method4_context', 'table_name')),
			'#COLUMNS', v_column_list),
			'#CONDITION', replace(p_sql_statement_condition, '''', '''''')),
			'#SECONDS_TO_WAIT', p_refresh_seconds);
	end;

begin
	set_context_attributes;
	check_for_rowdependencies;
	create_temp_types;
	create_temp_function;
	--Yes, this commit is really necessary.
	--I don't know why, but without it the CREATE statements above don't work.
	commit;
	return method4_ot.odcitabledescribe(rtype, 'select * from table(M4_TEMP_FUNCTION_'||sys_context('method4_context', 'temp_object_id')||')');
end ODCITableDescribe;


   ----------------------------------------------------------------------------
   STATIC FUNCTION ODCITablePrepare(
                   sctx                      OUT method4_poll_table_ot,
                   tf_info                   IN  sys.ODCITabFuncInfo,
                   p_table_name              IN VARCHAR2,
                   p_sql_statement_condition IN VARCHAR2,
                   p_refresh_seconds         IN NUMBER DEFAULT 3
                   ) RETURN NUMBER IS

      super_sctx method4_ot;
      status     number;

  BEGIN
      super_sctx := sctx;
      status := method4_ot.ODCITablePrepare(super_sctx, tf_info, 'select * from table(M4_TEMP_FUNCTION_'||sys_context('method4_context', 'temp_object_id')||')');
      sctx := method4_poll_table_ot(super_sctx.atype);
      return odciconst.success;
   END;

   ----------------------------------------------------------------------------
   STATIC FUNCTION ODCITableStart(
                   sctx                      IN OUT method4_poll_table_ot,
                   p_table_name              IN VARCHAR2,
                   p_sql_statement_condition IN VARCHAR2,
                   p_refresh_seconds         IN NUMBER DEFAULT 3
                   ) RETURN NUMBER IS

      type string_table is table of varchar2(32767);
      v_sql_ids string_table;

  BEGIN
      --Find SQL_IDs of the SQL statements used to call Method4.
      --Use dynamic SQL to enable roles to select from GV$SQL.
      EXECUTE IMMEDIATE q'[
            select 'begin sys.dbms_shared_pool.purge('''||address||' '||hash_value||''', ''C''); end;' v_sql
            from sys.gv_$sql
            where lower(sql_text) like '%method4.poll_table%'
      ]'
      BULK COLLECT INTO v_sql_ids;

      --Purge each SQL_ID to force hard-parsing each time.
      --This cannot be done in the earlier Describe or Prepare phase or it will generate errors.
      FOR i IN 1 .. v_sql_ids.count LOOP
            EXECUTE IMMEDIATE v_sql_ids(i);
      END LOOP;

      RETURN method4_ot.ODCITableStart(sctx, 'select * from table(M4_TEMP_FUNCTION_'||sys_context('method4_context', 'temp_object_id')||')');
   END;

   ----------------------------------------------------------------------------
   OVERRIDING MEMBER FUNCTION ODCITableClose(
                   SELF IN method4_poll_table_ot
                   ) RETURN NUMBER IS
      PRAGMA AUTONOMOUS_TRANSACTION;
   BEGIN

      --Drop temporary types and functions.
      execute immediate 'drop function m4_temp_function_'||sys_context('method4_context', 'temp_object_id');
      execute immediate 'drop type m4_temp_table_'||sys_context('method4_context', 'temp_object_id');
      execute immediate 'drop type m4_temp_type_'||sys_context('method4_context', 'temp_object_id');

      DBMS_SQL.CLOSE_CURSOR( method4.r_sql.cursor );
      method4.r_sql := NULL;

      RETURN ODCIConst.Success;

   END;

END;
/
