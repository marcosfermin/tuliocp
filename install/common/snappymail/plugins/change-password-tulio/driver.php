<?php

use SnappyMail\SensitiveString;

class ChangePasswordTulioDriver
{
	const
		NAME        = 'Tulio',
		DESCRIPTION = 'Change passwords in TulioCP.';

	/**
	 * @var \RainLoop\Config\Plugin
	 */
	private $oConfig = null;

	/**
	 * @var \MailSo\Log\Logger
	 */
	protected $oLogger = null;

	function __construct(\RainLoop\Config\Plugin $oConfig, \MailSo\Log\Logger $oLogger)
	{
		$this->oConfig = $oConfig;
		$this->oLogger = $oLogger;
	}

	public static function isSupported() : bool
	{
		return true;
	}

	public static function configMapping() : array
	{
		return array(
			\RainLoop\Plugins\Property::NewInstance('tulio_host')->SetLabel('Tulio Host')
				->SetDefaultValue('')
				->SetDescription('Ex: localhost or domain.com'),
			\RainLoop\Plugins\Property::NewInstance('tulio_port')->SetLabel('Tulio Port')
				->SetType(\RainLoop\Enumerations\PluginPropertyType::INT)
				->SetDefaultValue(8083)
		);
	}

	public function ChangePassword(\RainLoop\Model\Account $oAccount, SensitiveString $oPrevPassword, SensitiveString $oNewPassword) : bool
	{
		if (!\RainLoop\Plugins\Helper::ValidateWildcardValues($oAccount->Email(), $this->oConfig->Get('plugin', 'tulio_allowed_emails', ''))) {
			return false;
		}

		$this->oLogger->Write("Tulio: Try to change password for {$oAccount->Email()}");

		$sHost = $this->oConfig->Get('plugin', 'tulio_host');
		$sPort = $this->oConfig->Get('plugin', 'tulio_port');

		$HTTP = \SnappyMail\HTTP\Request::factory();
		$postvars = array(
			'email'    => $oAccount->Email(),
			'password' => (string) $oPrevPassword,
			'new'      => (string) $oNewPassword,
		);
		$response = $HTTP->doRequest('POST', 'https://'.$sHost.':'.$sPort.'/reset/mail/', \http_build_query($postvars));
		if (!$response) {
			$this->oLogger->Write("Tulio[Error]: Response failed");
			return false;
		}
		if ('==ok==' != $response->body) {
			$this->oLogger->Write("Tulio[Error]: Response: {$response->status} {$response->body}");
			return false;
		}
		return true;
	}
}
