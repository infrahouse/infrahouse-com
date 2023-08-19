#
# Regular cron jobs for the infrahouse-com package
#
0 4	* * *	root	[ -x /usr/bin/infrahouse-com_maintenance ] && /usr/bin/infrahouse-com_maintenance
