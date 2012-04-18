---
--- Script by http://kerryosborne.oracle-guy.com/
---
set lines 150
select * from table(dbms_xplan.display_cursor('&sql_id','&child_no','typical +peeked_binds'))
/

