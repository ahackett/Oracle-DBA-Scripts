---
--- My Oracle ID 169139.1
---
SELECT                                                          /*+ ordered */
      w1.sid waiting_session,
       h1.sid holding_session,
       w.kgllktype lock_or_pin,
       w.kgllkhdl address,
       DECODE (h.kgllkmod,
               0, 'None',
               1, 'Null',
               2, 'Share',
               3, 'Exclusive',
               'Unknown')
          mode_held,
       DECODE (w.kgllkreq,
               0, 'None',
               1, 'Null',
               2, 'Share',
               3, 'Exclusive',
               'Unknown')
          mode_requested
  FROM dba_kgllock w,
       dba_kgllock h,
       v$session w1,
       v$session h1
 WHERE ( (    (h.kgllkmod != 0)
          AND (h.kgllkmod != 1)
          AND ( (h.kgllkreq = 0) OR (h.kgllkreq = 1)))
        AND ( ( (w.kgllkmod = 0) OR (w.kgllkmod = 1))
             AND ( (w.kgllkreq != 0) AND (w.kgllkreq != 1))))
       AND w.kgllktype = h.kgllktype
       AND w.kgllkhdl = h.kgllkhdl
       AND w.kgllkuse = w1.saddr
       AND h.kgllkuse = h1.saddr;

---
--- Which object is locked
---
--- select * from x$kglob where kglhdadr  = '&kgllkhdl'


