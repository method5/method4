CREATE OR REPLACE TYPE BODY method4_pivot_ot AS
--See Method4 package specification for details.
--Many methods in this type are almost identical to those in METHOD4_OT.
--Inheritence could simplify the code but causes unsolvable OCI errors in 11g.

----------------------------------------------------------------------------
static function get_pivot_sql(p_sql in varchar2, p_aggregate_function in varchar2) return varchar2 is

	v_cursor_id integer;
	v_col_cnt integer;
	--This type only works in Oracle 10g+. It's necessary to support 128-byte column names.
	v_columns dbms_sql.desc_tab2;
	v_has_pivot_column_id boolean;

	v_penultimate_column varchar2(128);
	v_last_column varchar2(128);

	v_distinct_sql clob := '
		select "#PENULTIMATE_COLUMN#"
		from
		(
			#ORIGINAL_SQL#
		)
		group by "#PENULTIMATE_COLUMN#"
		order by #1_OR_MIN_PIVOT_COLUMN_ID#';

	v_pivot_column_names sys.dbms_debug_vc2coll;
	v_pivot_column_values sys.dbms_debug_vc2coll := sys.dbms_debug_vc2coll();

	c_numeric_magic_value constant varchar2(4000) := '-987654321.1234';
	c_varchar_magic_value constant varchar2(4000) := 'Not a real value !@#1234';

	v_has_null_column_name boolean := false;
	v_nvl_column_list clob;

	v_identifier_too_long_counter number := 0;

	--Max size is 30 for early versions, and after 12.2 it can be determined through the constant ora_max_name_len.
	c_ora_max_name_len constant number :=
		$if    dbms_db_version.ver_le_9    $then 30
		$elsif dbms_db_version.ver_le_10   $then 30
		$elsif dbms_db_version.ver_le_11   $then 30
		$elsif dbms_db_version.ver_le_12_1 $then 30
		$else                                    ora_max_name_len
	$end;

	v_in_clause clob;
	v_pivot_sql clob := '
