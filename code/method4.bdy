create or replace package body method4 as

--Purge SQL_IDs to force hard-parsing.
--
--Purging is necessary because the dynamic SQL prevents Oracle from knowing when a dependent object
-- change requires not using cached plans and data.
--
--This procedure must be called in ODCITableStart, not in ODCITablePrepare or ODCITableDescribe.
--
--(Even though the types change the input SQL statement, that change is not good enough to prevent
-- caching problems. Purging is the only solution I have found.)
procedure purge_sql(p_search_string varchar2) is
	type string_table is table of varchar2(32767);
	v_purge_statements string_table;
begin
	--Find the SQL statements used to call Method4.
	--Dynamic SQL is used to simplify permissions.
	execute immediate replace(
		q'[
			select 'begin sys.dbms_shared_pool.purge('''||address||' '||hash_value||''', ''C''); end;' v_sql
			from sys.gv_$sql
			where lower(sql_text) like '%#SEARCH_STRING#%'
		]'
	, '#SEARCH_STRING#', p_search_string)
	bulk collect into v_purge_statements;

	--Execute the purge blocks.
	for i in 1 .. v_purge_statements.count loop
		execute immediate v_purge_statements(i);
	end loop;
end purge_sql;

procedure check_for_null_stmt(stmt varchar2) is
begin
	if stmt is null then
		raise_application_error(-20000,
		replace(replace(q'[
			The SQL statement parameter cannot be null and cannot use a bind variable. 
			(This limitation is because dynamic table functions use ODCITableDescribe which is called 
			at compile time and does not have access to bind variables.) 
			If you are not intentionally using a bid variable you may need to check if the parameter 
			CURSOR_SHARING is set to FORCE. 
			You can override that parameter at the session level by running "alter session set 
			cursor_sharing='exact'", and you can override the parameter at the statement level by 
			using a hint like "select /*+ cursor_sharing_exact */ * from table(method4...". 
			You may also need to run "alter system flush shared_pool" once to remove cached execution 
			plans for the previous errors.
		]', chr(10)), '	'));
	end if;
end check_for_null_stmt;

procedure set_temp_object_id(p_temp_object_id varchar2) is
begin
	dbms_session.set_context('method4_context', 'temp_object_id', p_temp_object_id);
end;

procedure set_owner(p_owner varchar2) is
begin
	dbms_session.set_context('method4_context', 'owner', p_owner);
end;

procedure set_table_name(p_table_name varchar2) is
begin
	dbms_session.set_context('method4_context', 'table_name', p_table_name);
end;

end method4;
/
