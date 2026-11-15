# Darkslide Privacy Policy

**Effective date:** November 15, 2026 · **Version 1.0**

Darkslide is a personal iPhone and iPad app for Fujifilm X cameras: it keeps film-simulation
recipes, writes them to the camera's custom slots over USB, develops RAW files on the camera, and
imports photos from the camera's memory card. It is an independent fork of Fuji Cookbook and is
not distributed through the App Store; it is built from the source code in this repository.

## 1. Who is responsible

Philipp Bevier, hello@bevier.cloud.

This policy covers the app as built from this repository and any email you send to that address.
If someone else builds and distributes the app from this source, they are responsible for their
build.

## 2. The short version

- **Your data stays on your device.** There is no account and no Darkslide server. The app
  contains no analytics, tracking, advertising or crash-reporting service.
- **Information leaves the device only when you make it:** by using the optional AI scan, which
  sends a screenshot to the AI provider whose API key you entered; by saving or sharing files
  yourself; or by turning on iCloud sync where the build supports it (Section 9).
- **Reports and feedback are not collected** at the moment (Section 10).
- I don't sell personal information or use it for advertising.

## 3. What the app stores on your device

- **Your library:** recipes (names, notes, tags, settings, credits), rolls, sample photos you
  add, and photos the camera develops for you.
- **Settings,** including the cameras you marked as yours and the folder you chose for imports.
- **Location tracks** you record (Section 5).
- **An import list:** for each file already imported from the camera, its name, size and capture
  time, so the Light Table can hide what you already have.
- **Diagnostic information:** app logs, the report from the most recent camera connection,
  backups of your camera's slot settings, and screenshots waiting to be scanned. Logs record
  outcomes, errors and technical identifiers, not recipe contents or locations.
- **In the iOS Keychain:** AI API keys you enter, and a random value used to code camera serial
  numbers (Section 6). Both use a device-only setting, so they don't sync through iCloud Keychain
  or move to another device in a backup.

Device and iCloud backups can include the app's local data under your Apple settings. Some files,
such as developed photos the app recovered after an interrupted save, are visible in the Files app
under Darkslide.

## 4. Permissions the app asks for

- **Camera.** iOS uses this permission for cameras connected over USB. Darkslide asks for it to
  talk to your Fujifilm camera. It never uses the iPhone's or iPad's own camera or microphone.
- **Files and Folders.** iOS asks for this as well before the app can read the connected camera's
  contents.
- **Add to Photos.** Only adding, never reading: to save developed photos and photos imported from
  the camera into your photo library. When you pick a photo (for example a RAW file or a
  screenshot), the iOS picker gives the app only the photos you select.
- **Location, while using the app.** Only to record a location track (Section 5). It is asked for
  the first time you start a track.

The app doesn't use contacts or Bluetooth.

## 5. Location tracks and geotagging

- **When:** only between **Start** and **Stop** in Camera ▸ Location Track. Once started, recording
  continues while the screen is locked or the app is in the background, and iOS shows the location
  indicator the whole time. Quitting the app ends the recording.
- **What:** time, latitude, longitude, altitude (when known) and accuracy, roughly every 10 metres
  or once a minute.
- **Where:** one file per track in the app's own storage on this device. Tracks are not part of
  iCloud sync and are never sent anywhere by the app; device backups can include them.
- **How long:** until you delete them. There is no automatic expiry. Delete a single track in
  Camera ▸ Location Track; deleting the app deletes all of them. Clear Diagnostics does not touch
  tracks.
- **Use:** when you import photos from the camera with **Add Location** turned on, each photo gets
  the position recorded at the time it was taken. JPEG and HEIF files get it written into the
  file; RAF files saved to a folder get an XMP sidecar file beside them; photos saved to your photo
  library also get it as the photo's location. After that, the position travels with the photo
  wherever you save or share it.

## 6. Your camera and USB

When you connect a Fujifilm camera over USB, the app talks to it directly, only while it is
connected. It reads what the camera reports about itself (model, firmware, serial number,
capabilities) and the recipes in its custom slots. It writes to those slots only when you push a
recipe, and reads each write back.

- **Developing RAW files:** the app sends the RAW file to the camera, retrieves the JPEG it makes,
  and removes that temporary JPEG from the camera.
