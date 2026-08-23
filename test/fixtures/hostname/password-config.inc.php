<?php

// Fixture: a password plugin configuration in the shape the panel ships.

$config["password_driver"] = "tulio";
$config["password_minimum_length"] = 8;

// A setting whose value happens to name another setting. Rewriting the panel
// host must not touch it.
$config["password_extra_host"] = "password_tulio_host";

// Tulio Driver options
// -----------------------
// password_tulio_host is written by v-change-sys-hostname
$config["password_tulio_host"] = "localhost";
$config["password_tulio_port"] = "8083";
