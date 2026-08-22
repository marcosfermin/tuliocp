# Nginx cache purge plugin for WordPress

::: warning Third-party project, built for HestiaCP
This plugin is maintained by a third party for **HestiaCP**, the project TulioCP
was forked from. It is not maintained by TulioCP and has not been tested against
it. Because TulioCP kept the upstream API surface, it is expected to work, but
that is not guaranteed — the plugin talks to the panel API and refers to the
panel by its upstream name. Report problems with it to its own repository, not
to TulioCP.
:::

By [Juniper Bouchard](https://github.com/imjuniper/)  
[View the project](https://wordpress.org/plugins/hestia-nginx-cache/) – [Source code](https://github.com/imjuniper/hestia-nginx-cache)

::: info
Requires a panel version equivalent to **HestiaCP >= 1.6.0**, as it uses the
current API. Every TulioCP release meets that requirement.
:::

WordPress plugin that automatically purges the Nginx cache after you make a website change such as updating a post or changing your theme. You also have the ability to manually purge the cache using a button in the WordPress admin bar.
