import { defineConfig } from 'vitepress';
import { version } from '../../package.json';

export default defineConfig({
	lang: 'en-US',
	title: 'Tulio Control Panel',
	description: 'Documentation for TulioCP, an open-source web server control panel.',

	// The docs site is published under https://tuliocp.com/docs/panel/, alongside
	// the rest of the project website. Keep this in sync with the in-panel
	// documentation links (see web/templates and web/api/index.php).
	base: '/docs/panel/',

	lastUpdated: true,
	cleanUrls: false,

	// `head` entries are emitted verbatim — VitePress does not prepend `base` to
	// them the way it does for `themeConfig.logo`, so these hrefs must spell out
	// /docs/panel/ themselves. A bare /logo.svg here would silently resolve to the
	// marketing site's asset at the domain root.
	head: [
		['link', { rel: 'icon', sizes: '32x32', href: '/docs/panel/favicon.ico' }],
		['link', { rel: 'icon', type: 'image/svg+xml', href: '/docs/panel/logo.svg' }],
		[
			'link',
			{ rel: 'apple-touch-icon', sizes: '180x180', href: '/docs/panel/apple-touch-icon.png' },
		],
		['link', { rel: 'manifest', href: '/docs/panel/site.webmanifest' }],
		['meta', { name: 'theme-color', content: '#2b5b96' }],
	],

	themeConfig: {
		logo: '/logo.svg',

		nav: nav(),

		socialLinks: [{ icon: 'github', link: 'https://github.com/marcosfermin/tuliocp' }],

		sidebar: { '/': sidebarDocs() },

		outline: [2, 3],

		editLink: {
			pattern: 'https://github.com/marcosfermin/tuliocp/edit/main/docs/:path',
			text: 'Edit this page on GitHub',
		},

		footer: {
			message:
				'Released under the GPLv3 licence. A fork of HestiaCP, itself derived from VestaCP — not affiliated with either project.',
			copyright: 'Copyright © 2026 the TulioCP contributors',
		},
	},
});

/** @returns {import("vitepress").DefaultTheme.NavItem[]} */
function nav() {
	return [
		{ text: 'Documentation', link: '/', activeMatch: '^/$' },
		{ text: 'Install', link: '/install' },
		{ text: 'Attribution', link: '/attribution' },
		{ text: 'Project website', link: 'https://tuliocp.com/' },
		{
			text: `v${version}`,
			items: [
				{
					text: 'Changelog',
					link: 'https://github.com/marcosfermin/tuliocp/blob/main/CHANGELOG.md',
				},
				{
					text: 'Contributing',
					link: 'https://github.com/marcosfermin/tuliocp/blob/main/CONTRIBUTING.md',
				},
				{
					text: 'Security policy',
					link: 'https://github.com/marcosfermin/tuliocp/blob/main/SECURITY.md',
				},
			],
		},
	];
}
/** @returns {import("vitepress").DefaultTheme.SidebarItem[]} */
function sidebarDocs() {
	return [
		{
			text: 'Introduction',
			collapsed: false,
			items: [
				{ text: 'Getting started', link: '/introduction/getting-started' },
				{ text: 'Best practices', link: '/introduction/best-practices' },
			],
		},
		{
			text: 'User guide',
			collapsed: false,
			items: [
				{ text: 'Account', link: '/user-guide/account' },
				{ text: 'Backups', link: '/user-guide/backups' },
				{ text: 'Cron jobs', link: '/user-guide/cron-jobs' },
				{ text: 'Databases', link: '/user-guide/databases' },
				{ text: 'DNS', link: '/user-guide/dns' },
				{ text: 'File manager', link: '/user-guide/file-manager' },
				{ text: 'Mail domains', link: '/user-guide/mail-domains' },
				{ text: 'Notifications', link: '/user-guide/notifications' },
				{ text: 'Packages', link: '/user-guide/packages' },
				{ text: 'Statistics', link: '/user-guide/statistics' },
				{ text: 'Users', link: '/user-guide/users' },
				{ text: 'Web domains', link: '/user-guide/web-domains' },
			],
		},
		{
			text: 'Server administration',
			collapsed: false,
			items: [
				{ text: 'Backup & restore', link: '/server-administration/backup-restore' },
				{ text: 'Configuration', link: '/server-administration/configuration' },
				{ text: 'Customisation', link: '/server-administration/customisation' },
				{ text: 'Databases & phpMyAdmin', link: '/server-administration/databases' },
				{ text: 'DNS clusters & DNSSEC', link: '/server-administration/dns' },
				{ text: 'Email', link: '/server-administration/email' },
				{ text: 'File manager', link: '/server-administration/file-manager' },
				{ text: 'Firewall', link: '/server-administration/firewall' },
				{ text: 'OS upgrades', link: '/server-administration/os-upgrades' },
				{ text: 'Rest API', link: '/server-administration/rest-api' },
				{ text: 'SSL certificates', link: '/server-administration/ssl-certificates' },
				{ text: 'Web templates & caching', link: '/server-administration/web-templates' },
				{ text: 'Troubleshooting', link: '/server-administration/troubleshooting' },
			],
		},
		{
			text: 'Contributing',
			collapsed: false,
			items: [
				{ text: 'Building Packages', link: '/contributing/building' },
				{ text: 'Development', link: '/contributing/development' },
				{ text: 'Documentation', link: '/contributing/documentation' },
				{ text: 'Quick install app', link: '/contributing/quick-install-app' },
				{ text: 'Releasing', link: '/contributing/releasing' },
				{ text: 'Testing', link: '/contributing/testing' },
				{ text: 'Translations', link: '/contributing/translations' },
			],
		},
		{
			text: 'Community',
			collapsed: false,
			items: [
				{ text: 'Nginx cache plugin', link: '/community/tulio-nginx-cache' },
				{
					text: 'Ioncube installer',
					link: '/community/ioncube-tulio-installer',
				},
				{ text: 'Install script generator', link: '/community/install-script-generator' },
			],
		},
		{
			text: 'Reference',
			collapsed: false,
			items: [
				{ text: 'API', link: '/reference/api' },
				{ text: 'CLI', link: '/reference/cli' },
			],
		},
		{
			text: 'About',
			collapsed: false,
			items: [{ text: 'Attribution', link: '/attribution' }],
		},
	];
}
