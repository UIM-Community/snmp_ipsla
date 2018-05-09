# NOKIA_IPSLA

## FT

- Création d'une issue à cause d'un segmentation fault sur la LIB SNMP (lors des échecs).

```
*** Error in `../../../perl/bin/perl': corrupted double-linked list: 0x00007f6470024fc0 ***
Failed to get SNMP systemVarList with hostname MY-NOKIA, ip 75.1.56.41
sysObjectID =>
Device MY-NOKIA (uuid: bb590d4d-4b01-2823-6156-c6e18c9312c0) has been detected has pollable: false
======= Backtrace: =========
/lib64/libc.so.6(+0x7b194)[0x7f64ab891194]
/lib64/libc.so.6(+0x7d0e5)[0x7f64ab8930e5]
/usr/lib64/libnetsnmp.so.31(snmp_free_varbind+0x1b)[0x7f64a3ee2f9b]
/usr/lib64/libnetsnmp.so.31(snmp_free_pdu+0x34)[0x7f64a3ee2fe4]
/usr/lib64/libnetsnmp.so.31(snmp_sess_timeout+0x100)[0x7f64a3ee5430]
/usr/lib64/libnetsnmp.so.31(snmp_timeout+0x18)[0x7f64a3ee5598]
/usr/lib64/libnetsnmp.so.31(snmp_synch_response_cb+0x12e)[0x7f64a3ec22ce]
/opt/nimsoft/perl/lib/site_perl/5.14.2/x86_64-linux-thread-multi/auto/SNMP/SNMP.so(+0x7146)[0x7f64a1de3146]
/opt/nimsoft/perl/lib/site_perl/5.14.2/x86_64-linux-thread-multi/auto/SNMP/SNMP.so(XS_SNMP__getnext+0xb10)[0x7f64a1def2b0]
../../../perl/bin/perl(Perl_pp_entersub+0x611)[0x497a81]
../../../perl/bin/perl(Perl_runops_standard+0xe)[0x49614e]
../../../perl/bin/perl(Perl_call_sv+0x535)[0x42f145]
/opt/nimsoft/perl/lib/5.14.2/x86_64-linux-thread-multi/auto/threads/threads.so(+0x7189)[0x7f64a4ed1189]
/lib64/libpthread.so.0(+0x7dc5)[0x7f64abbdfdc5]
/lib64/libc.so.6(clone+0x6d)[0x7f64ab90cced]
======= Memory map: ========
Receiving new alarm of type: device_not_responding
00400000-0054b000 r-xp 00000000 fd:06 60629                              /opt/nimsoft/perl/bin/perl
0064a000-0065f000 rw-p 0014a000 fd:06 60629                              /opt/nimsoft/perl/bin/perl
00eda000-038ed000 rw-p 00000000 00:00 0                                  [heap]
7f6464000000-7f6464f8c000 rw-p 00000000 00:00 0
7f6464f8c000-7f6468000000 ---p 00000000 00:00 0
7f6468000000-7f64688df000 rw-p 00000000 00:00 0
7f64688df000-7f646c000000 ---p 00000000 00:00 0
7f646c000000-7f646c8de000 rw-p 00000000 00:00 0
7f646c8de000-7f6470000000 ---p 00000000 00:00 0
7f6470000000-7f6470f89000 rw-p 00000000 00:00 0
7f6470f89000-7f6474000000 ---p 00000000 00:00 0
7f6474000000-7f6474f85000 rw-p 00000000 00:00 0
7f6474f85000-7f6478000000 ---p 00000000 00:00 0
7f647affe000-7f647afff000 ---p 00000000 00:00 0
7f647afff000-7f647b7ff000 rwxp 00000000 00:00 0                          [stack:6170]
7f647b7ff000-7f647b800000 ---p 00000000 00:00 0
7f647b800000-7f647c000000 rwxp 00000000 00:00 0                       Create new SNMP Session on hostname P10-RSO-00001-CPE1, ip 75.2.10.24
   [stack:6169]
