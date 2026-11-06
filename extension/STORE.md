# Chrome Web Store listing: Midas for Chrome

What to enter in the Chrome Web Store developer dashboard. `scripts/pack_extension.sh` builds the package (without the manifest's `key`, which is for Load unpacked only). After the first upload, put the ID the store gives the extension in `extension/store-id.txt` and run `./midas install`, so the store's extension may reach Midas too.

## Store listing

**Name:** Midas for Chrome

**Summary:** Sends one call tab's audio to the Midas app on your Mac, so Midas hears the call, not your other tabs.

**Category:** Productivity

**Description:**

> Midas is a free, open-source meeting assistant for macOS that transcribes your calls on your Mac and drafts replies in a private panel. Midas for Chrome is its companion for calls in Chrome: Google Meet, or Zoom and Microsoft Teams on the web.
>
> Without it, Midas hears all of Chrome's audio, so a video in another tab would end up in the meeting's transcript. With it, you click the Midas button on the call's tab, and Midas hears that tab only, until you click again or close the tab. The tab keeps playing for you, and the button reads ON while Midas hears it.
>
> On Google Meet, muting yourself in Meet also mutes Midas's microphone.
>
> Requires the Midas app on a Mac with Apple Silicon (macOS 14.4 or later): https://onurkagan.github.io/midas-meeting-copilot/. The extension sends the audio only to that app on your Mac, never over the internet. Source code: https://github.com/onurkagan/midas-meeting-copilot
>
> Tell the other participants you're transcribing, and get their consent where the law or your organization requires it.
>
> Google Chrome and Google Meet are trademarks of Google LLC. Midas is not affiliated with or endorsed by Google, Zoom or Microsoft.

**Screenshots (1280×800):** the consent page; a Meet tab with the button reading ON next to the Midas panel (take the panel picture from `bin/midas-overlay --render-preview`, since the live panel stays out of screenshots).

## Privacy practices

**Single purpose:** Send the audio of the browser tab the user chooses to the Midas app on the same Mac, which transcribes the call, and keep Midas's microphone muted when the user mutes themselves in Google Meet.

**Permission justifications:**

- `tabCapture`: captures the audio of the tab the user clicked the toolbar button on, the call Midas transcribes.
- `offscreen`: an offscreen document (reason USER_MEDIA) holds that audio stream, keeps the tab audible for the user and converts the audio to 16 kHz mono for Midas.
- `nativeMessaging`: hands the audio to the Midas app on the same Mac (native host `dev.midas.tab`); this is the only place it goes.
- `storage`: remembers that the user allowed the extension on its consent page.
- Content script on `https://meet.google.com/*`: reads only whether the Meet microphone button is muted, to mute Midas's microphone with it.

**Remote code:** No. All code is in the package.

**Data usage:** collects *Personal communications* (the call audio of the chosen tab) and *Website content* (the Meet microphone button's state). No personally identifiable information, health, financial, authentication, location, web history or user activity data.

Certify: not sold or transferred to third parties outside the approved use cases; not used or transferred for purposes unrelated to the single purpose; not used or transferred to determine creditworthiness or for lending.

**Privacy policy:** https://github.com/onurkagan/midas-meeting-copilot/blob/main/PRIVACY.md (section "Midas for Chrome", with the Limited Use statement).
