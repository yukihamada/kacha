# KAGI - Free iOS app for Beds24 smart lock automation

Hi everyone,

I'm a vacation rental host and developer, and I've built an iOS app called **KAGI** that connects directly to the Beds24 API v2 to solve a problem I kept running into: managing smart locks and guest communication across multiple properties from my phone.

## What it does

KAGI is a mobile-first companion app for Beds24 that adds:

- **Automatic booking sync** — Connect your Beds24 account with an invite code and all your bookings appear on a clean calendar view. New reservations sync in the background via push notifications.
- **Smart lock control** — Register your SwitchBot, Sesame, Nuki, or Qrio locks and control them with one tap. Locks are automatically assigned to properties so the right door code goes to the right guest.
- **AI guest auto-reply** — When a guest message comes in via Beds24 (Airbnb, Booking.com, direct), KAGI suggests 3 AI-generated reply options. Tap to send. Works in multiple languages.
- **E2E encrypted guest sharing** — Generate a secure guest card with WiFi password, door access instructions, house rules, and check-in/out times. The link uses URL-fragment encryption (AES-256-GCM) so even our server never sees the plaintext.
- **Philips Hue scene control** — Set up welcome/goodbye lighting scenes that trigger based on check-in status.
- **Multi-property dashboard** — Swipe between properties, see occupancy at a glance, track revenue by platform.

## How it works

1. Open KAGI and tap "Connect Beds24"
2. Enter your Beds24 API v2 invite code (generated from Beds24 Settings > API)
3. Your bookings, properties, and guest messages sync automatically
4. Add your smart locks (SwitchBot/Sesame/Nuki/Qrio) to each property
5. Guests receive a secure link with everything they need — WiFi, door code, house manual

Everything is local-first. Your data lives on your iPhone, not on our servers. The server only stores encrypted blobs for the sharing feature.

## Screenshots

Here's what you'd see in the app:

- **Dashboard**: A calendar view showing upcoming check-ins/check-outs across all properties, color-coded by platform (Airbnb orange, Booking.com blue, direct green)
- **Booking detail**: Guest name, dates, platform, guest message thread with AI reply suggestions
- **Lock control**: Large unlock/lock buttons per device, battery status, activity log
- **Guest card**: A clean mobile-friendly page the guest sees — property photo, WiFi credentials, door instructions, local area tips, all in the guest's language
- **Settings**: Beds24 connection status, connected devices, team member management

## Pricing

- **Free**: 1 property, all features including Beds24 sync and smart lock control
- **Pro** (980 JPY/month): Unlimited properties, E2E encrypted sharing, background sync, team management

## Looking for beta testers

The app is currently in TestFlight beta and I'd love feedback from other Beds24 users:

**TestFlight**: https://testflight.apple.com/join/CTmyqV6H

Specifically interested in hearing about:
- Which smart lock brands you use (planning to add more integrations)
- How you currently handle guest key handoff
- Any Beds24 API features you wish a mobile app supported
- Bugs, crashes, or UX issues

## Technical details

- Built with SwiftUI + SwiftData (iOS 17+)
- Server component: Rust (axum) on Fly.io — only handles encrypted sharing links and Universal Links
- Uses Beds24 API v2 endpoints: bookings, messages, channels/settings, properties
- Open source: https://github.com/yukihamada/kacha (MIT license)

Happy to answer any questions. This grew out of my own frustration managing 3 properties and I hope it's useful to others here too.

Cheers,
Yuki
