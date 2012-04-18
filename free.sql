---
--- http://asktom.oracle.com/pls/asktom/ASKTOM.download_file?p_file=6551402703363001567
---
set linesize 121
-------------------------------------------------------
-- free.sql  
--
-- This SQL Plus script lists freespace by tablespace
--------------------------------------------------------

column dummy noprint
column  pct_used format 999.9       heading "%|Used" 
column  name    format a19      heading "Tablespace Name" 
column  Kbytes   format 999,999,999,999    heading "KBytes" 
column  used    format 999,999,999,999   heading "Used" 
column  free    format 999,999,999  heading "Free" 
column  largest    format 999,999,999  heading "Largest" 
column  max_size format 999,999,999 heading "MaxPoss|Kbytes"
column  pct_max_used format 999.9       heading "%|Max|Used" 
break   on report 
compute sum of kbytes on report 
compute sum of free on report 
compute sum of used on report 

select (select decode(extent_management,'LOCAL','*',' ') || 
               decode(segment_space_management,'AUTO','a ','m ')
	      from dba_tablespaces where tablespace_name = b.tablespace_name) || nvl(b.tablespace_name, 
			 nvl(a.tablespace_name,'UNKOWN')) name,
	   kbytes_alloc kbytes, 
	   kbytes_alloc-nvl(kbytes_free,0) used,
	   nvl(kbytes_free,0) free, 
	   ((kbytes_alloc-nvl(kbytes_free,0))/ 
						  kbytes_alloc)*100 pct_used,
	   nvl(largest,0) largest,
	   nvl(kbytes_max,kbytes_alloc) Max_Size,
	   decode( kbytes_max, 0, 0, (kbytes_alloc/kbytes_max)*100) pct_max_used
from ( select sum(bytes)/(1024*1024*1024) Kbytes_free, 
			  max(bytes)/(1024*1024*1024) largest,
			  tablespace_name
	   from  sys.dba_free_space 
	   group by tablespace_name ) a,
     ( select sum(bytes)/(1024*1024*1024) Kbytes_alloc, 
			  sum(maxbytes)/(1024*1024*1024) Kbytes_max,
			  tablespace_name 
	   from sys.dba_data_files 
	   group by tablespace_name 
	   union all
      select sum(bytes)/(1024*1024*1024) Kbytes_alloc, 
			  sum(maxbytes)/(1024*1024*1024) Kbytes_max,
			  tablespace_name 
	   from sys.dba_temp_files 
	   group by tablespace_name )b
where a.tablespace_name (+) = b.tablespace_name
order by pct_used
/
