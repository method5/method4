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

end method4;
/
