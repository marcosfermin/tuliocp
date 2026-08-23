#!/bin/bash

# Tulio Control Panel upgrade script for target version 1.10.6

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

# This release changes two commands and nothing on disk, so nothing above needs
# rebuilding and there is no state to migrate. tulio.conf keeps the values it
# already has, including DEMO_MODE: upgrading a panel that is in demo mode
# leaves it in demo mode.

# A panel that is in demo mode right now is one whose operator hit, or is about
# to hit, the defect this release fixes, so it is worth saying so where they
# will see it.
if [ "$(sysconfig_value 'DEMO_MODE' "$TULIO/conf/tulio.conf")" = 'yes' ]; then
	add_upgrade_message "This panel is in demo mode, and 'v-change-sys-demo-mode no' now works from inside it.\nBefore this release the disable path went through v-change-sys-config-value, which demo mode refuses, so the command was blocked by the mode it was trying to leave.\nLeaving demo mode does not turn the API back on. To restore it deliberately afterwards:\n  v-change-sys-api enable all\n  v-add-sys-api-ip <address>   # the allow list is seeded with 127.0.0.1 only"
fi

# 'v-change-sys-api enable' with no version used to set neither API nor
# API_SYSTEM. It now means 'enable all'. Nothing in an existing configuration
# changes because of that - the default only applies to commands run from here
# on - but a script that relied on 'enable' leaving the flags alone is now
# turning both APIs on, so it is called out.
add_upgrade_message "'v-change-sys-api enable' with no version argument now means 'enable all' and turns on both APIs.\nIt used to install the endpoint and set neither API nor API_SYSTEM, which left a half-enabled API behind.\nScripts that ran it for its side effect on web/api/index.php alone should name the version they want: 'legacy' or 'api'."
