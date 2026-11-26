# TukTak24 Gift Card Portal (Google Apps Script)

This folder contains the first implementation of the TukTak24 gift-card portal. It is separate from the current storefront.

## Features
- Public gift-card code verification (discount, expiry, status)
- Admin password login
- Create 1–100 unique codes per batch
- One-time redemption with customer name, mobile and order number
- Google Sheets storage and recent-card list
- LockService prevents two admins redeeming the same code simultaneously

## Setup (free Google account)
1. Open https://script.google.com/ and create a new Apps Script project.
2. Copy `Code.gs` into the editor's `Code.gs` file.
3. Add an HTML file named `Index` and copy `Index.html` into it.
4. In the function selector, run `setupGiftCardSystem`. Approve the Google permissions.
5. Open **Execution log**. Save the spreadsheet URL and the initial admin password somewhere safe.
6. In **Project Settings → Script Properties**, change `ADMIN_PASSWORD` to a strong private password. Never share it in chat or put it in the HTML file.
7. Deploy → New deployment → Web app. Execute as **Me**. Choose access **Anyone** (public code verification needs this), then Deploy.
8. Copy the Web app URL. Open it to test public verification and admin login.

## Important
- Do not publish or share the spreadsheet itself. Only the Apps Script web app URL is public.
- The admin password is stored in Script Properties, not in browser code.
- Anyone with the public URL can check whether a code exists. Do not store sensitive customer details beyond what is needed for redemption.
- The Apps Script deployment must be authorized by the account owner. ChatGPT cannot approve Google permissions or deploy inside the user's account.