select * from
(
	#BEGIN_NVL_FOR_NULL_COLUMN_NAMES#
	#ORIGINAL_SQL#
	#END_NVL_FOR_NULL_COLUMN_NAMES#
)
pivot (#AGGREGATE_FUNCTION#("#LAST_COLUMN#") for "#PENULTIMATE_COLUMN#" in (#IN_CLAUSE#))';

	--The PIVOT_COLUMN_ID column will be treated differently, so we need to remove it
	--from the collection but have a flag to know we it exists.
	procedure find_and_remove_pivot_col_id(p_columns in out dbms_sql.desc_tab2, p_has_pivot_column_id out boolean) is
		v_columns_without_pivot_col_id dbms_sql.desc_tab2;
		--Use this counters instead of "i" because the new collection may have a gap.
		v_column_count number := 1;
	begin
		--Assume it's false if we don't find it.
		p_has_pivot_column_id := false;

		--Go through all columns, rebuild list with everything but PIVOT_COLUMN_ID.
		for i in 1 .. p_columns.count loop
			if v_columns(i).col_name = 'PIVOT_COLUMN_ID' then
				p_has_pivot_column_id := true;
			else
				v_columns_without_pivot_col_id(v_column_count) := p_columns(i);
				v_column_count := v_column_count + 1;
			end if;
		end loop;

		p_columns := v_columns_without_pivot_col_id;
	end find_and_remove_pivot_col_id;


	--If one of the pivot columns shares a name with a regular column, change the pivot column name.
	procedure change_ambiguous_column_names(p_pivot_column_names in out sys.dbms_debug_vc2coll, p_columns in dbms_sql.desc_tab2) is
		v_current_column_name varchar2(32767);
		v_new_column varchar2(4000);
		v_counter number := 0;
		v_suffix varchar2(4);
	begin
		--Look at all columns except the last two (which won't be in the final query).
		for i in 1 .. p_columns.count - 2 loop
			v_counter := 0;
			v_current_column_name := p_columns(i).col_name;
			if p_columns(i).col_name member of p_pivot_column_names then
				--Look for an available name.
				for j in v_counter .. 1000 loop
					v_counter := v_counter + 1;
					v_suffix := '_'||v_counter;
					v_new_column := p_columns(i).col_name || v_suffix;

					--Shorten the name and add the suffix if it exceeds the max length.
					if length(v_new_column) > c_ora_max_name_len then
						v_new_column := substr(p_columns(i).col_name, 1, c_ora_max_name_len - length(v_suffix)) || v_suffix;
					--Otherwise simply add the suffix.
					else
						v_new_column := p_columns(i).col_name || v_suffix;
					end if;

					--Quit this loop if the new name also already exists.
					if v_new_column member of p_pivot_column_names then
						continue;
					--Switch to the new name.
					else
						--Find the index of the names that match and change the pivot_column_name.
						for k in 1 .. p_pivot_column_names.count loop
							if p_columns(i).col_name = p_pivot_column_names(k) then
								p_pivot_column_names(k) := v_new_column;
								exit;
							end if;
						end loop;

						--Stop looping through suffixes after unused value was found and assigned.
						exit;
					end if;
				end loop;
			end if;
		end loop;
	end change_ambiguous_column_names;

begin
	--Use the cached value if it exists.
	--(This way the pivot SQL won't be regenerated for both Describe and Start.)
	if method4.r_pivot_sql is not null then
		return method4.r_pivot_sql;
	end if;

	--Otherwise regenerate the whole query.
	v_cursor_id := dbms_sql.open_cursor;
	dbms_sql.parse(v_cursor_id, p_sql, dbms_sql.native);
	dbms_sql.describe_columns2(v_cursor_id, v_col_cnt, v_columns);

	find_and_remove_pivot_col_id(v_columns, v_has_pivot_column_id);

	--Must be at least two columns.
	if v_columns.count <= 1 then
		raise_application_error(-20000, 'The SQL statement must have at least two columns.');
	end if;

	--Do not allow dates, timestamps, and intervals as column name column.
	if v_columns(v_columns.count-1).col_type in (12, 180, 181, 182, 183, 231) then
		raise_application_error(-20000, 'To avoid implicit conversion problems, the second to last '||
		'column cannot be a date, timestamp, or interval. Try explicitly casting the column to a '||
		'string with TO_CHAR.');
	end if;

	--Set some important column names.
	v_penultimate_column := v_columns(v_columns.count - 1).col_name;
	v_last_column        := v_columns(v_columns.count).col_name;

	--Get a distinct set of values from the second-to-last column.
	v_distinct_sql := replace(v_distinct_sql, '#PENULTIMATE_COLUMN#', v_penultimate_column);
	v_distinct_sql := replace(v_distinct_sql, '#ORIGINAL_SQL#', p_sql);
	if v_has_pivot_column_id then
		v_distinct_sql := replace(v_distinct_sql, '#1_OR_MIN_PIVOT_COLUMN_ID#', 'min(pivot_column_id), 1');
	else
		v_distinct_sql := replace(v_distinct_sql, '#1_OR_MIN_PIVOT_COLUMN_ID#', '1');
	end if;

	declare
		v_index_out_of_range exception;
		pragma exception_init(v_index_out_of_range, -22165);
	begin
		execute immediate v_distinct_sql bulk collect into v_pivot_column_names;
	exception when v_index_out_of_range then
		raise_application_error(-20000, 'The query contains more than 32K pivoting columns.');
	end;

	--Convert to a sorted associative array, handle nulls, handle columns larger than 30 or 128 bytes.
	--In the associative array, the key is the column name and the value is the column value. (Not always the same thing.)
	for i in 1 .. v_pivot_column_names.count loop
		v_pivot_column_values.extend;

		if v_pivot_column_names(i) is null then
			v_has_null_column_name := true;

			--Use special value for numbers.
			if v_columns(v_columns.count-1).col_type in (2, 100, 101) then
				--v_ordered_pivot_columns('NULL_COLUMN_NAME') := c_numeric_magic_value;
				v_pivot_column_names(i) := 'NULL_COLUMN_NAME';
				v_pivot_column_values(i) := c_numeric_magic_value;
			--Use special value for strings.
			else
				--v_ordered_pivot_columns('NULL_COLUMN_NAME') := c_varchar_magic_value;
				v_pivot_column_names(i) := 'NULL_COLUMN_NAME';
				v_pivot_column_values(i) := c_varchar_magic_value;
			end if;
		else
			--Shrink the name if necessary.
			if length(v_pivot_column_names(i)) > c_ora_max_name_len then
				v_identifier_too_long_counter := v_identifier_too_long_counter + 1;
				--v_ordered_pivot_columns( substr(v_pivot_column_names(i), 1, c_ora_max_name_len - 4)
				--	|| '_' || lpad(v_identifier_too_long_counter, 3, 0)) := v_pivot_column_names(i);
				v_pivot_column_values(i) := v_pivot_column_names(i);
				v_pivot_column_names(i) := substr(v_pivot_column_names(i), 1, c_ora_max_name_len - 4)
					|| '_' || lpad(v_identifier_too_long_counter, 3, 0);
			else
				--v_ordered_pivot_columns(v_pivot_column_names(i)) := v_pivot_column_names(i);
				v_pivot_column_values(i) := v_pivot_column_names(i);
			end if;
		end if;

		--Quoted identifiers cannot contain double quotation marks, so replace them with an underscore.
		--Ideally, this replacement character would be an optional parameter, but there's a bizarre
		--bug in ODCI where the second optional parameter gets mixed up with the first optional parameter.
		if instr(v_pivot_column_names(i), '"') <> 0 then
			v_pivot_column_names(i) := replace(v_pivot_column_names(i), '"', '_');
		end if;
	end loop;

	--Remove pivot column names that match existing columns.
	change_ambiguous_column_names(v_pivot_column_names, v_columns);

	--Create pivot SQL for normal cases with at least one dynamic column.
	if v_pivot_column_names.count >= 1 then

		-- Need to list columns if therer is a NULL value or a PIVOT_COLUMN_ID.
		if v_has_null_column_name or v_has_pivot_column_id then
			for i in 1 .. v_columns.count loop
				--Add NVL to penultimate column if necessary.
				if i = v_columns.count - 1 and v_has_null_column_name then
					--Use a different magic value for numbers and string.
					if v_columns(v_columns.count-1).col_type in (2, 100, 101) then
						v_nvl_column_list := v_nvl_column_list || ', NVL("' || v_columns(i).col_name || '", ' || c_numeric_magic_value || ') "' || v_columns(i).col_name || '"';
					else
						v_nvl_column_list := v_nvl_column_list || ', NVL("' || v_columns(i).col_name || '", ''' || c_varchar_magic_value || ''') "' || v_columns(i).col_name || '"';
					end if;

				--Leave other columns alone.
				else
					v_nvl_column_list := v_nvl_column_list || ', "' || v_columns(i).col_name || '"';
				end if;
			end loop;

			v_nvl_column_list := substr(v_nvl_column_list, 2);

			v_nvl_column_list := '	select ' || v_nvl_column_list || ' from ' || chr(10) || '	(';

			v_pivot_sql := replace(v_pivot_sql, '	#BEGIN_NVL_FOR_NULL_COLUMN_NAMES#', v_nvl_column_list);
			v_pivot_sql := replace(v_pivot_sql, '#END_NVL_FOR_NULL_COLUMN_NAMES#', ')');

		else
			v_pivot_sql := replace(v_pivot_sql, '	#BEGIN_NVL_FOR_NULL_COLUMN_NAMES#', null);
			v_pivot_sql := replace(v_pivot_sql, '	#END_NVL_FOR_NULL_COLUMN_NAMES#', null);
		end if;

		--Create the list of column names and values.
		for i in 1 .. v_pivot_column_names.count loop
			--Convert to numeric literal for number (2), float (100), or double (101)
			if v_columns(v_columns.count-1).col_type in (2, 100, 101) then
				v_in_clause := v_in_clause || v_pivot_column_values(i) ||
					' as "' || v_pivot_column_names(i)||'", ';
			--Convert to string literal otherwise.
			else
				v_in_clause := v_in_clause || '''' ||
					replace(v_pivot_column_values(i), '''', '''''') ||
					''' as "'||v_pivot_column_names(i)||'", ';
			end if;
		end loop;

		v_in_clause := substr(v_in_clause, 1, length(v_in_clause)-2);

		v_pivot_sql := replace(v_pivot_sql, '#ORIGINAL_SQL#', p_sql);
		v_pivot_sql := replace(v_pivot_sql, '#AGGREGATE_FUNCTION#', p_aggregate_function);
		v_pivot_sql := replace(v_pivot_sql, '#LAST_COLUMN#', v_last_column);
		v_pivot_sql := replace(v_pivot_sql, '#PENULTIMATE_COLUMN#', v_penultimate_column);
		v_pivot_sql := replace(v_pivot_sql, '#IN_CLAUSE#', v_in_clause);

	--Create pivot SQL where there are no rows and 3 or more columns - display everything but last two columns.
	elsif v_pivot_column_names.count = 0 and v_columns.count >= 3 then
		v_pivot_sql := 'select ';

		for i in 1 .. v_columns.count - 2 loop
			v_pivot_sql := v_pivot_sql || v_columns(i).col_name || ', ';
		end loop;

		--Remove extra ',' at the end.
		v_pivot_sql := substr(v_pivot_sql, 1, length(v_pivot_sql)-2);

		--Add original SQL to generate correct types.
		v_pivot_sql := v_pivot_sql || ' from '||chr(10)||'('||chr(10)||p_sql||chr(10)||')';

	--Create pivot SQL where there are no rows and 2 columns - create fake column named "NO_RESULTS".
	elsif v_pivot_column_names.count = 0 and v_columns.count = 2 then
		v_pivot_sql := 'select cast(null as varchar2(1)) no_results from dual';
	end if;

	--TESTING:
	--(DBMS_OUTPUT does not work on errors so you may need to change the SQL.)
	--dbms_output.put_line(v_pivot_sql);
	--v_pivot_sql := 'select * from dual';

	dbms_sql.close_cursor(v_cursor_id);

	return v_pivot_sql;
exception when others then
	dbms_sql.close_cursor(v_cursor_id);
	raise;
end get_pivot_sql;


   ----------------------------------------------------------------------------
   STATIC FUNCTION ODCITableDescribe(
                   rtype   OUT ANYTYPE,
                   stmt    IN  VARCHAR2,
                   p_aggregate_function IN VARCHAR2 DEFAULT 'MAX'
                   ) RETURN NUMBER IS

      r_sql   method4.rt_dynamic_sql;
      v_rtype ANYTYPE;
	  v_pivot_sql CLOB;

  BEGIN
      --Clear the old pivot SQL and get a new one.
      method4.r_pivot_sql := null;
      method4.check_for_null_stmt(stmt);
      v_pivot_sql := get_pivot_sql(stmt, p_aggregate_function);

      /*
      || Parse the SQL and describe its format and structure.
      */
      r_sql.cursor := DBMS_SQL.OPEN_CURSOR;
      DBMS_SQL.PARSE( r_sql.cursor, v_pivot_sql, DBMS_SQL.NATIVE );
      DBMS_SQL.DESCRIBE_COLUMNS2( r_sql.cursor, r_sql.column_cnt, r_sql.description );
      DBMS_SQL.CLOSE_CURSOR( r_sql.cursor );

      /*
      || Create the ANYTYPE record structure from this SQL structure.
      || Replace LONG columns with CLOB...
      */
      ANYTYPE.BeginCreate( DBMS_TYPES.TYPECODE_OBJECT, v_rtype );

      FOR i IN 1 .. r_sql.column_cnt LOOP

         v_rtype.AddAttr(
                          --Column names can be over 30 bytes if an expression was used.
                          --If the length is more than 30 the query will generate the error
                          --"ORA-00902: invalid datatype" without a line number.
                          --I'm not sure why or where it breaks, but this fixes it.
                          $IF DBMS_DB_VERSION.ver_le_10 $THEN
                             substr(r_sql.description(i).col_name, 1, 30),
                          $ELSIF DBMS_DB_VERSION.ver_le_11 $THEN
                             substr(r_sql.description(i).col_name, 1, 30),
                          $ELSIF DBMS_DB_VERSION.ver_le_12_1 $THEN
                             substr(r_sql.description(i).col_name, 1, 30),
                          --In 12.2 the same logic applies, but for 128 bytes instead of 30.
                          $ELSE
                             substr(r_sql.description(i).col_name, 1, 128),
                          $END
                          CASE
                             --<>--
                             WHEN r_sql.description(i).col_type IN (1,96,11,208)
                             THEN DBMS_TYPES.TYPECODE_VARCHAR2
                             --<>--
                             WHEN r_sql.description(i).col_type = 2
                             THEN DBMS_TYPES.TYPECODE_NUMBER
                             --<LONG defined as CLOB>--
                             WHEN r_sql.description(i).col_type IN (8,112)
                             THEN DBMS_TYPES.TYPECODE_CLOB
                             --<>--
                             WHEN r_sql.description(i).col_type = 113
                             THEN DBMS_TYPES.TYPECODE_BLOB
                             --<>--
                             WHEN r_sql.description(i).col_type = 12
                             THEN DBMS_TYPES.TYPECODE_DATE
                             --<>--
                             WHEN r_sql.description(i).col_type = 23
                             THEN DBMS_TYPES.TYPECODE_RAW
                             --<>--
                             WHEN r_sql.description(i).col_type = 100
                             THEN DBMS_TYPES.TYPECODE_BFLOAT
                             --<>--
                             WHEN r_sql.description(i).col_type = 101
                             THEN DBMS_TYPES.TYPECODE_BDOUBLE
                             --<>--
                             WHEN r_sql.description(i).col_type = 180
                             THEN DBMS_TYPES.TYPECODE_TIMESTAMP
                             --<>--
                             WHEN r_sql.description(i).col_type = 181
                             THEN DBMS_TYPES.TYPECODE_TIMESTAMP_TZ
                             --<>--
                             WHEN r_sql.description(i).col_type = 182
                             THEN DBMS_TYPES.TYPECODE_INTERVAL_YM
                             --<>--
                             WHEN r_sql.description(i).col_type = 183
                             THEN DBMS_TYPES.TYPECODE_INTERVAL_DS
                             --<>--
                             WHEN r_sql.description(i).col_type = 231
                             THEN DBMS_TYPES.TYPECODE_TIMESTAMP_LTZ
                             --<>--
                          END,
                          --Float and Number share the same col_type, 2.
                          --Convert FLOAT to NUMBER by changing scale and precision.
                          CASE
                             WHEN r_sql.description(i).col_type = 2 AND r_sql.description(i).col_precision > 0 AND r_sql.description(i).col_scale = -127
                             THEN 0
                             ELSE r_sql.description(i).col_precision
                          END,
                          CASE
                             WHEN r_sql.description(i).col_type = 2 AND r_sql.description(i).col_precision > 0 AND r_sql.description(i).col_scale = -127
                             THEN -127
                             ELSE r_sql.description(i).col_scale
                          END,
                          CASE r_sql.description(i).col_type
                             WHEN 11
                             THEN 32
                             ELSE r_sql.description(i).col_max_len
                          END,
                          r_sql.description(i).col_charsetid,
                          r_sql.description(i).col_charsetform );
      END LOOP;

      v_rtype.EndCreate;

      /*
      || Now we can use this transient record structure to create a table type
      || of the same. This will create a set of types on the database for use
      || by the pipelined function...
      */
      ANYTYPE.BeginCreate( DBMS_TYPES.TYPECODE_TABLE, rtype );
      rtype.SetInfo( NULL, NULL, NULL, NULL, NULL, v_rtype,
                     DBMS_TYPES.TYPECODE_OBJECT, 0 );
      rtype.EndCreate();

      RETURN ODCIConst.Success;

   END;

   ----------------------------------------------------------------------------
   STATIC FUNCTION ODCITablePrepare(
                   sctx    OUT method4_pivot_ot,
                   tf_info IN  sys.ODCITabFuncInfo,
                   stmt    IN  VARCHAR2,
                   p_aggregate_function IN VARCHAR2 DEFAULT 'MAX'
                   ) RETURN NUMBER IS

      r_meta method4.rt_anytype_metadata;

  BEGIN

      /*
      || We prepare the dataset that our pipelined function will return by
      || describing the ANYTYPE that contains the transient record structure...
      */
      r_meta.typecode := tf_info.rettype.GetAttrElemInfo(
                            1, r_meta.precision, r_meta.scale, r_meta.length,
                            r_meta.csid, r_meta.csfrm, r_meta.type, r_meta.name
                            );

      /*
      || Using this, we initialise the scan context for use in this and
      || subsequent executions of the same dynamic SQL cursor...
      */
      sctx := method4_pivot_ot(r_meta.type);

      RETURN ODCIConst.Success;

   END;

   ----------------------------------------------------------------------------
   STATIC FUNCTION ODCITableStart(
                   sctx IN OUT method4_pivot_ot,
                   stmt IN     VARCHAR2,
                   p_aggregate_function IN VARCHAR2 DEFAULT 'MAX'
                   ) RETURN NUMBER IS

      r_meta method4.rt_anytype_metadata;
	  v_pivot_sql CLOB;

  BEGIN
      v_pivot_sql := get_pivot_sql(stmt, p_aggregate_function);
      method4.purge_sql('method4.pivot');

      /*
      || We now describe the cursor again and use this and the described
      || ANYTYPE structure to define and execute the SQL statement...
      */
      method4.r_sql.cursor := DBMS_SQL.OPEN_CURSOR;
      DBMS_SQL.PARSE( method4.r_sql.cursor, v_pivot_sql, DBMS_SQL.NATIVE );
      DBMS_SQL.DESCRIBE_COLUMNS2( method4.r_sql.cursor,
                                  method4.r_sql.column_cnt,
                                  method4.r_sql.description );

      FOR i IN 1 .. method4.r_sql.column_cnt LOOP

         /*
         || Get the ANYTYPE attribute at this position...
         */
         r_meta.typecode := sctx.atype.GetAttrElemInfo(
                               i, r_meta.precision, r_meta.scale, r_meta.length,
                               r_meta.csid, r_meta.csfrm, r_meta.type, r_meta.name
                               );

         CASE r_meta.typecode
            --<>--
            WHEN DBMS_TYPES.TYPECODE_VARCHAR2
            THEN
               DBMS_SQL.DEFINE_COLUMN(
                  method4.r_sql.cursor, i, '', 32767
                  );
            --<>--
            WHEN DBMS_TYPES.TYPECODE_NVARCHAR2
            THEN
               DBMS_SQL.DEFINE_COLUMN(
                  method4.r_sql.cursor, i, '', 32767
                  );
            --<>--
            WHEN DBMS_TYPES.TYPECODE_NUMBER
            THEN
               DBMS_SQL.DEFINE_COLUMN(
                  method4.r_sql.cursor, i, CAST(NULL AS NUMBER)
                  );
            --<FLOAT - convert to NUMBER.>--
            WHEN 4
            THEN
               DBMS_SQL.DEFINE_COLUMN(
                  method4.r_sql.cursor, i, CAST(NULL AS NUMBER)
                  );
            --<>--
            WHEN DBMS_TYPES.TYPECODE_BFLOAT
            THEN
               DBMS_SQL.DEFINE_COLUMN(
                  method4.r_sql.cursor, i, CAST(NULL AS BINARY_FLOAT)
                  );
            --<>--
            WHEN DBMS_TYPES.TYPECODE_BDOUBLE
            THEN
               DBMS_SQL.DEFINE_COLUMN(
                  method4.r_sql.cursor, i, CAST(NULL AS BINARY_DOUBLE)
                  );
            --<>--
            WHEN DBMS_TYPES.TYPECODE_BLOB
            THEN
               DBMS_SQL.DEFINE_COLUMN(
                  method4.r_sql.cursor, i, CAST(NULL AS BLOB)
                  );
            --<>--
            WHEN DBMS_TYPES.TYPECODE_DATE
            THEN
               DBMS_SQL.DEFINE_COLUMN(
                  method4.r_sql.cursor, i, CAST(NULL AS DATE)
                  );
            --<>--
            WHEN DBMS_TYPES.TYPECODE_RAW
            THEN
               DBMS_SQL.DEFINE_COLUMN_RAW(
                  method4.r_sql.cursor, i, CAST(NULL AS RAW), r_meta.length
                  );
            --<>--
            WHEN DBMS_TYPES.TYPECODE_TIMESTAMP
            THEN
               DBMS_SQL.DEFINE_COLUMN(
                  method4.r_sql.cursor, i, CAST(NULL AS TIMESTAMP)
                  );
            --<>--
            WHEN DBMS_TYPES.TYPECODE_TIMESTAMP_TZ
            THEN
               DBMS_SQL.DEFINE_COLUMN(
                  method4.r_sql.cursor, i, CAST(NULL AS TIMESTAMP WITH TIME ZONE)
                  );
            --<>--
            WHEN DBMS_TYPES.TYPECODE_TIMESTAMP_LTZ
            THEN
               DBMS_SQL.DEFINE_COLUMN(
                  method4.r_sql.cursor, i, CAST(NULL AS TIMESTAMP WITH LOCAL TIME ZONE)
                  );
            --<>--
            WHEN DBMS_TYPES.TYPECODE_INTERVAL_YM
            THEN
               DBMS_SQL.DEFINE_COLUMN(
                  method4.r_sql.cursor, i, CAST(NULL AS INTERVAL YEAR TO MONTH)
                  );
            --<>--
            WHEN DBMS_TYPES.TYPECODE_INTERVAL_DS
            THEN
               DBMS_SQL.DEFINE_COLUMN(
                  method4.r_sql.cursor, i, CAST(NULL AS INTERVAL DAY TO SECOND)
                  );
            --<>--
            WHEN DBMS_TYPES.TYPECODE_CLOB
            THEN
               --<>--
               CASE method4.r_sql.description(i).col_type
                  WHEN 8
                  THEN
                     DBMS_SQL.DEFINE_COLUMN_LONG(
                        method4.r_sql.cursor, i
                        );
                  ELSE
                     DBMS_SQL.DEFINE_COLUMN(
                        method4.r_sql.cursor, i, CAST(NULL AS CLOB)
                        );
               END CASE;
         END CASE;
      END LOOP;

      /*
      || The cursor is prepared according to the structure of the type we wish
      || to fetch it into. We can now execute it and we are done for this method...
      */
      method4.r_sql.execute := DBMS_SQL.EXECUTE( method4.r_sql.cursor );

      RETURN ODCIConst.Success;

   END;

   ----------------------------------------------------------------------------
   MEMBER FUNCTION ODCITableFetch(
                   SELF   IN OUT method4_pivot_ot,
                   nrows  IN     NUMBER,
                   rws    OUT    ANYDATASET
                   ) RETURN NUMBER IS

      TYPE rt_fetch_attributes IS RECORD
      ( v2_column      VARCHAR2(32767)
      , num_column     NUMBER
      , bfloat_column  BINARY_FLOAT
      , bdouble_column BINARY_DOUBLE
      , date_column    DATE
      , clob_column    CLOB
      , blob_column    BLOB
      , raw_column     RAW(32767)
      , raw_error      NUMBER
      , raw_length     INTEGER
      , ids_column     INTERVAL DAY TO SECOND
      , iym_column     INTERVAL YEAR TO MONTH
      , ts_column      TIMESTAMP(9)
      , tstz_column    TIMESTAMP(9) WITH TIME ZONE
      , tsltz_column   TIMESTAMP(9) WITH LOCAL TIME ZONE
      , cvl_offset     INTEGER := 0
      , cvl_length     INTEGER
      );
      r_fetch rt_fetch_attributes;
      r_meta  method4.rt_anytype_metadata;


   BEGIN

      IF DBMS_SQL.FETCH_ROWS( method4.r_sql.cursor ) > 0 THEN

         /*
         || First we describe our current ANYTYPE instance (SELF.A) to determine
         || the number and types of the attributes...
         */
         r_meta.typecode := SELF.atype.GetInfo(
                               r_meta.precision, r_meta.scale, r_meta.length,
                               r_meta.csid, r_meta.csfrm, r_meta.schema,
                               r_meta.name, r_meta.version, r_meta.attr_cnt
                               );

         /*
         || We can now begin to piece together our returning dataset. We create an
         || instance of ANYDATASET and then fetch the attributes off the DBMS_SQL
         || cursor using the metadata from the ANYTYPE. LONGs are converted to CLOBs...
         */
         ANYDATASET.BeginCreate( DBMS_TYPES.TYPECODE_OBJECT, SELF.atype, rws );
         rws.AddInstance();
         rws.PieceWise();

         FOR i IN 1 .. method4.r_sql.column_cnt LOOP

            r_meta.typecode := SELF.atype.GetAttrElemInfo(
                                  i, r_meta.precision, r_meta.scale, r_meta.length,
                                  r_meta.csid, r_meta.csfrm, r_meta.attr_type,
                                  r_meta.attr_name
                                  );

            CASE r_meta.typecode
               --<>--
               WHEN DBMS_TYPES.TYPECODE_VARCHAR2
               THEN
                  DBMS_SQL.COLUMN_VALUE(
                     method4.r_sql.cursor, i, r_fetch.v2_column
                     );
                  rws.SetVarchar2( r_fetch.v2_column );
               --<>--
               WHEN DBMS_TYPES.TYPECODE_NVARCHAR2
               THEN
                  DBMS_SQL.COLUMN_VALUE(
                     method4.r_sql.cursor, i, r_fetch.v2_column
                     );
                  rws.SetNVarchar2( r_fetch.v2_column );
               --<>--
               WHEN DBMS_TYPES.TYPECODE_NUMBER
               THEN
                  DBMS_SQL.COLUMN_VALUE(
                     method4.r_sql.cursor, i, r_fetch.num_column
                     );
                  rws.SetNumber( r_fetch.num_column );
               --<FLOAT - convert to NUMBER.>--
               WHEN 4
               THEN
                  DBMS_SQL.COLUMN_VALUE(
                     method4.r_sql.cursor, i, r_fetch.num_column
                     );
                  rws.SetNumber( r_fetch.num_column );
               --<>--
               WHEN DBMS_TYPES.TYPECODE_BFLOAT
               THEN
                  DBMS_SQL.COLUMN_VALUE(
                     method4.r_sql.cursor, i, r_fetch.bfloat_column
                     );
                  rws.SetBFloat( r_fetch.bfloat_column );
               --<>--
               WHEN DBMS_TYPES.TYPECODE_BDOUBLE
               THEN
                  DBMS_SQL.COLUMN_VALUE(
                     method4.r_sql.cursor, i, r_fetch.bdouble_column
                     );
                  rws.SetBDouble( r_fetch.bdouble_column );
               --<>--
               WHEN DBMS_TYPES.TYPECODE_BLOB
               THEN
                  DBMS_SQL.COLUMN_VALUE(
                     method4.r_sql.cursor, i, r_fetch.blob_column
                     );
                  rws.SetBlob( r_fetch.blob_column );
               --<>--
               WHEN DBMS_TYPES.TYPECODE_DATE
               THEN
                  DBMS_SQL.COLUMN_VALUE(
                     method4.r_sql.cursor, i, r_fetch.date_column
                     );
                  rws.SetDate( r_fetch.date_column );
               --<>--
               WHEN DBMS_TYPES.TYPECODE_RAW
               THEN
                  DBMS_SQL.COLUMN_VALUE_RAW(
                     method4.r_sql.cursor, i, r_fetch.raw_column,
                     r_fetch.raw_error, r_fetch.raw_length
                     );
                  rws.SetRaw( r_fetch.raw_column );
               --<>--
               WHEN DBMS_TYPES.TYPECODE_INTERVAL_DS
               THEN
                  DBMS_SQL.COLUMN_VALUE(
                     method4.r_sql.cursor, i, r_fetch.ids_column
                     );
                  rws.SetIntervalDS( r_fetch.ids_column );
               --<>--
               WHEN DBMS_TYPES.TYPECODE_INTERVAL_YM
               THEN
                  DBMS_SQL.COLUMN_VALUE(
                     method4.r_sql.cursor, i, r_fetch.iym_column
                     );
                  rws.SetIntervalYM( r_fetch.iym_column );
               --<>--
               WHEN DBMS_TYPES.TYPECODE_TIMESTAMP
               THEN
                  DBMS_SQL.COLUMN_VALUE(
                     method4.r_sql.cursor, i, r_fetch.ts_column
                     );
                  rws.SetTimestamp( r_fetch.ts_column );
               --<>--
               WHEN DBMS_TYPES.TYPECODE_TIMESTAMP_TZ
               THEN
                  DBMS_SQL.COLUMN_VALUE(
                     method4.r_sql.cursor, i, r_fetch.tstz_column
                     );
                  rws.SetTimestampTZ( r_fetch.tstz_column );
               --<>--
               WHEN DBMS_TYPES.TYPECODE_TIMESTAMP_LTZ
               THEN
                  DBMS_SQL.COLUMN_VALUE(
                     method4.r_sql.cursor, i, r_fetch.tsltz_column
                     );
                  rws.SetTimestamplTZ( r_fetch.tsltz_column );
               --<>--
               WHEN DBMS_TYPES.TYPECODE_CLOB
               THEN
                  --<>--
                  CASE method4.r_sql.description(i).col_type
                     WHEN 8
                     THEN
                        LOOP
                           DBMS_SQL.COLUMN_VALUE_LONG(
                              method4.r_sql.cursor, i, 32767, r_fetch.cvl_offset,
                              r_fetch.v2_column, r_fetch.cvl_length
                              );
                           r_fetch.clob_column := r_fetch.clob_column ||
                                                  r_fetch.v2_column;
                           r_fetch.cvl_offset := r_fetch.cvl_offset + 32767;
                           EXIT WHEN r_fetch.cvl_length < 32767;
                        END LOOP;
                     ELSE
                        DBMS_SQL.COLUMN_VALUE(
                           method4.r_sql.cursor, i, r_fetch.clob_column
                           );
                     END CASE;
                     rws.SetClob( r_fetch.clob_column );
               --<>--
            END CASE;
         END LOOP;

         /*
         || Our ANYDATASET instance is complete. We end our create session...
         */
         rws.EndCreate();

      END IF;

      RETURN ODCIConst.Success;

   END;

   ----------------------------------------------------------------------------
   MEMBER FUNCTION ODCITableClose(
                   SELF IN method4_pivot_ot
                   ) RETURN NUMBER IS
   BEGIN
      DBMS_SQL.CLOSE_CURSOR( method4.r_sql.cursor );
      method4.r_sql := NULL;
      RETURN ODCIConst.Success;

   END;

END;
/
