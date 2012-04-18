--- 
--- SQL*Plus script to "color" a SQL statement so it always gets included in AWR snapshots
---
exec dbms_workload_repository.add_colored_sql('&v_sql_id');

