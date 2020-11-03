prompt
prompt
prompt **************************************************************************
prompt    Method4 Installer
prompt    (c) oracle-developer.net, Jon Heller
prompt **************************************************************************
prompt

prompt Installing type specifications...
@@code/method4_ot.tps
@@code/method4_dynamic_ot.tps
@@code/method4_pivot_ot.tps
@@code/method4_poll_table_ot.tps
prompt Installing package specification...
@@code/method4.spc
prompt Installing package body...
@@code/method4.bdy
prompt Installing type bodies...
@@code/method4_ot.tpb
@@code/method4_dynamic_ot.tpb
@@code/method4_pivot_ot.tpb
@@code/method4_poll_table_ot.tpb
prompt Creating context...
create context method4_context using method4;

prompt
prompt **************************************************************************
set serveroutput on feedback off
exec dbms_output.put_line('   Method4 version '||method4.c_version||' installation complete.');
set feedback on
prompt **************************************************************************
