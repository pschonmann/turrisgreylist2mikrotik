#List downloaded at 2022-04-19
/log info "Loading turris_greylist address list"
/ip firewall address-list remove [/ip firewall address-list find list=turris_greylist]
/ip firewall address-list
