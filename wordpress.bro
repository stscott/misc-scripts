##
# Test policy to identify wordpress servers by the daily communication back
#   to the mother ship...
#

# original source:
# https://raw.githubusercontent.com/set-element/misc-scripts/master/wordpress.bro

@load base/frameworks/software

module WP_PARSE;

export {
	redef enum Log::ID += { LOG };

        redef enum Software::Type += {
                ## Identifier for web applications in the software framework.
                WEB_WORDPRESS_APP, 		# support app like MySQL
                WEB_WORDPRESS_CORE, 		# core wordpress version
                WEB_WORDPRESS_PLUGIN, 		# plugin info
        };

	redef enum Notice::Type += {
		WP_Value,
	};


	# List of hosts that are assigned to the name 'api.wordpress.org'
	global wp_api_hosts = [ 66.155.40.203, 66.155.40.249, 66.155.40.250, 66.155.40.202 ] &redef;

	# HTTP header which holds the site name and agent
	const ua_header = /USER-AGENT/ &redef;
	# Used to snip out the desired values from the ascii goo thrown back and forth.
	const wp_plugin_name = /s\:4\:\"Name\"/;
	const wp_plugin_version = /s\:7:\"Version\"/;

	# there are two types of this - a short lived and a long lived version
	# short exists while the http_request and http_header are being procesed
	#   where the data is heald in wp_conns
	#
	# longer term is indexed by the site name and holds long term data
	#
	type wp_ent: record {
		cid: conn_id;
		uid: string &default="UID" &log;
		name: string &default="NAME" &log;	
		wp_version: string &default="WPVERSION" &log;
		php_version: string &default="PHPVERSION" &log;
		sql_version: string &default="SQLVERSION" &log;
		blog_count: string  &default="0" &log;
		multisite: string &default="0" &log;
		users: string &default="0" &log;
		data: string &default="";
		plugin: string &default="NULL" &log;
		plugin_ver: string &default="NULL" &log;
		};

	global t_wp: table[conn_id] of wp_ent;

	}

function get_version(rawv: string) : Software::Version
	{
	local sv: Software::Version;
	local ver = split_string(rawv, /\./);

	if ( |ver| > 1 ) {

		if ( |ver| > 3 )
			sv$minor3 = to_count(ver[3]);

		if ( |ver| > 2 )
			sv$minor2 = to_count(ver[2]);

		sv$minor = to_count(ver[1]);
		sv$major = to_count(ver[0]);
		}

	return sv;
	}

function software_log(w: wp_ent)
	{
	# This will get called in the event that we are reporting the wordpress core and when
	#   looking at plugins
	local ts = network_time();

	if ( w$plugin != "NULL" ) {
		# This is a plugin report
		local si: Software::Info;
		si$ts = ts;
		si$host = w$cid$orig_h;
		si$host_p = w$cid$orig_p;
		si$software_type = WEB_WORDPRESS_PLUGIN;
		si$name = w$plugin;
		si$version = get_version(w$plugin_ver);
		si$unparsed_version = w$plugin_ver;

		Software::found(w$cid, si);
		}
	else {
		# kinda unclean ...
		local si1: Software::Info;
		si1$ts = ts;
		si1$host = w$cid$orig_h;
		si1$host_p = w$cid$orig_p;
		si1$software_type = WEB_WORDPRESS_CORE;
		si1$name = "Wordpress";
		si1$version = get_version(w$wp_version);
		si1$unparsed_version = w$wp_version;
		Software::found(w$cid, si1);

		local si2: Software::Info;
		si2$ts = ts;
		si2$host = w$cid$orig_h;
		si2$host_p = w$cid$orig_p;
		si2$software_type = WEB_WORDPRESS_APP;
		si2$name = "WP_PHP";
		si2$version = get_version(w$php_version);
		si2$unparsed_version = w$php_version;
		Software::found(w$cid, si2);

		local si3: Software::Info;
		si3$ts = ts;
		si3$host = w$cid$orig_h;
		si3$host_p = w$cid$orig_p;
		si3$software_type = WEB_WORDPRESS_APP;
		si3$name = "WP_MySQL";
		si3$version = get_version(w$sql_version);
		si3$unparsed_version = w$sql_version;
		Software::found(w$cid, si3);
		}
	
	}


