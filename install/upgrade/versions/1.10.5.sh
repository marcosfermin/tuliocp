#!/bin/bash

# Tulio Control Panel upgrade script for target version 1.10.5

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

# This release fixes two things that ship inside the panel rather than in a
# template, so nothing above needs rebuilding.

# The phpMyAdmin sign-on client posts the panel API key to the panel and gets
# database credentials back. It used to do that with certificate verification
# switched off, so anything that could answer on the panel address collected the
# key. The installed copy holds keys that only exist in that file, so it is
# re-rendered from the fixed template with its own values rather than replaced.
# shellcheck source=/usr/local/tulio/func/pma.sh
source "$TULIO/func/pma.sh"

pma_sso_installed='/usr/share/phpmyadmin/tulio-sso.php'
pma_sso_template="$TULIO/install/deb/phpmyadmin/tulio-sso.php"

if [ -f "$pma_sso_installed" ] && [ -f "$pma_sso_template" ]; then
	echo "[ * ] Updating phpMyAdmin single sign-on client..."

	pma_sso_key="$(pma_sso_read_define "$pma_sso_installed" 'PHPMYADMIN_KEY')"
	pma_sso_api_key="$(pma_sso_read_define "$pma_sso_installed" 'API_KEY')"
	pma_sso_host="$(pma_sso_read_define "$pma_sso_installed" 'API_HOST_NAME')"
	pma_sso_port="$(pma_sso_read_define "$pma_sso_installed" 'API_TULIO_PORT')"

	if [ -z "$pma_sso_key" ] || [ -z "$pma_sso_api_key" ] \
		|| [ -z "$pma_sso_host" ] || [ -z "$pma_sso_port" ]; then
		# Without the installed keys a re-render would lock the operator out of
		# phpMyAdmin, so the file is left exactly as it is and the operator is
		# told how to replace it deliberately.
		add_upgrade_message "The phpMyAdmin single sign-on client at $pma_sso_installed could not be read, so it was left unchanged.\nIt still sends the panel API key without verifying the panel certificate.\nTo replace it, run:\n  v-delete-sys-pma-sso\n  v-add-sys-pma-sso"
	else
		# A trust anchor is only needed when the system trust store cannot
		# verify the panel itself; an existing one is kept.
		pma_sso_ca="$(pma_sso_read_define "$pma_sso_installed" 'API_CA_FILE')"
		if [ -z "$pma_sso_ca" ]; then
			pma_sso_ca="$(pma_sso_ca_file "$pma_sso_host" "$pma_sso_port")"
		fi

		if pma_sso_render "$pma_sso_template" "$pma_sso_installed" \
			"$pma_sso_key" "$pma_sso_host" "$pma_sso_port" "$pma_sso_api_key" \
			"$pma_sso_ca"; then
			if [ -n "$pma_sso_ca" ]; then
				add_upgrade_message "phpMyAdmin single sign-on now verifies the panel certificate at https://$pma_sso_host:$pma_sso_port instead of accepting any certificate.\nThat certificate is not one the system trust store can verify, so the client was pointed at $pma_sso_ca as its trust anchor.\nInstalling a publicly trusted certificate for $pma_sso_host removes the need for it."
			else
				add_upgrade_message "phpMyAdmin single sign-on now verifies the panel certificate at https://$pma_sso_host:$pma_sso_port instead of accepting any certificate.\nIf sign-on stops working, check that the certificate is valid for $pma_sso_host, or point the client at a trust anchor by setting API_CA_FILE in $pma_sso_installed."
			fi
		else
			add_upgrade_message "The phpMyAdmin single sign-on client at $pma_sso_installed could not be updated.\nIt still sends the panel API key without verifying the panel certificate.\nTo replace it, run:\n  v-delete-sys-pma-sso\n  v-add-sys-pma-sso"
		fi
	fi
fi

unset pma_sso_installed pma_sso_template pma_sso_key pma_sso_api_key
unset pma_sso_host pma_sso_port pma_sso_ca

# The hostname command rewrote /etc/hosts entries that had nothing to do with
# the hostname being changed: it collapsed their spacing, dropped a repeated
# alias and moved loopback names to the front of the list. Nothing on disk needs
# repairing here - the entries stayed resolvable, only their formatting was
# changed - so there is no migration step, just the fixed command.
