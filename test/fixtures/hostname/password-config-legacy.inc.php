<?php

// Fixture: what the old hostname command left behind. The panel host is
// assigned to the legacy array that current Roundcube releases ignore, and the
// assignment the plugin actually reads is gone.

$config["password_driver"] = "tulio";
$config["password_minimum_length"] = 8;

// Tulio Driver options
// -----------------------
$rcmail_config["password_tulio_host"] = "demo.tuliocp.com";
$config["password_tulio_port"] = "8083";
