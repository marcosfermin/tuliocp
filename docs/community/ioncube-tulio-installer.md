# Install Ioncube

::: warning Third-party project, built for HestiaCP
This installer is maintained by a third party for **HestiaCP**, the project
TulioCP was forked from. It is not maintained by TulioCP and has not been tested
against it. The script assumes upstream paths such as `/usr/local/hestia`, so it
will need adjusting for TulioCP, which installs to `/usr/local/tulio`. Read it
before running it. Report problems with it to its own repository, not to
TulioCP.
:::

By [Jaap Marcus](https://github.com/jaapmarcus/)  
[Source code](https://github.com/jaapmarcus/ioncube-hestia-installer)

Simple tool to download and install [Ioncube loaders](https://www.ioncube.com/loaders.php) for each available PHP version that is installed.

```bash
wget https://raw.githubusercontent.com/jaapmarcus/ioncube-hestia-installer/main/install_ioncube.sh
chmod +x install_ioncube.sh
# Review the script and adjust the panel paths for TulioCP before running it.
./install_ioncube.sh
```