7f647c000000-7f647c530000 rw-p 00000000 00:00 0
7f647c530000-7f6480000000 ---p 00000000 00:00 0
7f6480000000-7f6480f89000 rw-p 00000000 00:00 0
7f6480f89000-7f6484000000 ---p 00000000 00:00 0
7f6484000000-7f64848e7000 rw-p 00000000 00:00 0
7f64848e7000-7f6488000000 ---p 00000000 00:00 0
7f6488000000-7f6488f89000 rw-p 00000000 00:00 0
7f6488f89000-7f648c000000 ---p 00000000 00:00 0
7f648c000000-7f648cfad000 rw-p 00000000 00:00 0
7f648cfad000-7f6490000000 ---p 00000000 00:00 0
7f649018e000-7f649018f000 ---p 00000000 00:00 0
7f649018f000-7f649098f000 rwxp 00000000 00:00 0                          [stack:6168]
7f649098f000-7f6490990000 ---p 00000000 00:00 0
7f6490990000-7f6491190000 rwxp 00000000 00:00 0                          [stack:6120]
7f6491190000-7f6491191000 ---p 00000000 00:00 0
7f6491191000-7f6491991000 rwxp 00000000 00:00 0                          [stack:6118]
7f6491991000-7f6491992000 ---p 00000000 00:00 0
7f6491992000-7f6492192000 rwxp 00000000 00:00 0                          [stack:6119]
7f6492192000-7f6492196000 r-xp 00000000 fd:06 268888195                  /opt/nimsoft/perl/lib/5.14.2/x86_64-linux-thread-multi/auto/IO/IO.so
7f6492196000-7f6492295000 ---p 00004000 fd:06 268888195                  /opt/nimsoft/perl/lib/5.14.2/x86_64-linux-thread-multi/auto/IO/IO.so
7f6492295000-7f6492296000 rw-p 00003000 fd:06 268888195                  /opt/nimsoft/perl/lib/5.14.2/x86_64-linux-thread-multi/auto/IO/IO.so
7f6492296000-7f64922bd000 r-xp 00000000 fd:00 91060                      /usr/lib64/libexpat.so.1.6.0
7f64922bd000-7f64924bd000 ---p 00027000 fd:00 91060                      /usr/lib64/libexpat.so.1.6.0
7f64924bd000-7f64924bf000 r--p 00027000 fd:00 91060                      /usr/lib64/libexpat.so.1.6.0
7f64924bf000-7f64924c0000 rw-p 00029000 fd:00 91060                      /usr/lib64/libexpat.so.1.6.0
7f64924c0000-7f64924d4000 r-xp 00000000 fd:06 269061793                  /opt/nimsoft/perl/lib/site_perl/5.14.2/x86_64-linux-thread-multi/auto/XML/Parser/Expat/Expat.so
7f64924d4000-7f64926d3000 ---p 00014000 fd:06 269061793                  /opt/nimsoft/perl/lib/site_perl/5.14.2/x86_64-linux-thread-multi/auto/XML/Parser/Expat/Expat.so
7f64926d3000-7f64926d4000 r--p 00013000 fd:06 269061793                  /opt/nimsoft/perl/lib/site_perl/5.14.2/x86_64-linux-thread-multi/auto/XML/Parser/Expat/Expat.so
7f64926d4000-7f64926d5000 rw-p 00014000 fd:06 269061793                  /opt/nimsoft/perl/lib/site_perl/5.14.2/x86_64-linux-thread-multi/auto/XML/Parser/Expat/Expat.so
7f64926d5000-7f64926e1000 r-xp 00000000 fd:00 27094                      /usr/lib64/libnss_files-2.17.so
7f64926e1000-7f64928e0000 ---p 0000c000 fd:00 27094                      /usr/lib64/libnss_files-2.17.so
7f64928e0000-7f64928e1000 r--p 0000b000 fd:00 27094                      /usr/lib64/libnss_files-2.17.so
7f64928e1000-7f64928e2000 rw-p 0000c000 fd:00 27094                      /usr/lib64/libnss_files-2.17.so
7f64928e2000-7f64928e8000 rw-p 00000000 00:00 0
7f64928e8000-7f64928fd000 r-xp 00000000 fd:00 146                        /usr/lib64/libgcc_s-4.8.5-20150702.so.1
7f64928fd000-7f6492afc000 ---p 00015000 fd:00 146                        /usr/lib64/libgcc_s-4.8.5-20150702.so.1
7f6492afc000-7f6492afd000 r--p 00014000 fd:00 146                        /usr/lib64/libgcc_s-4.8.5-20150702.so.1
7f6492afd000-7f6492afe000 rw-p 00015000 fd:00 146                        /usr/lib64/libgcc_s-4.8.5-20150702.so.1
7f6492afe000-7f6492be7000 r-xp 00000000 fd:00 27133                      /usr/lib64/libstdc++.so.6.0.19
7f6492be7000-7f6492de7000 ---p 000e9000 fd:00 27133                      /usr/lib64/libstdc++.so.6.0.19
7f6492de7000-7f6492def000 r--p 000e9000 fd:00 27133                      /usr/lib64/libstdc++.so.6.0.19
7f6492def000-7f6492df1000 rw-p 000f1000 fd:00 27133                      /usr/lib64/libstdc++.so.6.0.19Aborted
```