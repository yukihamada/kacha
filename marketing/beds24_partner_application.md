# Beds24 Partner Program Application

**To:** Beds24 Partnerships / Integration Team
**Subject:** KAGI iOS App - Beds24 API v2 Integration Partner Application

---

Dear Beds24 Team,

I'm writing to apply for a listing on the Beds24 partner/integration page for our iOS app, **KAGI**.

## Who we are

We are **Enabler DAO**, a small team building open-source tools for vacation rental hosts. Our philosophy is local-first and privacy-focused — user data stays on their device, and all our code is open source (MIT license) on GitHub.

- Website: https://kacha.pasha.run
- GitHub: https://github.com/yukihamada/kacha
- Organization: https://enablerdao.com

## What KAGI does

KAGI is a mobile-first PMS companion app for iOS that extends Beds24 with three capabilities hosts frequently request:

1. **Smart lock automation** — Connects SwitchBot, Sesame, Nuki, and Qrio smart locks to Beds24 bookings. Hosts can control locks from their iPhone and guests receive secure access instructions automatically.

2. **AI guest messaging** — Pulls guest messages from Beds24 and generates context-aware reply suggestions in multiple languages. Hosts tap to send, reducing response time from minutes to seconds.

3. **E2E encrypted guest sharing** — Generates secure guest cards (WiFi, door codes, house manual, area guides) with AES-256-GCM encryption. The server never sees plaintext guest data.

## Technical integration details

KAGI uses the following Beds24 API v2 endpoints:

| Endpoint group | Usage |
|---|---|
| **Bookings** | Sync reservations, check-in/out status, guest details |
| **Messages** | Read and send guest messages across all channels |
| **Properties** | Property list, room configuration, mapping to smart devices |
| **Channels/Settings** | Channel identification (Airbnb/Booking.com/direct) for dashboard display |

Authentication is handled via API v2 invite codes. The app respects rate limits and caches data locally to minimize API calls.

## User value proposition

Beds24 users benefit from KAGI because:

- **Mobile gap**: Beds24's strength is its powerful web dashboard, but hosts frequently need to unlock doors or reply to guests while away from their desk. KAGI fills this mobile gap.
- **Smart lock integration**: This is the #1 feature request we hear from Beds24 users. KAGI bridges PMS data with physical access control.
- **Privacy**: Unlike competitors that store guest data on their servers, KAGI's local-first approach means sensitive information (door codes, WiFi passwords) never leaves the host's device unless explicitly shared via E2E encryption.

## Current status

- **TestFlight beta**: https://testflight.apple.com/join/CTmyqV6H
- **Active beta testers**: Growing community of hosts in Japan
- **App Store submission**: Planned for Q2 2026
- **Pricing**: Free for 1 property; Pro plan for multi-property hosts

## Our request

We would like to be listed on the Beds24 integrations/partner page as a compatible iOS app. We are happy to:

- Provide technical documentation for the integration
- Co-promote the partnership (blog post, social media, in-app Beds24 badge)
- Support mutual users with setup and troubleshooting
- Share usage analytics (anonymized) to help improve the Beds24 API
- Implement any additional API features you recommend

## Contact

- **Name**: Yuki Hamada
- **Email**: mail@yukihamada.jp
- **GitHub**: https://github.com/yukihamada
- **Organization**: Enabler DAO

Thank you for considering our application. Beds24 is the backbone of our hosts' operations, and we want to make the mobile experience as strong as the web dashboard.

Best regards,
Yuki Hamada
Enabler DAO
