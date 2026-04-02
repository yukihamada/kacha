# Product Hunt Launch Draft

## Basic Info

**Product Name**: KAGI
**Tagline**: Automate your vacation rental with smart locks + AI guest messaging
**Website**: https://kacha.pasha.run
**Topics**: Productivity, Travel, Smart Home, Property Management, Open Source

---

## Description

### Paragraph 1 — What it is

KAGI is a free, open-source iOS app that brings smart lock automation and AI-powered guest messaging to vacation rental hosts. It connects to Beds24 (a popular channel manager for Airbnb, Booking.com, and direct bookings) and lets you manage locks, reply to guests, and share check-in info — all from your iPhone.

### Paragraph 2 — How it works

Connect your Beds24 account with an invite code and your bookings sync automatically. Register your smart locks (SwitchBot, Sesame, Nuki, or Qrio) and control them with one tap. When a guest messages you at 3am asking for the WiFi password, KAGI's AI generates three reply options in the guest's language. Tap to send. Before check-in, share a guest card — an E2E encrypted link with WiFi, door code, house rules, and local tips. The server never sees the plaintext.

### Paragraph 3 — Why we built it

We're vacation rental hosts who got tired of juggling 5 apps every day. Beds24 is great for channel management but lacks a native mobile experience. Smart lock apps don't talk to your PMS. Guest messaging is scattered across platforms. KAGI puts it all in one place. It's local-first (your data stays on your iPhone), open source (MIT license), and free for one property.

---

## Images / Screenshots to include

1. **Dashboard** — Calendar view with color-coded bookings from all channels
2. **Lock Control** — One-tap unlock with activity log
3. **AI Guest Reply** — Message thread with 3 AI-suggested replies
4. **Guest Card** — Mobile-friendly check-in page with WiFi, door code, house rules
5. **Multi-property** — Swipe between properties with occupancy overview

---

## Maker Comment

Hey Product Hunt!

I'm Yuki, and I built KAGI because I needed it myself. I've been a vacation rental host in Tokyo for 3 years, and the daily routine of switching between Beds24, SwitchBot, Airbnb, Booking.com, and LINE was driving me crazy.

The moment that pushed me to build this was getting a 3am message from a guest saying "I can't open the door." I had to open the SwitchBot app to check the lock status, switch to Beds24 to find the booking, then type out instructions in English on a tiny phone screen while half asleep.

KAGI solves this with one notification tap. The AI knows the property details and generates the right response in the guest's language.

A few things I'm particularly proud of:

- **E2E encryption** for guest cards — the server literally cannot read your guests' door codes
- **4 smart lock brands** supported — SwitchBot, Sesame, Nuki, Qrio
- **Local-first** — all data on your iPhone, no cloud dependency
- **Open source** (MIT) — https://github.com/yukihamada/kacha

Free for 1 property. Pro plan ($7/month) for multi-property hosts.

Currently in TestFlight beta: https://testflight.apple.com/join/CTmyqV6H

Would love your feedback, especially if you're a host or property manager. What features would make your life easier?

---

## First Comment (Post after launch)

Thanks for checking out KAGI! A few things I'd love feedback on:

1. **Smart lock coverage** — We support SwitchBot, Sesame, Nuki, and Qrio. What other brands should we add? (Yale, August, Schlage?)

2. **PMS integrations** — We started with Beds24 because it's what we use. Would Guesty, Hostaway, or Lodgify integrations be valuable to you?

3. **Platform** — iOS only for now. Would an Android version change your workflow?

4. **Self-hosting** — The server component is Rust + SQLite, designed to be lightweight. Anyone interested in self-hosting the encrypted sharing backend?

Happy to answer any technical questions — the codebase is fully open on GitHub.

---

## Launch Day Checklist

- [ ] Schedule launch for Tuesday 12:01 AM PT (best day for PH)
- [ ] Prepare 5 screenshots (dashboard, lock, AI reply, guest card, multi-property)
- [ ] Record 30-second GIF showing Beds24 connect → booking sync → lock unlock flow
- [ ] Draft tweets for launch day (English + Japanese)
- [ ] Notify beta testers to upvote and leave honest reviews
- [ ] Post maker comment immediately after launch
- [ ] Post first comment 30 minutes after launch
- [ ] Cross-post to Hacker News as "Show HN: KAGI — Open source smart lock automation for vacation rentals"
- [ ] Share on r/AirBnB, r/homeautomation, r/selfhosted
- [ ] Reply to every comment within 1 hour during launch day
