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
