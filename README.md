# Amulet

A tiny macOS app that asks which Chrome profile should open each link you click.
A small item with a big effect.

You set Amulet as your default browser. When any app opens a link, a small panel
shows the link and your profiles; you pick one and the link opens in Chrome in that
profile.

It is one Swift file with no dependencies. It makes no network requests, reads no
files, and needs no permissions.

## Requirements

- macOS with Google Chrome installed
- Xcode Command Line Tools, for `swiftc` (`xcode-select --install`)

It has only been built and run on macOS 27.

## Setup

1. List your profiles:

   ```sh
   cp Profiles.example.swift Profiles.swift
   ```

   Edit `Profiles.swift`. For each profile you need its folder name: open
   `chrome://profile-internals` in Chrome, click a profile to expand it, and take the
   last part of its "Profile Path" (for example `Default` or `Profile 1`).

   Only list folders that exist. Chrome creates a new, empty profile when it is given
   a folder name it doesn't know.

2. Build and install into `~/Applications`:

   ```sh
   ./build.sh
   ```

3. Make it the default browser:

   ```sh
   ~/Applications/Amulet.app/Contents/MacOS/Amulet --make-default
   ```

To change the list later, edit `Profiles.swift` and run `./build.sh` again.
`Profiles.swift` is ignored by git, so your list stays on your machine.

## Using it

| Key | Action |
| --- | --- |
| `1`–`9` | Open the link in that profile |
| `↑` `↓` then `Return` | Choose with the keyboard |
| Click | Open the link in that profile |
| `Esc` | Drop the link |

If several links arrive at once, the picker asks about them one at a time.

## How it works

- `Info.plist` declares the app as a handler for `http` and `https` links, which is
  what lets macOS use it as the default browser.
- When a link arrives, the app shows the panel and waits for a choice.
- It then runs `open -n -b com.google.Chrome --args --profile-directory=<folder> <url>`.
  Chrome hands the link to its running copy, in that profile.

The profile list is compiled in because macOS does not let other apps read Chrome's
own profile list.

## Notes

- Links you click inside Chrome stay in Chrome. Only links opened by other apps go
  through the picker.
- Chrome will occasionally point out that it is no longer the default browser.
- To undo, set Chrome as the default web browser in System Settings.
- The app has no Dock icon or menu. To stop it, run `pkill -x Amulet`; it starts
  again on the next link.
