---
title: Connecting to Draw Things
order: 1
---

# Connecting to Draw Things

Tanque Studio is a companion app — it needs a running [Draw Things](https://drawthings.ai) with its API server enabled. All generation happens on the Draw Things side over gRPC.

## Setup

1. Install Draw Things from the Mac App Store and download at least one model in it.
2. In Draw Things, enable the API server: **Settings → API Server → Enable**. Note the port (default **7859**).
3. In Tanque Studio, open **Settings** (sidebar) and fill in the **Draw Things Connection** section:

- **Host** — `127.0.0.1` when Draw Things runs on this Mac; the machine's LAN IP (e.g. `192.168.1.34`) when it runs on another machine.
- **Port** — `7859` unless you changed it in Draw Things.
- **Shared Secret** — only if the server has one configured. Paste it exactly as Draw Things displays it — the spaced format (`8EA9 N6UM WYFM`) is fine, spaces are ignored.

4. Click **Test Connection**. On success the model list loads automatically.

## Empty model list?

An empty model picker almost always means a **connection or shared-secret problem** — not a broken install and not missing models.

- Is Draw Things running, with the API server enabled?
- Right host and port? For a remote machine, are both Macs on the same network?
- Does the shared secret match? A wrong secret can connect but return an empty inventory.
- Use the refresh button (circular arrow) next to the Model field in the Generate panel, or **Test Connection** in Settings, after fixing.

The host field keeps a history — use the dropdown chevron to switch between machines you've connected to before.

## Good to know

- The connection status light lives in the top-right corner of the window: green **connected** means the model inventory is loaded.
- A model only *generates* if it is actually downloaded in Draw Things. Presets and pasted configs can reference models you don't have yet — Draw Things will return no image in that case (see Troubleshooting).
