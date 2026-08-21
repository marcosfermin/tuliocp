<?php

class ChangePasswordTulioPlugin extends \RainLoop\Plugins\AbstractPlugin
{
	const
		NAME     = 'Change Password Tulio',
		AUTHOR   = 'TulioCP',
		VERSION  = '2.36',
		RELEASE  = '2026-08-21',
		REQUIRED = '2.36.0',
		CATEGORY = 'Security',
		DESCRIPTION = 'Extension to allow users to change their passwords through TulioCP';

	public function Supported() : string
	{
		return 'Use Change Password plugin';
	}
}
