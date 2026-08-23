#!/bin/bash

# Tulio Control Panel upgrade script for target version 1.10.4

#######################################################################################
#######                      Place additional commands below.                   #######
#######################################################################################
####### upgrade_config_set_value only accepts true or false.                    #######
#######                                                                         #######
####### Pass through information to the end user in case of a issue or problem  #######
#######                                                                         #######
####### Use add_upgrade_message "My message here" to include a message          #######
####### in the upgrade notification email. Example:                             #######
#######                                                                         #######
####### add_upgrade_message "My message here"                                   #######
#######                                                                         #######
####### You can use \n within the string to create new lines.                   #######
#######################################################################################

upgrade_config_set_value 'UPGRADE_UPDATE_WEB_TEMPLATES' 'false'
upgrade_config_set_value 'UPGRADE_UPDATE_DNS_TEMPLATES' 'false'
upgrade_config_set_value 'UPGRADE_UPDATE_FILEMANAGER_CONFIG' 'false'
upgrade_config_set_value 'UPGRADE_UPDATE_MAIL_TEMPLATES' 'false'
upgrade_config_set_value 'UPGRADE_REBUILD_USERS' 'false'

# The only template change in this release is the documentation URL in their
# comment headers, which is not worth overwriting operator-modified copies of
# the stock templates for. They refresh on the next release that touches them.

# New installs start with an API allow list of 127.0.0.1. Existing installs are
# left exactly as the operator configured them - widening an allow list during
# an unattended upgrade would be a security change made behind their back. Point
# out the case where the API is reachable by nobody at all, which is what an
# empty allow list means.
if [ "$API" = "yes" ] && [ -z "$API_ALLOWED_IP" ]; then
	add_upgrade_message "The legacy API is enabled but its allow list (API_ALLOWED_IP) is empty, which rejects every client.\nNew installations now default to 127.0.0.1. To match that, run:\n  v-add-sys-api-ip 127.0.0.1\nAdd any further addresses explicitly with the same command."
fi

# The Roundcube password driver posts the mailbox password to the panel. It used
# to do that with certificate verification switched off, and the hostname and
# port commands used to record the panel address in the $rcmail_config array
# that current Roundcube releases ignore. Refresh both on installations that
# already have Roundcube, so the fix does not wait for a webmail reinstall.
# shellcheck source=/usr/local/tulio/func/webmail.sh
source "$TULIO/func/webmail.sh"

rc_driver_src="$TULIO/install/common/roundcube/tulio.php"
rc_driver_dst="/var/lib/roundcube/plugins/password/drivers/tulio.php"
rc_password_config="/etc/roundcube/plugins/password/config.inc.php"

rc_driver_updated='false'

if [ -f "$rc_driver_dst" ] && [ -f "$rc_driver_src" ] && ! cmp -s "$rc_driver_src" "$rc_driver_dst"; then
	echo "[ * ] Updating Roundcube password driver..."
	if cp -f "$rc_driver_src" "$rc_driver_dst"; then
		chown --reference="$(dirname "$rc_driver_dst")" "$rc_driver_dst" 2> /dev/null
		chmod 644 "$rc_driver_dst"
		rc_driver_updated='true'
	else
		add_upgrade_message "The Roundcube password driver at $rc_driver_dst could not be updated.\nIt still sends mailbox passwords to the panel without verifying the panel certificate.\nCopy $rc_driver_src over it to apply the fix."
	fi
fi

if [ -f "$rc_password_config" ]; then
	# Read the configured values back and write them out in the form the plugin
	# actually reads, so an operator's panel host and port survive untouched.
	rc_host="$(get_roundcube_option "$rc_password_config" 'password_tulio_host')"
	rc_port="$(get_roundcube_option "$rc_password_config" 'password_tulio_port')"
	[ -z "$rc_port" ] && rc_port="${BACKEND_PORT:-8083}"

	# A certificate cannot be issued for "localhost", and verification is no
	# longer optional, so point a loopback value at the panel hostname instead.
	case "$rc_host" in
		"" | localhost | localhost.localdomain | 127.0.0.1 | ::1)
			rc_host="$(hostname)"
			;;
	esac

	if ! set_roundcube_option "$rc_password_config" 'password_tulio_host' "$rc_host" \
		|| ! set_roundcube_option "$rc_password_config" 'password_tulio_port' "$rc_port"; then
		add_upgrade_message "The Roundcube password plugin configuration at $rc_password_config could not be updated.\nCheck that it assigns password_tulio_host and password_tulio_port on the \$config array."
	fi

	if [ "$rc_driver_updated" = 'true' ]; then
		add_upgrade_message "Webmail password changes now verify the panel certificate at https://$rc_host:$rc_port instead of accepting any certificate.\nIf the panel serves a self-signed certificate, point the plugin at a trust store that contains it by adding this line to $rc_password_config:\n  \$config['password_tulio_ca_file'] = '/usr/local/tulio/ssl/certificate.crt';"
	fi
fi

unset rc_driver_src rc_driver_dst rc_driver_updated rc_password_config rc_host rc_port
