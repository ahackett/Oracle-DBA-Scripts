---
--- SQL*Plus script to show the execution plan of an SQL Plan Baseline
---
set lines 150
select * from table (dbms_xplan.display_sql_plan_baseline('&sql_handle', '&plan_name', 'typical +peeked_binds'))
/