- **Importing photos (Light Table):** the app lists the photos on the memory card, shows previews,
  and copies the ones you select to your photo library or to a folder you choose in Files (on the
  device, in iCloud Drive or on an external drive). It never deletes or changes anything on the
  memory card. Files are copied as the camera wrote them, with their metadata (Section 8).

The camera's serial number isn't stored or logged in readable form. The app keeps only a coded
version: a short hash keyed to the random value in this device's Keychain, which never leaves the
device.

## 7. Optional AI scan

AI scanning is off by default. It works with your own account and API key at Anthropic or OpenAI.
To use it, you turn it on in Settings, confirm the notice and enter your key.

- **What is sent:** the screenshot you choose, resized and re-encoded as a new JPEG without the
  original's metadata (such as EXIF or location), plus instructions for reading the recipe. It goes
  straight from your device to the provider (`api.anthropic.com` or `api.openai.com`). Anything
  visible in the image is visible to the provider.
- **Model list:** setting up AI features also asks the provider which models your account can
  use. That request carries your API key but no images or library content.
- **Share Extension:** you can scan from other apps through the share sheet. A screenshot that
  can't be scanned right away can be saved on the device and is retried when you open the app.
  Saved screenshots are removed after 30 days (or when more than 20 are waiting), and Clear
  Diagnostics removes them at once.
- **Your provider:** you use the provider under your own agreement with it; its terms, retention
  and training settings apply. I don't receive your images, the responses or your key. See
  [Anthropic's](https://www.anthropic.com/legal/privacy) and
  [OpenAI's](https://openai.com/policies/privacy-policy/) privacy information.
- **Your key** is stored in the Keychain (device-only) and sent only to the provider it belongs to.
  Settings ▸ Delete API Keys removes it; to revoke it completely, also revoke it in your provider
  account.

Like any internet request, these requests carry connection details such as your IP address.

## 8. Files you save or share

Exports and shares are copies you make and send where you choose; the app doesn't send them
anywhere itself. This covers recipe and roll exports (`.fujirecipe`), library backups, camera slot
backups, developed photos and imported photos.

Photos keep the metadata the camera wrote, which can include camera settings and, if the camera or
the geotagging added it, the location. Check a photo before sharing it if that matters to you.

## 9. iCloud sync

The app has an iCloud sync switch in Settings, off by default. If it is on in a build that has
the iCloud capability, your library (recipes, rolls, sample photos and developed photos) syncs
through your own private iCloud database, which I can't access, and the app may wake briefly in
the background on silent CloudKit notifications to fetch changes. API keys, AI settings,
diagnostics and location tracks are never synced.

The builds I make for my own devices are signed with a free Apple developer account that can't
use iCloud, so sync doesn't work in them.

## 10. Reports and feedback

Darkslide doesn't collect reports or feedback at the moment. The app's diagnostics report
(Settings ▸ Diagnostics Report) can be read and copied on the device but offers no way to send it,
and there is no feedback form.

If you email me yourself, I receive your email address, your message and any attachments, and use
them only to answer you. I delete them when they are no longer needed for that, at the latest after
three years. My email is hosted by a third-party provider.

## 11. Your controls

- **Location Track:** start and stop recording; delete tracks.
- **AI features switch and Delete API Keys** (Section 7).
- **Clear Diagnostics:** removes logs, saved screenshots and camera test data, including backups
  of your camera's original settings (the app offers to export them first). It keeps what the app
  last wrote to each slot, so it can notice when a slot changed.
- **iOS Settings:** turn off Location, Photos or Camera access for Darkslide at any time.
- **Deleting the app** removes its local data. Keychain items (API keys, the serial-coding value)
  can survive; use Delete API Keys first.

## 12. Your rights

Under the GDPR you have the right to access, correct or delete personal information I hold about
you, to restrict or object to its processing, to receive a copy of it, and to complain to a data
protection authority. In practice the only personal information I can hold is email you sent me;
everything else stays on your device and under your control. To make a request, email
hello@bevier.cloud.

Where I process your email, the legal basis is answering your request (Art. 6(1)(b) GDPR) and my
legitimate interest in replying to messages about the app (Art. 6(1)(f) GDPR).

## 13. Changes

When the app changes how it handles information, I update this policy, its date and version. The
history of every change is in this repository.

## 14. Contact

Philipp Bevier · hello@bevier.cloud
