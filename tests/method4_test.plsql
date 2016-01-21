create or replace package method4_test authid current_user is
/*
== Purpose ==

Unit tests for Method4.


== Example ==

begin
	method4_test.run;
end;

When testing it is often helpful to run this block first:

begin
	dbms_session.reset_package;
	execute immediate 'alter system flush shared_pool';
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

	--Calling with second parameter other than YES or NO raises an exception.
	declare
		actual varchar2(1);
		bad_parmaeter exception;
		pragma exception_init(bad_parmaeter, -20000);
	begin
		execute immediate
		q'<
			select *
			from table(method4.run('select * from dual', 'FALSE'))
		>'
		into actual;

		assert_equals('Exception for bad parameter.', 'Exception', 'No exception');
	exception when bad_parmaeter then
		assert_equals('Exception for bad parameter.', 'Exception', 'Exception');
	end;

	--DBA objects.
	declare
		actual number;
	begin
		execute immediate q'<select * from table(method4.run('select count(*) from dba_users where rownum = 1'))>'
		into actual;
		assert_equals('DBA objects.', '1', actual);
	end;

	--Long column names.
	declare
		actual number;
	begin
		execute immediate q'<select * from table(method4.run('select count(*)+0+0+0+0+0+0+0+0+0+0+0 from dba_users where rownum = 1'))>'
		into actual;
		assert_equals('Long, default column name with 30 bytes.', '1', actual);
	end;

	declare
		actual number;
	begin
		execute immediate q'<select * from table(method4.run('select count(*)+0+0+0+0+0+0+0+0+0+0+0+0+0+0+0+0+0+0+0+0+0+0 from dba_users where rownum = 1'))>'
		into actual;
		assert_equals('Long, default column name with > 30 bytes.', '1', actual);
	end;

	--Re-evaluation, only one query.

	--Re-evaluation, multiple queries.


	-------------------------------------------------------------------------------
	--Listed in order of "Table 2-1 Built-in Data Type Summary" from SQL Language Reference.
	-------------------------------------------------------------------------------

	--Varchar2.
	declare
		actual1 varchar2(1);
		actual2 varchar2(100);
		actual3 varchar2(4000);
	begin
		execute immediate
		q'<
			select *
			from table(method4.run('select ''A'', cast(''B'' as varchar2(1)), lpad(''C'', 4000, ''C'') from dual'))
		>'
		into actual1, actual2, actual3;

		assert_equals('Varchar2 1.', 'A', actual1);
		assert_equals('Varchar2 2.', 'B', actual2);
		assert_equals('Varchar2 3.', lpad('C', 4000, 'C'), actual3);
	end;

	--NVarchar2.
	declare
		actual1 nvarchar2(1);
		actual2 nvarchar2(100);
		actual3 nvarchar2(4000);
	begin
		execute immediate
		q'<
			select *
			from table(method4.run('select n''A'', cast(''B'' as nvarchar2(1)), lpad(n''C'', 1000, n''C'') from dual'))
		>'
		into actual1, actual2, actual3;

		assert_equals('NVarchar2 1.', n'A', actual1);
		assert_equals('NVarchar2 2.', n'B', actual2);
		assert_equals('NVarchar2 3.', lpad(n'C', 1000, n'C'), actual3);
	end;

	--Number.
	declare
		actual1 number;
		actual2 number;
		actual3 number;
	begin
		execute immediate
		q'<
			select *
			from table(method4.run('select 1.1, cast(2.2 as number(10, 1)), 3 from dual'))
		>'
		into actual1, actual2, actual3;

		assert_equals('Number 1.', '1.1', actual1);
		assert_equals('Number 2.', '2.2', actual2);
		assert_equals('Number 3.', '3', actual3);
	end;

	--Float.
	declare
		actual1 float;
		actual2 float;
		actual3 float;
	begin
		execute immediate
		q'<
			select *
			from table(method4.run('select cast(100.001 as float), cast(20.02 as float(100)), cast(3 as float(1)) from dual'))
		>'
		into actual1, actual2, actual3;

		assert_equals('Float 1.', '100.001', actual1);
		assert_equals('Float 2.', '20.02', actual2);
		assert_equals('Float 3.', '3', actual3);
	end;

	--Long.
	--This view is the same in 11g and 12c, hopefully it's the same in all versions.
	declare
		actual1 clob;
	begin
		execute immediate
		q'<
			select *
			from table(method4.run('select text from dba_views where view_name = ''DBA_EXP_VERSION'''))
		>'
		into actual1;

		assert_equals('Long 1.', 'select o.expid'||chr(10)||'from sys.incvid o', actual1);
	end;

	--Date.
	--Note that SYSDATE is not always the same as DATE and worth testing.
	declare
		actual1 date;
		actual2 date;
		actual3 date;
	begin
		execute immediate
		q'<
			select *
			from table(method4.run('select date ''2000-01-01'', to_date(''2000-01-02'', ''YYYY-MM-DD''), sysdate from dual'))
		>'
		into actual1, actual2, actual3;

		assert_equals('Date 1.', '2000-01-01', to_char(actual1, 'YYYY-MM-DD'));
		assert_equals('Date 2.', '2000-01-02', to_char(actual2, 'YYYY-MM-DD'));
		assert_equals('Date 3.', to_char(sysdate, 'YYYY-MM-DD'), to_char(actual3, 'YYYY-MM-DD'));
	end;

	--BINARY_FLOAT.
	declare
		actual1 binary_float;
		actual2 binary_float;
	begin
		execute immediate
		q'<
			select *
			from table(method4.run('select 1.1f, cast(2.2 as binary_float) from dual'))
		>'
		into actual1, actual2;

		assert_equals('BINARY_FLOAT 1.', '1.1', trim(to_char(actual1, '9.9')));
		assert_equals('BINARY_FLOAT 2.', '2.2', trim(to_char(actual2, '9.9')));
	end;


/*
BINARY_DOUBLE
TIMESTAMP [(fractional_seconds_precision)]
TIMESTAMP [(fractional_seconds_precision)] WITH TIME ZONE
TIMESTAMP [(fractional_seconds_precision)] WITH LOCAL TIME ZONE
SYSTIMESTAMP (in case it's different than a regular timestamp)
INTERVAL YEAR [(year_precision)] TO MONTH
INTERVAL DAY [(day_precision)] TO SECOND [(fractional_seconds_precision)]
RAW(size)
LONG RAW
ROWID
UROWID [(size)]
CHAR [(size [BYTE | CHAR])]
NCHAR[(size)]
CLOB
NCLOB
BLOB
BFILE

REF?
TYPE
NESTED TABLE
XMLType
ANYDATA
*/

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
