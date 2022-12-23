
<h1 align="center">
  <br>
  <a href="https://github.com/HotCakeX"><img src="https://avatars.akamai.steamstatic.com/48612a0ea22fed72aea709509281d0b4e4a4e227_full.jpg" alt="Markdownify" width="200"></a>
  <br>
  Harden Windows Security
  <br>
</h1>

<h4 align="center">Harden Windows 11 Safely, securely and without breaking anything</h4>

<p align="center">
	
	
  <a href="https://www.powershellgallery.com/packages/Harden-Windows-Security/">
    <img src="https://img.shields.io/powershellgallery/v/Harden-Windows-Security?style=for-the-badge"
         alt="PowerShell Gallery">
  </a>
	
	
  <a href="https://www.powershellgallery.com/packages/Harden-Windows-Security/">
    <img src="https://img.shields.io/powershellgallery/dt/Harden-Windows-Security?style=for-the-badge"
         alt="PowerShell Gallery Downloads count">
  </a>
 
</p>

<p align="center">
  <a href="#Hardening-Categories">Hardening Categories</a> •
  <a href="#how-to-use">How To Use</a> •
  <a href="#download">Download</a> •
  <a href="#credits">Credits</a> •
  <a href="#related">Related</a> •
  <a href="#license">License</a>
</p>

![screenshot](https://raw.githubusercontent.com/amitmerchant1990/electron-markdownify/master/app/img/markdownify.gif)

## Hardening Categories


* Commands that require Administrator Privileges
  - Windows Security aka Defender
  - Attack surface reduction rules
  - Bitlocker Settings 
  - TLS Security
  - Lock Screen
  - UAC (User Account Control)
  - Device Guard
  - Windows Firewall
  - Optional Windows Features
  - Windows Networking
  - Miscellaneous Configurations  
* Commands that don't require Administrator Privileges
  - Non-Admin Commands


## How To Use

To run the script, first you need to go to the top of this page, select Code and then select Download Zip, or just click here to start the download:[Download the Zip package](https://github.com/HotCakeX/Harden-Windows-Security/archive/refs/heads/main.zip) then extract it to a folder


```PowerShell
# Set Execution policy to bypass for the current process which is temporary only for current PowerShell instance 
$ Set-ExecutionPolicy Bypass -Scope Process

# use CD command to change the working directory to the folder where you've downloaded and extracted the zip files, like this example:
$ cd "C:\Users\$env:username\Downloads\Harden-Windows-Security-main\Harden-Windows-Security-main\"

# use this command to run the script
$ .\Harden-Windows-Security.ps1

```

> **Note**
> If you're using Linux Bash for Windows, [see this guide](https://www.howtogeek.com/261575/how-to-run-graphical-linux-desktop-applications-from-windows-10s-bash-shell/) or use `node` from the command prompt.


## Download

You can [download](https://github.com/amitmerchant1990/electron-markdownify/releases/tag/v1.2.0) the latest installable version of Markdownify for Windows, macOS and Linux.

## Emailware

Markdownify is an [emailware](https://en.wiktionary.org/wiki/emailware). Meaning, if you liked using this app or it has helped you in any way, I'd like you send me an email at <bullredeyes@gmail.com> about anything you'd want to say about this software. I'd really appreciate it!

## Credits

This software uses the following open source packages:

- [Electron](http://electron.atom.io/)
- [Node.js](https://nodejs.org/)
- [Marked - a markdown parser](https://github.com/chjj/marked)
- [showdown](http://showdownjs.github.io/showdown/)
- [CodeMirror](http://codemirror.net/)
- Emojis are taken from [here](https://github.com/arvida/emoji-cheat-sheet.com)
- [highlight.js](https://highlightjs.org/)

## Related

[markdownify-web](https://github.com/amitmerchant1990/markdownify-web) - Web version of Markdownify

## Support

<a href="https://www.buymeacoffee.com/5Zn8Xh3l9" target="_blank"><img src="https://www.buymeacoffee.com/assets/img/custom_images/purple_img.png" alt="Buy Me A Coffee" style="height: 41px !important;width: 174px !important;box-shadow: 0px 3px 2px 0px rgba(190, 190, 190, 0.5) !important;-webkit-box-shadow: 0px 3px 2px 0px rgba(190, 190, 190, 0.5) !important;" ></a>

<p>Or</p> 

<a href="https://www.patreon.com/amitmerchant">
	<img src="https://c5.patreon.com/external/logo/become_a_patron_button@2x.png" width="160">
</a>

## You may also like...

- [Pomolectron](https://github.com/amitmerchant1990/pomolectron) - A pomodoro app
- [Correo](https://github.com/amitmerchant1990/correo) - A menubar/taskbar Gmail App for Windows and macOS

## License

MIT

---

> [amitmerchant.com](https://www.amitmerchant.com) &nbsp;&middot;&nbsp;
> GitHub [@amitmerchant1990](https://github.com/amitmerchant1990) &nbsp;&middot;&nbsp;
> Twitter [@amit_merchant](https://twitter.com/amit_merchant)
