# Accessibility

Midas should be usable by everyone who takes part in meetings, including people who use assistive technology. We treat accessibility barriers as bugs.

## Our commitment

- **The panel** follows Apple's [accessibility guidelines](https://developer.apple.com/design/human-interface-guidelines/accessibility) as the goal: it should work with VoiceOver, the keyboard and larger text, and not rely on color alone.
- **The website** aims for [WCAG 2.2](https://www.w3.org/TR/WCAG22/) level AA.
- Pull requests are reviewed for accessibility, and fixing a reported barrier comes before new features.

## Supported environments

- **App:** macOS 14.4 or later on Apple Silicon, with macOS's built-in assistive technology (VoiceOver, Zoom, Full Keyboard Access, Increase Contrast, Reduce Motion).
- **Website:** current versions of Safari, Chrome, Firefox and Edge.

## What works today

- The main actions have global keyboard shortcuts that work from any app: **⌃⌥A** answer, **⌃⌥M** show or hide the panel, **⌃⌥P** pause or resume listening.
- The panel is built from standard SwiftUI controls, and its buttons have descriptions (shown on hover).
- Midas shows what other participants say as live text, which can help people who are deaf or hard of hearing follow a meeting.
- The website has a skip link, visible keyboard focus, semantic headings and landmarks, alt text and table headers, and turns off smooth scrolling when Reduce Motion is on.

## Known limitations

- **Text size:** the panel uses fixed font sizes and doesn't follow macOS's text size settings yet.
- **VoiceOver:** the panel hasn't been tested with VoiceOver yet, and some icon-only buttons (copy, refresh, settings) may not have spoken labels.
- **Keyboard:** apart from the global shortcuts, moving around inside the panel with the keyboard hasn't been tested.
- **Screen capture:** on purpose, the panel is hidden from screen sharing and screen recording. Assistive tools that work from screenshots or screen recordings can't see it.
- **Captions:** transcription is automatic and isn't a replacement for professional captioning. It only covers other participants, doesn't tell speakers apart, and its accuracy depends on audio quality, language and accent.
- **The website** hasn't had a formal audit; its accessibility is based on our own checks.

## Report a barrier

If something in Midas or on the website is hard or impossible for you to use, please tell us:

- **[Open an accessibility issue](https://github.com/onurkagan/midas-meeting-copilot/issues/new?template=accessibility.yml)**, or
- if you'd rather not post publicly, email [onurkaganaldemir@gmail.com](mailto:onurkaganaldemir@gmail.com).

Tell us what you were trying to do, what got in the way, and which assistive technology you use, if any. We aim to reply within 7 days. Midas is maintained by one person in their spare time, so larger fixes may take longer, but we'll keep you posted.

Contributions that improve accessibility are especially welcome; see [CONTRIBUTING.md](CONTRIBUTING.md).
