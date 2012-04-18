SELECT sid,
       serial#,
       event,
       sql_id,
       seconds_in_wait
  FROM v$session
 WHERE state = 'WAITING'
       AND event IN ('buffer busy waits', 'read by other session')
