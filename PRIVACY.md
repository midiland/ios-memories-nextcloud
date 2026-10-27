# Privacy Policy

_Last updated: October 27, 2026_

This policy covers **Memories for iOS** (the "app"), an unofficial iOS client for the
[Memories](https://github.com/pulsejet/memories) photo app for Nextcloud, published by Midiland.

## Summary

The app does not collect any data. The developer runs no server, and the app contains no analytics,
advertising, tracking or crash reporting. The app only talks to the Nextcloud server that **you**
choose, and to the map services used by the Memories interface when you open a map.

## Your Nextcloud server

When you sign in, the app connects to the Nextcloud server whose address you enter, using the official
Nextcloud Login Flow. Your photos, albums, metadata and account details are exchanged only between the
app and that server. Whoever runs that server (you, your organization or your hosting provider) is
responsible for the data it stores, under its own privacy policy.

## Data stored on your device

- **Server address and app password**: stored in the iOS Keychain, only on this device (not synced to
  iCloud). Signing out revokes the app password on the server and deletes it from the device.
- **Memories interface files**: a copy of the Memories web interface, downloaded from your server so the
  app opens quickly.
- **Session data and cache**: cookies and cached content of the web interface, deleted when you sign out.
- **"On this day" widget photos**: if you add the widget to your home screen, small copies of a few
  photos taken on this date in past years are downloaded from your server and stored in a folder shared
  between the app and its widget, with the list of photos you removed from it. They are not backed up,
  are never sent anywhere except from your own server, and are deleted when you sign out or remove the
  widget.
- **Device photo settings and matches**: which device folders you chose to show, and which device photos
  were found to already exist on your server.

None of this data leaves your device, except to your own Nextcloud server.

## Photo library

If you enable device photos (Settings > Device Folders), the app asks for access to your photo library.
It reads photos and their metadata (date, size, dimensions, file name) to show them in your timeline and
to hide those already on your Nextcloud server. Device photos are processed on the device and are never
uploaded or sent anywhere by the app. You can revoke access at any time in iOS Settings.

## Local network

The app may ask for local network access so that it can reach a Nextcloud server on your home or office
network. It also runs a small web server reachable only from the device itself (127.0.0.1), which
serves the interface to the app.

## Third-party services

When you open a map, the Memories interface loads map tiles and place search results from third-party
services, depending on the map style chosen in Memories: OpenStreetMap, OpenTopoMap or Esri ArcGIS.
These services receive your IP address and the map area being viewed, under their own privacy policies.
Your Nextcloud server may also be configured by its administrator to use other services.

## Children

The app is not directed at children and collects no data from anyone.

## Changes

Changes to this policy will be published on this page, with a new "Last updated" date.

## Contact

Questions about this policy: contact@midiland.fr, or open an issue on the project's GitHub repository.
