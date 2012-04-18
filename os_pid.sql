set lines 132
SELECT s.username, s.user#, s.sid, s.serial#, s.prev_hash_value, p.spid os_pid
 FROM V$SESSION S, v$process p
 WHERE sid = nvl('&sid',sid)
and p.spid = nvl('&os_pid',p.spid)
and p.addr = s.paddr
 and s.username is not null
/
