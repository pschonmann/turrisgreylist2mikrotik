# turrisgreylist2mikrotik
Convert Turris Greylist to mikrotik RSC format - Easy to import

If you want updated list in your mikrotik from turris greylist project just add this into script
Run script every 7d to be updated.
Profit !

/tool fetch url=https://raw.githubusercontent.com/pschonmann/turrisgreylist2mikrotik/master/turrisgreylist2mikrotik.rsc
/import file-name=turrisgreylist2mikrotik.rsc
