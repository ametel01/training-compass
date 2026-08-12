# Establish the personal iPhone deployment envelope

Type: research
Status: resolved

## Question

According to current official Apple documentation, what installation and signing paths can keep this personal app usable on the owner's iPhone? Compare the relevant free provisioning, paid developer, direct development, TestFlight, expiration, re-signing, device, capability, and long-term maintenance constraints without assuming a public App Store release.

## Answer

Use a two-stage deployment envelope: free Xcode Personal Team signing only for prototyping and physical-device HealthKit validation, then paid Apple Developer Program development signing through Xcode for sustained owner-only use. Paid Ad Hoc is an optional release-like direct-install variant; internal TestFlight is an optional convenience path, but every build expires after 90 days. HealthKit and Background Modes are available to both free and paid accounts, so the paid membership addresses operational durability rather than unlocking those two capabilities. None of the private paths is maintenance-free: keep the membership current, re-sign before the generated profile's expiration, validate first-launch connectivity, and provide verified export/restore for app-owned data.

Context: [Personal iPhone deployment envelope](../../../docs/research/personal-iphone-deployment-envelope.md)
