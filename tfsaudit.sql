REM
REM Adapted from My Oracle Support Article ID 1019552.6
REM
SET ECHO off
col user_name for a12 heading "User name"
col proxy_name for a12 heading "Proxy name"
col privilege for a30 heading "Privilege"
col user_name for a12 heading "User name" 
col audit_option format a30 heading "Audit Option"
col timest format a13 
col userid format a8 trunc 
col obn format a10 trunc 
col name format a13 trunc 
col sessionid format 99999 
col entryid format 999 
col owner format a10 
col object_name format a10 
col object_type format a6 
col priv_used format a15 trunc 
break on user_name
set pages 1000

REM set pause 'Return...' 

prompt 
prompt System auditing options across the system and by user

select * from sys.dba_stmt_audit_opts
order by user_name, proxy_name, audit_option 
/

prompt
prompt Auditing options on all objects...


select owner, object_name, object_type, 
       alt,aud,com,del,gra,ind,ins,loc,ren,sel,upd,ref,exe 
from sys.dba_obj_audit_opts 
where  
   alt !='-/-' or aud !='-/-' or com !='-/-' 
or del !='-/-' or gra !='-/-' or ind !='-/-' 
or ins !='-/-' or loc !='-/-' or ren !='-/-' 
or sel !='-/-' or upd !='-/-' or ref !='-/-' or exe !='-/-' 
/ 

prompt
prompt System privileges audited across the system and by user...

select * from dba_priv_audit_opts
order by user_name, proxy_name, privilege
/
