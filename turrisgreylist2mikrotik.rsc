#List downloaded at 2022-03-22
/log info "Loading turris_greylist address list"
/ip firewall address-list remove [/ip firewall address-list find list=turris_greylist]
/ip firewall address-list
:do { add address=<head><title>502 Bad Gateway</title></head> list=turris_greylist timeout=60d } on-error={} 
:do { add address=<body bgcolor="white"> list=turris_greylist timeout=60d } on-error={} 
:do { add address=<center><h1>502 Bad Gateway</h1></center> list=turris_greylist timeout=60d } on-error={} 
:do { add address=<hr><center>nginx/1.14.2</center> list=turris_greylist timeout=60d } on-error={} 
:do { add address=</body> list=turris_greylist timeout=60d } on-error={} 
:do { add address=</html> list=turris_greylist timeout=60d } on-error={} 
