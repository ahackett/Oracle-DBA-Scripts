---
--- http://kerryosborne.oracle-guy.com/
---
SELECT * FROM table(dbms_xplan.display_awr(nvl('&sql_id','a96b61z6vp3un'),nvl('&plan_hash_value',null),null,'typical +peeked_binds'))
/
