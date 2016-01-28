prompt
prompt
prompt **************************************************************************
prompt    Method4 Installer
prompt    (c) oracle-developer.net
prompt **************************************************************************
prompt

prompt Installing type specifications...
@method4_ot.tps
@method4_dynamic_ot.tps
prompt Installing package specification...
@method4.spc
prompt Installing type bodies...
@method4_ot.tpb
@method4_dynamic_ot.tpb

prompt
prompt **************************************************************************
set serveroutput on feedback off
exec dbms_output.put_line('   Method4 version '||method4.c_version||' installation complete.');
set feedback on
prompt **************************************************************************