function clean_string(s: string) : string
	{
	# take a string that looks like /a:11:{s:4:"Name"/ and return /Name/
	local t_s = split_string(s, /\"/);
	return t_s[1];
	}

event http_request(c: connection, method: string, original_URI: string, unescaped_URI: string, version: string) &priority=3
    {
	# There are two things we are lookig at:
	#  GET /core/version-check/1.6/?version=3.5.1&php=5.3.2&locale=en_US&mysql=5.1.52&local_package=&blogs=1&users=9&multisite_enabled=0 HTTP/1.0
	#  USER-AGENT WordPress/3.5.1; https://materialsproject.org/blog/
	# and
	#  POST /plugins/update-check/1.0/ HTTP/1.0

	if ( c$id$resp_h in wp_api_hosts ) {

        	if ( method == "GET" && /\/version-check\// in unescaped_URI )
    		{
		# do some quick parsing
		local twe: wp_ent;
		local _uri = split_string(unescaped_URI, /\&|\?/);

		if ( c$id !in t_wp ) {
			#print fmt("register %s", c$id);
			t_wp[c$id] = twe;
			}

		for (ui in _uri) {
			local kv = split_string(_uri[ui], /=/);

			if ( kv[0] == "version" ) {
				twe$wp_version = kv[1];
				#print fmt("VER: %s  %s", kv[2], twe);
				}

			if ( kv[0] == "mysql" ) {
				twe$sql_version = kv[1];
				#print fmt("MSQ: %s  %s", kv[2], twe);
				}

			if ( kv[0] == "php" ) {
				twe$php_version = kv[1];
				#print fmt("PHP: %s  %s", kv[2], twe);
				}

			if ( kv[0] == "blogs" ) {
				twe$blog_count = kv[1];
				#print fmt("BLG: %s  %s", kv[2], twe);
				}

			if ( kv[0] == "multisite_enabled" ) {
				twe$multisite = kv[1];
				#print fmt("MSE: %s  %s", kv[2], twe);
				}

			if ( kv[0] == "users" ) {
				twe$users = kv[1];
				#print fmt("MSE: %s  %s", kv[2], twe);
				}
        		}

		if ( twe$uid == "UID" )
			twe$uid = c$uid;

		twe$cid = c$id;

		#Log::write(LOG, twe);
	
		t_wp[c$id] = twe;
		}
	}

	} # end http_request event

event http_header(c: connection, is_orig: bool, name: string, value: string) &priority=3
	{
	# The user-agent header value we are interested in has both the 
	#   user agent (not useful) and the assigned site url (interesting!)
	if ( (is_orig) && ( c$id$resp_h in wp_api_hosts ) )
		{
		if ( ua_header in name ) {
			local domain = split_string(value, /\ /)[1];
			local twe: wp_ent;
			local si: Software::Info;

			# Pull this stunt since there are a number of connections
			#   involved beyond the initial.  The new twe struct is more 
			#   in place to mark the data as interesting and will be indexed
			#   by the site name...
			if ( c$id !in t_wp ) {
				twe$name = domain;
				twe$uid = c$uid;
				twe$cid = c$id;
				}
			else {
				twe = t_wp[c$id];
				twe$name = domain;
				Log::write(LOG, twe);
				software_log(twe);
				}

			t_wp[c$id] = twe;
			} # end header loop
		}

	} # end event


event http_entity_data(c: connection, is_orig: bool, length: count, data: string)
    {
	# If the connection is in the list of known collectors, track the 
	#   data 
    if (is_orig && c$id in t_wp) {
	local twe: wp_ent;
	twe = t_wp[c$id];

	# append new data on old
	twe$data = fmt("%s%s", twe$data, data);

	t_wp[c$id] = twe;
	}
    }


event http_end_entity(c: connection , is_orig: bool )
	{
	# There is probably a better way to go about doing this,
	#   but I will deal with that in the event that things get too
	#   complex or performance suffers.
	if ( c$id in t_wp ){ 

		local twe: wp_ent;
		twe = t_wp[c$id];

		local si: Software::Info;
		local v_array = split_string( unescape_URI(twe$data), /;/);

		delete t_wp[c$id];
		local nret_value = "X";
		local vret_value = "X";
		
		for ( x in v_array ) {
			local val = v_array[x];

			if ( wp_plugin_name in val ) {
				local nvalue = clean_string(v_array[x+1]);
				nret_value = split_string1( nvalue, / /)[0];
				twe$plugin = nret_value;
				}
			if ( wp_plugin_version in val ) {
				local vvalue = clean_string(v_array[x+1]);
				vret_value = split_string1( vvalue, / /)[0];
				twe$plugin_ver = vret_value;
				}

			if ( (nret_value != "X") && (vret_value != "X")) {
				#print fmt("%s %s", nret_value, vret_value);
				Log::write(LOG, twe);
				software_log(twe);
				nret_value = "X";
				vret_value = "X";
				}
			}

		} # end if c$id in t_wp
	}

event bro_init() &priority=5
	{
	Log::create_stream(WP_PARSE::LOG, [$columns=wp_ent]);
	}
