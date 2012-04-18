---
--- Generate a SQL Monitoring report outside of EM
---
set pages 0 echo off timi off lines 1000 trims on trim on long 2000000 longchunksize 2000000
spool sql_monitoring_report.html
select dbms_sqltune.report_sql_monitor(-
          type           => 'EM', - 
          sql_id         => '&sql_id', -
          sql_exec_start => to_date('&sql_exec_date', 'dd/mm/yyyy hh24:mi:ss')-
       )
 from dual;
spool off

