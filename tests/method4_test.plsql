create or replace package method4_test authid current_user is
/*
== Purpose ==

Unit tests for Method4.


== Example ==

begin
	method4_test.run;
end;

*/

--Run the unit tests and display the results in dbms output.
procedure run;

end;
/
create or replace package body method4_test is

--Global counters.
g_test_count number := 0;
g_passed_count number := 0;
g_failed_count number := 0;

--------------------------------------------------------------------------------
procedure assert_equals(p_test nvarchar2, p_expected nvarchar2, p_actual nvarchar2) is
begin
	g_test_count := g_test_count + 1;

	if p_expected = p_actual or p_expected is null and p_actual is null then
		g_passed_count := g_passed_count + 1;
	else
		g_failed_count := g_failed_count + 1;
		dbms_output.put_line('Failure with: '||p_test);
		dbms_output.put_line('Expected: '||p_expected);
		dbms_output.put_line('Actual  : '||p_actual);
	end if;
end assert_equals;


--------------------------------------------------------------------------------
procedure test_convert_to_text is
begin
	--Simple.
	declare
		actual varchar2(1);
	begin
		execute immediate
		q'<
			select *
			from table(method4.run('select * from dual'))
		>'
		into actual;

		assert_equals('Simple.', 'X', actual);
	end;

	--TODO

	--Calling with second parameter other than YES or NO raises an exception.
	declare
		actual varchar2(1);
	begin
		execute immediate
		q'<
			select *
			from table(method4.run('select * from dual', 'FALSE'))
		>'
		into actual;

		assert_equals('Simple.', 'X', actual);
	end;

	--Different datatypes.

	--DBA objects.

	--Long column names.

	--Re-evaluation, only one query.

	--Re-evaluation, multiple queries.

end test_convert_to_text;


--------------------------------------------------------------------------------
procedure run is
begin
	--Reset counters.
	g_test_count := 0;
	g_passed_count := 0;
	g_failed_count := 0;

	--Print header.
	dbms_output.put_line(null);
	dbms_output.put_line('----------------------------------------');
	dbms_output.put_line('Method4 Test Summary');
	dbms_output.put_line('----------------------------------------');

	--Run the tests.
	test_convert_to_text;

	--Print summary of results.
	dbms_output.put_line(null);
	dbms_output.put_line('Total : '||g_test_count);
	dbms_output.put_line('Passed: '||g_passed_count);
	dbms_output.put_line('Failed: '||g_failed_count);

	--Print easy to read pass or fail message.
	if g_failed_count = 0 then
		dbms_output.put_line('
  _____         _____ _____
 |  __ \ /\    / ____/ ____|
 | |__) /  \  | (___| (___
 |  ___/ /\ \  \___ \\___ \
 | |  / ____ \ ____) |___) |
 |_| /_/    \_\_____/_____/');
	else
		dbms_output.put_line('
  ______      _____ _
 |  ____/\   |_   _| |
 | |__ /  \    | | | |
 |  __/ /\ \   | | | |
 | | / ____ \ _| |_| |____
 |_|/_/    \_\_____|______|');
	end if;
end run;

end;
/
